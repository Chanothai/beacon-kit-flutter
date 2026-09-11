package com.bigc.beacon_kit_android

import android.bluetooth.BluetoothDevice
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.UUID
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.anyString
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito

/**
 * เทสต์ระดับ `BeaconScanReceiver.onReceive()` เต็มเส้นทาง (ผ่าน `processProximity`
 * ที่เป็น `private` — เข้าถึงได้ทางเดียวคือเรียก `onReceive()` ตรง ๆ) — สองเรื่องที่
 * `ProximityGateStoreTest`/`IbeaconIdentityFromTest` ทดสอบแยกส่วนไม่ครอบคลุม:
 *
 * 1. **key แยกกันจริงเมื่อ major ต่างกัน ภายใน region ที่ลงทะเบียนด้วย UUID อย่าง
 *    เดียว** — นี่คือเทสต์ที่ถ้ามีตั้งแต่ ADR-20 รอบแรก (9 ก.ย. 2026 ที่ key ยังเป็น
 *    `region|MAC`) จะจับความสับสนที่ทำให้ต้องแก้รอบนี้ (11 ก.ย. 2026, `f838b00`)
 *    ได้ตั้งแต่ต้น: รอบแรกไม่มีเทสต์ไหนยืนยันว่า "สอง major ที่ต่างกันใน region
 *    กว้างเดียวกันต้องได้ state แยกกันจริงโดยไม่พึ่ง MAC เป็นตัวแยก"
 * 2. sample ที่ถอด identity จากเฟรมไม่ได้ **ต้องไม่ถูกันดันเข้า gate และห้ามมี
 *    major/minor จาก region spec โผล่มาแทน** (ADR-20 หัวข้อ 3) — ทดสอบที่ระดับ
 *    `onReceive()` เพราะจุดที่ตัดสินใจ "fallback หรือไม่" อยู่ใน `processProximity`
 *    ไม่ใช่ใน `ibeaconIdentityFrom()` เอง
 *
 * ## ทำไม mock `ScanResult`/`ScanRecord`/`BluetoothDevice`/`Intent` ได้ทั้งที่เป็น
 * final class ของ android.jar
 *
 * `mockito-core:5.0.0` ใช้ inline mock maker เป็นค่าเริ่มต้น (ดู kdoc ของ
 * `BackgroundRegionMonitorOnExitAlarmTest` ที่อธิบายไว้แล้วตอนใช้ `mockStatic` กับ
 * `SystemClock`) ซึ่ง instrument bytecode ตรง ๆ แทนการ subclass จึง mock final class
 * ได้โดยไม่ต้องเพิ่ม dependency ใหม่
 *
 * ## ทำไมไม่ต้องตั้ง `isActive = true` ของชั้น 1 เลย
 *
 * `BackgroundRegionMonitor.onSighting()`/`reconcile()` (ชั้น 1, เรียกก่อนชั้น 2 เสมอ
 * ตาม ADR-17) คืนทันทีโดยไม่มีผลข้างเคียงถ้า `store.isActive == false` (ค่า default)
 * — เทสต์ชุดนี้สนใจเฉพาะชั้น 2 (proximity) จึงปล่อย `isActive` เป็น `false` เพื่อ
 * เลี่ยง `AlarmManager`/`BluetoothLeScanner` ทั้งชุดที่ชั้น 1 อาจแตะถ้า active จริง
 * — `restoredRegions()` (ที่ชั้น 2 ใช้หา uuid) อ่านจาก `SharedPreferences` ตรง ๆ
 * ไม่ผ่านเงื่อนไข `isActive` เลย จึงเซ็ตรายการ region ได้โดยไม่ต้องเปิดใช้ชั้น 1
 */
class BeaconScanReceiverProximityTest {

    private val regionIdentifier = "bigc-test"
    private val regionUuid = UUID.fromString("e2c56db5-dffb-48d2-b060-d0f5a71096e0")

