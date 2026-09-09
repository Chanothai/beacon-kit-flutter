package com.bigc.beacon_kit_android

import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * รับผลสแกนที่ระบบส่งมาผ่าน `PendingIntent`
 *
 * **นี่คือจุดที่ process อาจถูกสร้างขึ้นมาใหม่ทั้งตัวเพื่อ callback นี้ตัวเดียว** —
 * `BluetoothLeScanner.java:175-177` ระบุจุดประสงค์ของ API นี้ไว้ว่า "Use this method
 * of scanning if your process is not always running and it should be started when
 * scan results are available."
 *
 * ข้อจำกัดที่ตามมาและเป็นเหตุผลของทุกการตัดสินใจในไฟล์นี้:
 * - **ไม่มี Flutter engine** อย่าเรียกอะไรที่พึ่ง engine
 * - **ไม่มี Activity** อย่าเรียกอะไรที่ต้องการ Activity context
 * - **`onReceive` ต้องจบเร็ว และงานทุกอย่างต้องเสร็จก่อนคืนค่า** ระบบถือว่า process
 *   ทิ้งได้ทันทีที่เมธอดนี้คืน — ห้ามโยนงานไป thread อื่นแล้วหวังว่ามันจะได้รัน
 */
class BeaconScanReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val regionIdentifier =
            intent.getStringExtra(BackgroundRegionMonitor.EXTRA_REGION_IDENTIFIER)
                ?: return

        // ถ้า extras ของผลสแกนไม่มาด้วย แปลว่า PendingIntent ถูกสร้างเป็น
        // FLAG_IMMUTABLE ซึ่งทำให้ระบบ "ส่ง broadcast ได้ แต่ผลสแกนหายไปทั้งก้อน"
        // (PendingIntent.java:917-919) — เป็นความล้มเหลวแบบเงียบที่ ADR-14 บันทึกไว้
        // ตรวจให้เห็นชัดตรงนี้ แทนที่จะปล่อยให้อาการออกมาเป็น "ไม่มี event เลย"
        val errorCode = intent.getIntExtra(BluetoothLeScanner.EXTRA_ERROR_CODE, -1)
        if (errorCode != -1) {
            // ระบบแจ้งว่าสแกนล้มเหลว — ไม่ใช่การพบ beacon จึงไม่นับเป็นการเห็น
            // ยังไม่มีช่องทางรายงาน error ของเส้นทางเบื้องหลังไปถึงผู้ใช้ SDK
            // (บันทึกเป็นหนี้ใน ADR-14) แต่ต้อง **ไม่** ตีความว่าเป็น sighting
            return
        }

        val results = scanResultsFrom(intent)
        if (results.isEmpty()) return

        // ADR-17 หัวข้อ 3: ต้องมาก่อนตรรกะเดิมทั้งหมดของ onSighting — ถ้า
        // reconcile() พบว่า region นี้ (หรือ region อื่นที่กำลังเฝ้าอยู่พร้อมกัน)
        // ค้างสถานะ inside ทั้งที่เงียบไปนานผิดปกติ มันจะพลิก isInside เป็น
        // false ให้ก่อน แล้ว onSighting เดิม (ซึ่งไม่ต้องแก้อะไรเลยแม้แต่บรรทัด
        // เดียว) จะอ่านเจอ wasInside=false เองโดยธรรมชาติ และยิง enter ให้เอง
        // ตามตรรกะที่มีอยู่แล้ว — ผลคือผู้ใช้ SDK ได้ exit(stale) ตามด้วย enter
        // เรียงกัน แทนที่จะถูก onSighting กลืนเงียบเพราะเช็คแค่ wasInside บูลีน
        // ตัวเดียวโดยไม่รู้ว่าความเงียบก่อนหน้านั้นนานแค่ไหน
        BackgroundRegionMonitor.reconcile(context)

        // ใช้เวลาของเครื่องตอนรับ ไม่ใช่ `ScanResult.getTimestampNanos()` ซึ่งเป็น
        // เวลาแบบ elapsed-since-boot ที่แปลงเป็นเวลานาฬิกาได้ไม่ตรงเมื่อ event ถูก
        // คิวไว้นาน — และ log ต้องเทียบกับนาฬิกาข้อมือของผู้ทดสอบได้
        BackgroundRegionMonitor.onSighting(
            context,
            regionIdentifier,
            System.currentTimeMillis(),
        )

        // ---- ชั้นที่ 2 ของ ADR-20: proximity ----
        //
        // **ต้องอยู่หลัง `onSighting` เสมอ ห้ามก่อน และห้ามขยับลำดับ
        // `reconcile()` → `onSighting()` ข้างบนแม้แต่บรรทัดเดียว** (ADR-17)
        //
        // ครอบทั้งก้อนด้วย try/catch แล้ว **กลืน** exception โดยตั้งใจ — ไม่ใช่
        // ความมักง่าย: ชั้น 1 (region enter/exit) มีหลักฐานจากอุปกรณ์จริงระดับ
        // `observed` แล้ว (ADR-14 — `reconcile()` ของ ADR-17 ยัง `code-complete,
        // unverified` ตาม `docs/test-checklists/android_background_scanning.md`)
        // และเป็นเหตุผลเดียวที่ process นี้ถูกปลุกขึ้นมา ส่วนชั้นนี้ยังไม่เคยรันบน
        // เครื่องจริงเลยแม้แต่ครั้งเดียว และเป็น POC ที่อ่าน
        // ค่าที่เก็บไว้บนดิสก์ (ถอด JSON ได้ไม่ครบ) และแตะ `ScanRecord` ดิบ ถ้า
        // ปล่อยให้ exception ลอยขึ้นไป `onReceive` จะตายทั้งเมธอด แต่งานของชั้น 1
        // ที่ทำไปแล้วข้างบนถูก commit ลงดิสก์เรียบร้อยแล้ว — ผลคือ crash ที่ผู้ใช้
        // เห็นโดยไม่ได้อะไรกลับมา และรอบถัดไปก็จะ crash ซ้ำแบบเดิม โยนต่อจึงแย่กว่า
        // กลืนในทุกทาง ตราบใดที่ยัง log ไว้ให้ตามได้ (ADR-20 หัวข้อ 1)
        try {
            processProximity(context, regionIdentifier, results)
        } catch (throwable: Throwable) {
            Log.w(TAG, "ชั้น proximity ล้มเหลว — enter/exit ของชั้น 1 ไม่ได้รับผลกระทบ", throwable)
        }
    }

    /**
     * เดิน `ProximityGate` ให้ครบหนึ่ง batch แล้วบันทึกสถานะลงดิสก์
     *
     * ลำดับสำคัญและห้ามสลับ:
     * 1. กู้สถานะจากดิสก์ — ถ้าข้ามขั้นนี้ dwell จะเริ่มนับหนึ่งใหม่ทุก sighting
     *    เพราะ process ถูกฆ่าคั่นกลาง แล้ว `dwellSamples` จะไม่มีวันครบ (ADR-20 §3)
     * 2. [ProximityGate.sweepStale] **ก่อน** ป้อน sample ใหม่ — ตรวจความเงียบที่
     *    ผ่านมาด้วยเวลาก่อนที่ sample ของรอบนี้จะไปต่ออายุ key ให้ (ADR-20 §4:
     *    ไม่มี timer ในเบื้องหลัง stale จึงถูกค้นพบตอน receiver ตื่นเท่านั้น)
     * 3. ป้อนทุก `ScanResult` ตามลำดับที่ระบบส่งมา
     * 4. **บันทึกลงดิสก์ก่อนแจ้ง observer** — หลักการเดียวกับที่ชั้น 1 เขียน
     *    หลักฐานก่อนยิง notification: ถ้าระบบฆ่า process ระหว่างนั้น อย่างน้อย
     *    สถานะที่นับมาได้ต้องไม่หาย
     */
    private fun processProximity(
        context: Context,
        regionIdentifier: String,
        results: List<ScanResult>,
    ) {
        val store = ProximityGateStore(context)
        val gate = ProximityGate(clock = System::currentTimeMillis)
        gate.restoreStates(store.load())

        // เก็บ rssi/txPower ของ sample ที่จุดชนวน transition ไว้คู่กัน เพื่อให้
        // ไฟล์หลักฐานตอบได้ว่า median ที่ตัดสินใจมาจากสัญญาณแรงแค่ไหน — transition
        // จาก sweepStale ไม่มี sample ประกอบ จึงเป็น null ตามจริง
        val pending = mutableListOf<Triple<ProximityTransition, Int?, Int?>>()

        for (transition in gate.sweepStale()) {
            pending.add(Triple(transition, null, null))
        }

        for (result in results) {
            val txPower = ibeaconTxPowerFrom(
                result.scanRecord?.getManufacturerSpecificData(
                    BeaconRegionSpec.APPLE_COMPANY_ID,
                ),
            )
            val transition = gate.push(
                key = proximityKeyFor(regionIdentifier, result.device?.address),
                rssi = result.rssi,
                txPower = txPower,
            )
            if (transition != null) {
                pending.add(Triple(transition, result.rssi, txPower))
            }
        }

        store.save(gate.snapshotStates())
        // อ่านหลัง save เพื่อให้ครอบทั้งความล้มเหลวของ load และ save ในรอบเดียวกัน
        val storeError = store.lastError

        // ความล้มเหลวของดิสก์ต้องมีร่องรอย — ถ้า store อ่าน/เขียนไม่สำเร็จทุกครั้ง
        // dwell จะเริ่มนับหนึ่งใหม่ทุก sighting แล้ว gate จะเงียบตลอด ซึ่งอาการ
        // เหมือนกับ "ไม่มีบีคอนอยู่ใกล้" เป๊ะ (ดู kdoc ของ `ProximityGateStore`)
        store.lastError?.let { Log.w(TAG, "ProximityGateStore ล้มเหลว: $it") }

        if (pending.isEmpty()) return

        // อ่าน region spec ครั้งเดียวต่อ batch (เป็นการอ่านดิสก์) — และเฉพาะตอนมี
        // transition จริงเท่านั้น เพราะ batch ส่วนใหญ่ไม่ทำให้ bucket เปลี่ยนเลย
        val region = runCatching {
            BackgroundRegionMonitor.restoredRegions(context)
                .regions
                .firstOrNull { it.identifier == regionIdentifier }
        }.getOrNull()

        for ((transition, rssi, txPower) in pending) {
            BackgroundProximityMonitor.emit(
                ProximityChangedEvent(
                    regionIdentifier = regionIdentifier,
                    // มาจาก region spec ที่ลงทะเบียนไว้ ไม่ใช่จากเฟรม (ฝั่ง Kotlin
                    // ไม่มี parser) — region แบบกว้างที่ไม่ระบุ major/minor จึงได้
                    // `null` ตามจริง ห้ามเดาค่าแทน
                    uuid = region?.uuid?.toString(),
                    major = region?.major,
                    minor = region?.minor,
                    from = transition.from,
                    to = transition.to,
                    reason = transition.reason,
                    medianMeters = transition.medianMeters,
                    timestampMillis = System.currentTimeMillis(),
                    rssi = rssi,
                    txPower = txPower,
                    beaconTag = beaconTagOf(transition.key),
                    storeError = storeError,
                ),
            )
        }
    }

    /**
     * ดึงรายการ `ScanResult` ออกจาก Intent
     *
     * `getParcelableArrayListExtra(String)` ถูก deprecate ตั้งแต่ API 33 และแทนที่
     * ด้วยเวอร์ชันที่รับ `Class` — แยกสองทางตาม API level แทนการกด `@Suppress`
     * ทิ้งไว้ทั้งเมธอด เพราะเครื่องที่ target สูงขึ้นในอนาคตต้องเดินทางที่ถูก
     */
    private fun scanResultsFrom(intent: Intent): List<ScanResult> {
        val key = BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(key, ScanResult::class.java) ?: emptyList()
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<ScanResult>(key) ?: emptyList()
        }
    }
}

/** tag ของ logcat สำหรับเส้นทางเบื้องหลัง — สั้นกว่า 23 ตัวอักษรตามข้อจำกัดของ `Log` */
private const val TAG = "BeaconScanReceiver"

/**
 * key ของ `ProximityGate` สำหรับหนึ่งบีคอนที่เห็นใน region หนึ่ง
 *
 * ## ทำไมต้องมี MAC อยู่ในนี้ ทั้งที่ฝั่ง Dart ใช้ (uuid, major, minor)
 *
 * ฝั่ง Kotlin **ไม่มี parser** (ADR-14 หัวข้อ 4.1) จึงไม่รู้ uuid/major/minor ราย
 * เฟรมเลย — สิ่งที่รู้แน่ตอน `onReceive` มีสองอย่างคือ `regionIdentifier` (ติดมากับ
 * `PendingIntent`) และที่อยู่ของวิทยุที่ส่งเฟรมนั้น
 *
 * ถ้าใช้ `regionIdentifier` เดี่ยว ๆ เป็น key แล้วเจอ region แบบกว้างของ ADR-8 (ไม่
 * ระบุ major/minor) **RSSI ของบีคอนคนละตัวจะถูกยัดรวมในหน้าต่างเดียวกัน** median ที่
 * ได้จะไม่ใช่ระยะของบีคอนตัวใดเลย — บั๊กที่มองไม่เห็นจาก log เพราะตัวเลขยังดูสมเหตุผล
 *
 * ⚠️ **MAC ไม่ใช่ identity ที่ยั่งยืน** — บีคอนที่เปลี่ยนที่อยู่แบบสุ่ม (privacy
 * feature) จะกลายเป็น key ใหม่และเริ่มนับ dwell ใหม่ทั้งหมด และเปลี่ยนแบตแล้วตั้งค่า
 * ใหม่ก็อาจได้ที่อยู่ใหม่ ยอมรับได้เฉพาะขอบเขต POC ของ ADR-20 นี้เท่านั้น **ฝั่ง iOS
 * ห้ามลอกวิธีนี้ไปใช้** ที่นั่นต้องใช้ (uuid, major, minor) ตาม ADR-19
 *
 * [deviceAddress] เป็น `null` ได้ในทางทฤษฎี (ค่าที่ระบบส่งมาไม่ครบ) — ใช้
 * `"unknown-device"` แทนการทิ้ง sample เพราะการรวมทุกตัวที่ไม่รู้ที่อยู่ไว้ด้วยกัน
 * ยังดีกว่าการเงียบสนิทโดยไม่มีร่องรอย และเคสนี้ต้องแยกจาก key ปกติได้ด้วยตาเปล่า
 */