    @AfterTest
    fun tearDown() {
        // `BackgroundProximityMonitor.observer` เป็น `@Volatile var` ระดับ `object`
        // (อายุเท่า ClassLoader) — ต้องล้างเสมอ ไม่งั้นรั่วไปกระทบเทสต์อื่นในไฟล์
        // เดียวกันหรือไฟล์ถัดไปที่รันในเวิร์กเกอร์เดียวกัน (แพทเทิร์นเดียวกับ
        // `BackgroundRegionMonitorOnExitAlarmTest.tearDown`)
        BackgroundProximityMonitor.setProximityObserver(null)
    }

    private fun mockContext(prefs: FakeSharedPreferences): Context {
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.applicationContext).thenReturn(context)
        Mockito.`when`(context.getSharedPreferences(anyString(), anyInt())).thenReturn(prefs)
        return context
    }

    /** ลงทะเบียน region ด้วย **UUID อย่างเดียว** (ADR-8 wildcard) — ไม่ตั้ง major/minor */
    private fun registerWildcardRegion(context: Context) {
        BackgroundRegionStore(context).regions = listOf(
            BeaconRegionSpec(identifier = regionIdentifier, uuid = regionUuid),
        )
    }

    /** ลงทะเบียน region ที่ระบุ major/minor เจาะจง — ใช้พิสูจน์ว่า "ห้าม fallback มาใช้ค่านี้" */
    private fun registerNarrowRegion(context: Context, major: Int, minor: Int) {
        BackgroundRegionStore(context).regions = listOf(
            BeaconRegionSpec(identifier = regionIdentifier, uuid = regionUuid, major = major, minor = minor),
        )
    }

    private fun uuidBytes(uuid: UUID): ByteArray {
        val bytes = ByteArray(16)
        var most = uuid.mostSignificantBits
        var least = uuid.leastSignificantBits
        for (i in 7 downTo 0) {
            bytes[i] = (most and 0xFF).toByte()
            most = most shr 8
        }
        for (i in 15 downTo 8) {
            bytes[i] = (least and 0xFF).toByte()
            least = least shr 8
        }
        return bytes
    }

    /** manufacturer data ที่ถูกต้อง 23 ไบต์ (หลังตัด company id) — `02 15 | uuid | major | minor | txPower` */
    private fun validManufacturerData(major: Int, minor: Int, txPower: Byte = 0xC5.toByte()): ByteArray =
        BeaconRegionSpec.IBEACON_PREFIX + uuidBytes(regionUuid) +
            byteArrayOf((major shr 8).toByte(), major.toByte()) +
            byteArrayOf((minor shr 8).toByte(), minor.toByte()) +
            byteArrayOf(txPower)

    /** manufacturer data ที่ถอด identity ไม่ได้เลย — prefix ผิด (`03 15` แทน `02 15`) */
    private fun malformedManufacturerData(): ByteArray =
        validManufacturerData(major = 1234, minor = 99).also { it[0] = 0x03 }

    private fun mockScanResult(rssi: Int, manufacturerData: ByteArray, macAddress: String?): ScanResult {
        val scanRecord = Mockito.mock(ScanRecord::class.java)
        Mockito.`when`(scanRecord.getManufacturerSpecificData(BeaconRegionSpec.APPLE_COMPANY_ID))
            .thenReturn(manufacturerData)

        val device = macAddress?.let { address ->
            Mockito.mock(BluetoothDevice::class.java).also {
                Mockito.`when`(it.address).thenReturn(address)
            }
        }

        val result = Mockito.mock(ScanResult::class.java)
        Mockito.`when`(result.scanRecord).thenReturn(scanRecord)
        Mockito.`when`(result.rssi).thenReturn(rssi)
        Mockito.`when`(result.device).thenReturn(device)
        return result
    }

    /**
     * เรียก `receiver.onReceive()` ห่อด้วย `Mockito.mockStatic(Log::class.java)`
     * เสมอ — `android.util.Log` เป็นคลาสจริง (มี body) ของ android.jar ที่ unit
     * test คอมไพล์ด้วย โยน `RuntimeException("... not mocked")` ทุกครั้งที่ถูก
     * เรียกบน JVM ธรรมดา (คนละปัญหากับ `SharedPreferences` ที่เป็น interface ปลอม
     * เองได้ — ดู kdoc ของ `FakeSharedPreferences`) `processProximity()` เรียก
     * `Log.w()` จริงเมื่อ `droppedNoIdentityCount > 0` (ADR-20 หัวข้อ 3) ซึ่งเป็น
     * สาขาหลักที่เทสต์ไฟล์นี้ต้อง exercise — ห่อไว้ทุกจุดเรียกกันพลาดไม่ต้องแยกจำ
     * ว่าเทสต์ไหนต้องห่อบ้าง
     */
    private fun callOnReceive(receiver: BeaconScanReceiver, context: Context, intent: Intent) {
        Mockito.mockStatic(Log::class.java).use {
            receiver.onReceive(context, intent)
        }
    }

    private fun mockIntent(results: List<ScanResult>): Intent {
        val intent = Mockito.mock(Intent::class.java)
        Mockito.`when`(intent.getStringExtra(BackgroundRegionMonitor.EXTRA_REGION_IDENTIFIER))
            .thenReturn(regionIdentifier)
        Mockito.`when`(intent.getIntExtra(eq(BluetoothLeScanner.EXTRA_ERROR_CODE), anyInt()))
            .thenReturn(-1)
        // `Build.VERSION.SDK_INT` เป็น 0 บน JVM unit test ธรรมดา (ไม่มี Robolectric)
        // จึงเข้าสาขา deprecated ของ `getParcelableArrayListExtra` เสมอในเทสต์นี้ —
        // ตรงกับที่ `BeaconScanReceiver.scanResultsFrom()` เขียนไว้จริง
        @Suppress("DEPRECATION")
        Mockito.`when`(
            intent.getParcelableArrayListExtra<ScanResult>(BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT),
        ).thenReturn(ArrayList(results))
        return intent
    }

    /**
     * **เทสต์ที่ ADR-20 รอบแรกขาดไป** — สอง sighting ที่ major ต่างกัน (9902 กับ
     * 9903) ภายใน region เดียวกันที่ลงทะเบียนด้วย UUID อย่างเดียว ต้องได้ **2 key
     * แยกกันจริง** และ median ของแต่ละ key ต้องไม่ปนกัน (ไม่ใช่ทับกันเป็น key เดียว
     * หรือ median ของบีคอนหนึ่งไปปนกับอีกตัว)
     */
    @Test
    fun `sighting 2 ครั้ง major ต่างกัน ใน region ที่ลงทะเบียนด้วย UUID อย่างเดียว ต้องได้ 2 key แยกกันจริง`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        registerWildcardRegion(context)

        val receiver = BeaconScanReceiver()

        // rssi ต่างกันมากพอให้ median (ระยะ) ต่างกันชัดเจน — txPower คงที่ -59
        // (จากไบต์ในเฟรม) ทั้งคู่: d = 10^((txPower-rssi)/(10*pathLossExponent))
        callOnReceive(
            receiver,
            context,
            mockIntent(listOf(mockScanResult(rssi = -66, manufacturerData = validManufacturerData(9902, 2), macAddress = "AA:AA:AA:AA:AA:01"))),
        )
        callOnReceive(
            receiver,
            context,
            mockIntent(listOf(mockScanResult(rssi = -80, manufacturerData = validManufacturerData(9903, 3), macAddress = "AA:AA:AA:AA:AA:02"))),
        )

        val states = ProximityGateStore(context).load()

        val key1 = proximityKeyFor(regionIdentifier, regionUuid.toString(), 9902, 2)
        val key2 = proximityKeyFor(regionIdentifier, regionUuid.toString(), 9903, 3)

        assertEquals(2, states.size, "สอง major ต่างกันต้องได้สอง key แยกกันจริง ไม่ใช่ทับกันเป็นตัวเดียว")
        val state1 = assertNotNull(states[key1], "หา key ของ major=9902 ไม่เจอ")
        val state2 = assertNotNull(states[key2], "หา key ของ major=9903 ไม่เจอ")

        val distance1 = estimateDistanceMeters(rssi = -66, txPower = -59, pathLossExponent = 2.5)
        val distance2 = estimateDistanceMeters(rssi = -80, txPower = -59, pathLossExponent = 2.5)

        assertEquals(
            distance1,
            state1.window.single(),
            absoluteTolerance = 1e-9,
            message = "median ของ key1 ต้องเป็นระยะของ sample ของ key1 เท่านั้น",
        )
        assertEquals(
            distance2,
            state2.window.single(),
            absoluteTolerance = 1e-9,
            message = "median ของ key2 ต้องเป็นระยะของ sample ของ key2 เท่านั้น — ถ้าปนกัน " +
                "ค่านี้จะกลายเป็นของ key1 แทน",
        )
        assertTrue(
            state1.window.single() != state2.window.single(),
            "สอง key ต้องมี window ที่ไม่ปนกันเลย",
        )
    }

    /**
     * sample ที่ถอด major/minor จากเฟรมไม่ได้ (`prefix` ผิด) **ต้องไม่ถูก push เข้า
     * gate เลย** และ **ห้ามมี major/minor จาก region spec (1234/99) โผล่มาแทน** —
     * ทดสอบด้วยการปนอีก sample หนึ่งที่ถอด identity ได้และทำให้เกิด transition จริง
     * (จำเป็นเพราะถ้าทั้ง batch ถอดไม่ได้เลยจะไม่มี event ออกมาสักตัว — ดูเทสต์ถัดไป
     * ที่ยืนยันอาการนั้นแยกต่างหาก) เพื่อให้เห็น `droppedNoIdentityCount` ผ่าน event
     * ที่ปล่อยออกมาจริง
     */
    @Test
    fun `sample ที่ถอด identity ไม่ได้ ไม่ถูก push เข้า gate และห้ามใช้ major minor จาก region spec แทน`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        registerNarrowRegion(context, major = 1234, minor = 99)

        val events = mutableListOf<ProximityChangedEvent>()
        BackgroundProximityMonitor.setProximityObserver { events += it }

        val receiver = BeaconScanReceiver()
        callOnReceive(
            receiver,
            context,
            mockIntent(
                listOf(
                    // ถอดไม่ได้ — ต้องถูกทิ้งทั้งอัน ไม่มี key ให้ผูก
                    mockScanResult(rssi = -70, manufacturerData = malformedManufacturerData(), macAddress = "AA:AA:AA:AA:AA:03"),
                    // ถอดได้ — rssi ไกลพอให้ FAR ยืนยันได้ทันทีตั้งแต่ sample แรก
                    // (baseline ของ key ใหม่คือ FAR — ดู kdoc ของ ProximityGate.applyDwell)
                    mockScanResult(rssi = -90, manufacturerData = validManufacturerData(9902, 2), macAddress = "AA:AA:AA:AA:AA:04"),
                ),
            ),
        )

        assertEquals(1, events.size, "ต้องมี event เดียวจาก sample ที่ถอด identity ได้")
        val event = events.single()
        assertEquals(1, event.droppedNoIdentityCount, "sample ที่ถอดไม่ได้ 1 ตัวต้องถูกนับ")
        assertEquals(9902, event.major, "ต้องเป็น major จากเฟรมจริง")
        assertEquals(2, event.minor, "ต้องเป็น minor จากเฟรมจริง")

        val states = ProximityGateStore(context).load()
        assertEquals(1, states.size, "ต้องมี state แค่ key เดียว (ของ sample ที่ถอดได้) เท่านั้น")

        val fallbackKey = proximityKeyFor(regionIdentifier, regionUuid.toString(), 1234, 99)
        assertNull(
            states[fallbackKey],
            "ห้ามมี key ที่ใช้ major/minor จาก region spec (1234/99) โผล่มาแทนค่าที่ถอดจากเฟรมไม่ได้",
        )
    }

    /**
     * ⚠️ **บันทึกเป็นหนี้ ไม่ใช่ยืนยันว่าดี** — ถ้า sample ทั้ง batch ถอด identity
     * ไม่ได้เลยสักตัว (เช่น อ่าน region list ไม่สำเร็จ → `regionUuid == null` ทุก
     * sample) `processProximity()` จะไม่มี `pending` เลยแม้แต่ตัวเดียว →
     * `if (pending.isEmpty()) return` ตัดจบก่อนถึงลูป emit → **ไม่มี event ออกมา
     * สักตัว** ทั้งที่ `droppedNoIdentityCount` ที่แท้จริงมากกว่า 0 — อาการนี้แยกไม่
     * ออกจาก "ไม่มีบีคอนอยู่ใกล้เลย" จากฝั่งผู้สังเกตการณ์ (`ProximityChangedEvent`
     * เป็นช่องทางเดียวที่ตัวนับนี้ถูกแนบไป) เหลือแต่บรรทัด `Log.w` ใน logcat ที่หาย
     * ไปเมื่อไม่มีใครเปิดดูตอนนั้น
     *
     * การแก้จริงต้องมีช่องทาง event ที่ไม่ผูกกับ transition ซึ่งอยู่นอกขอบเขตของ
     * รอบนี้ (ADR-20 หัวข้อ 5 ห้ามขยาย payload/สัญญาโดยไม่แก้ ADR ก่อน) —
     * **ห้ามแก้โค้ดให้ emit event ปลอมเพื่อให้ตัวนับโผล่** เทสต์นี้ยืนยันพฤติกรรม
     * ปัจจุบันตามที่เป็นจริงเพื่อกันไม่ให้มีใครเข้าใจผิดว่าเคสนี้ถูกครอบคลุมแล้ว
     */
    @Test
    fun `หนี้ - batch ที่ถอด identity ไม่ได้เลยทั้งก้อน ไม่มี event ออกมาสักตัว แม้ droppedNoIdentityCount จริงจะมากกว่า 0`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        registerWildcardRegion(context)

        val events = mutableListOf<ProximityChangedEvent>()
        BackgroundProximityMonitor.setProximityObserver { events += it }

        val receiver = BeaconScanReceiver()
        callOnReceive(
            receiver,
            context,
            mockIntent(
                listOf(
                    mockScanResult(rssi = -70, manufacturerData = malformedManufacturerData(), macAddress = "AA:AA:AA:AA:AA:05"),
                    mockScanResult(rssi = -71, manufacturerData = malformedManufacturerData(), macAddress = "AA:AA:AA:AA:AA:06"),
                ),
            ),
        )

        assertTrue(
            events.isEmpty(),
            "ยืนยันอาการที่เป็นจริงในปัจจุบัน (ไม่ใช่พฤติกรรมที่ต้องการ): ทั้ง batch " +
                "ถอด identity ไม่ได้เลย = ไม่มี event ออกมาสักตัว ตัวนับ droppedNoIdentityCount " +
                "จึงไม่ถูกมองเห็นจากฝั่งผู้สังเกตการณ์เลย — ดูหนี้ที่รายงานใน ADR-20 ขั้น QA",
        )
        assertTrue(
            ProximityGateStore(context).load().isEmpty(),
            "ไม่มี key ใดถูกสร้างเลย เพราะไม่มี sample ไหนถอด identity ได้เลย",
        )
    }
}