internal fun proximityKeyFor(regionIdentifier: String, deviceAddress: String?): String =
    "$regionIdentifier|${deviceAddress ?: "unknown-device"}"

/**
 * ตัวแยกบีคอนสำหรับไฟล์หลักฐาน — **สองไบต์ท้ายของ MAC เท่านั้น**
 *
 * ดูเหตุผลเต็มที่ [ProximityChangedEvent.beaconTag] · คืน `null` เมื่อ key ไม่มี
 * ส่วนที่อยู่ (ไม่ควรเกิด แต่ห้ามเดา) และคืนค่าเดิมทั้งก้อนเมื่อเป็น
 * `"unknown-device"` เพราะเคสนั้นต้องแยกออกจาก MAC จริงได้ด้วยตาเปล่า
 */
internal fun beaconTagOf(key: String): String? {
    val address = key.substringAfter('|', missingDelimiterValue = "")
    if (address.isEmpty()) return null
    if (!address.contains(':')) return address
    return address.split(':').takeLast(2).joinToString(":")
}

/**
 * อ่าน `txPower` จาก manufacturer-specific data ของ iBeacon — **pure function**
 *
 * แยกออกมาเป็นฟังก์ชันระดับไฟล์ที่รับ `ByteArray?` (ไม่ใช่ `ScanResult`) ด้วยเหตุผล
 * เดียวกับที่ `BeaconRegionSpec.scanFilterDataAndMask()` ถูกแยกออกจาก `toScanFilter()`:
 * `ScanResult`/`ScanRecord` เป็นคลาสของ framework ที่สร้างใน JVM unit test ไม่ได้เลย
 * ถ้าปล่อยตรรกะการอ่านไบต์ไว้ข้างในเมธอดที่รับ `ScanResult` มันจะกลายเป็นตรรกะที่
 * เสี่ยงที่สุดในไฟล์นี้และทดสอบไม่ได้เลย — และอาการเวลาผิดคือ "ระยะเพี้ยนเป็นเท่าตัว"
 * ซึ่งดูเหมือนสัญญาณอ่อนธรรมดา ไม่มีอะไรฟ้องว่าเป็นบั๊ก
 *
 * layout (หลัง company id ถูกตัดออกโดย `getManufacturerSpecificData` แล้ว —
 * `ScanFilter.java:618-638` และหัวข้อ "รูปแบบของ byte ที่กรอง" ใน `BeaconRegionSpec`):
 * ```
 * 02 15 | uuid (16) | major (2) | minor (2) | txPower (1)
 * ```
 *
 * **ทั้ง prefix และ offset อ้างของเดิมตัวเดียว ไม่เขียนเลขซ้ำ** (ADR-20 หัวข้อ 1):
 * prefix มาจาก [BeaconRegionSpec.IBEACON_PREFIX] และ offset คำนวณจากความยาวของ
 * prefix นั้นบวกความยาวของฟิลด์ที่คั่นอยู่ ไม่ใช่ค่าคงที่ `22` ที่เขียนทิ้งไว้
 *
 * คืน `null` (ไม่ใช่ค่า default เงียบ ๆ) เมื่อ array เป็น `null` / สั้นเกินไป /
 * prefix ไม่ใช่ `02 15` — `ProximityGate` จะทิ้ง sample นั้นและนับ
 * `droppedNoTxPowerCount` ให้เอง ตาม ADR-19 หัวข้อ 6(จ) ที่ห้าม default ค่า txPower
 *
 * ค่าที่คืนเป็น **signed** (`Byte.toInt()`) เพราะ txPower ของ iBeacon คือ RSSI ที่วัด
 * ได้ที่ระยะ 1 เมตร ซึ่งเป็นค่าติดลบเสมอในทางปฏิบัติ — อ่านเป็น unsigned จะได้ ~200
 * แล้วสูตรระยะจะพุ่งเป็นหลักพันเมตรโดยไม่มีอะไรฟ้อง
 */
internal fun ibeaconTxPowerFrom(manufacturerData: ByteArray?): Int? {
    val data = manufacturerData ?: return null
    val prefix = BeaconRegionSpec.IBEACON_PREFIX

    // uuid 16 + major 2 + minor 2 ไบต์ คั่นระหว่าง prefix กับ txPower
    val txPowerIndex = prefix.size + 16 + 2 + 2
    if (data.size < txPowerIndex + 1) return null

    for (index in prefix.indices) {
        if (data[index] != prefix[index]) return null
    }

    return data[txPowerIndex].toInt()
}
