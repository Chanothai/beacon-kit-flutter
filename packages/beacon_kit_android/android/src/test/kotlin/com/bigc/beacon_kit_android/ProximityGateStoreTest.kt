package com.bigc.beacon_kit_android

import android.content.Context
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito

/**
 * เทสต์ `ProximityGateStore` — **เทสต์ที่สำคัญที่สุดของ ADR-20 ขั้นนี้**
 *
 * ## สิ่งที่เทสต์ round-trip พิสูจน์ (ADR-20 หัวข้อ 3)
 *
 * `BeaconScanReceiver` มีชีวิตแค่ช่วง `onReceive()` และ OEM แบบ MIUI ฆ่า process
 * ทิ้งได้ทันทีที่เมธอดนั้นคืนค่า ถ้า `ProximityGate` เก็บหน้าต่าง/ตัวนับ dwell ไว้ใน
 * memory อย่างเดียว ทุกอย่างจะรีเซ็ตทุก sighting แล้ว `dwellSamples = 3` **จะไม่มีวัน
 * ครบ** — gate เงียบตลอดทั้งที่ผู้ใช้ยืนอยู่หน้าชั้นวาง
 *
 * เทสต์ `dwell ข้าม process` ด้านล่างจำลองการตายของ process ด้วยการ **สร้างทั้ง
 * `ProximityGate` และ `ProximityGateStore` ขึ้นใหม่ทั้งคู่** โดยเหลือแค่ไฟล์ prefs
 * (ที่นี่คือ [FakeSharedPreferences] ตัวเดิม = "ดิสก์") เป็นสิ่งเดียวที่รอดข้ามมา
 * — ถ้า sample ที่ 3 ไม่ทำให้เกิด transition แปลว่า dwell รีเซ็ตข้าม process จริง
 * ซึ่งคืออาการที่ ADR-20 ทั้งฉบับมีไว้ป้องกัน
 *
 * ## ทำไมต้อง mock `Context`
 *
 * `ProximityGateStore` ต้องมี `Context` เพื่อเปิด `SharedPreferences` —
 * [FakeSharedPreferences] implement interface ตรง ๆ (ไม่ต้องใช้ Robolectric ดู
 * เหตุผลในไฟล์นั้น) ส่วน `Context` เอง mock ด้วย Mockito เฉพาะสองเมธอดที่ store
 * เรียกจริง (`applicationContext` / `getSharedPreferences`) เหมือนที่
 * `BackgroundRegionMonitorOnExitAlarmTest` ทำอยู่แล้ว — ไม่มี dependency ใหม่
 *
 * `org.json.JSONObject`/`JSONArray` ที่ `statesToJson`/`statesFromJson` เรียก ใช้
 * `org.json:json` ตัวจริงใน test classpath ที่มีอยู่ก่อนรอบนี้แล้ว จึงได้ตรวจ JSON
 * ที่เขียนจริง ไม่ใช่ผ่านเพราะไม่ throw
 *
 * ⚠️ JVM unit test ล้วน — **ไม่ได้พิสูจน์ว่าเส้นทางเบื้องหลังบนเครื่องจริงทำงาน**
 * (ยังไม่มีใครเห็น `BeaconScanReceiver` ถูกปลุกจริงพร้อมสถานะที่กู้มาได้เลยสักครั้ง)
 */
class ProximityGateStoreTest {

    private class FakeClock(var nowMillis: Long = 1_757_000_000_000L) {
        fun read(): Long = nowMillis
    }

    /**
     * รูปร่างใหม่ `region|uuid|major|minor` (ADR-20 หัวข้อ 3 แก้ 11 ก.ย. 2026) —
     * **แก้จากรูปร่างเดิม `region|MAC` ที่ไม่ผ่าน `isValidKeyShape` อีกต่อไป**
     * (เดิมคือ `"bigc-test|AA:BB:CC:DD:EE:FF"`) ทุกเทสต์ที่ใช้ตัวแปรนี้ยังทดสอบ
     * เจตนาเดิมทุกอย่างครบ (round-trip ข้าม process / clear ล้างจริง) เปลี่ยนแค่
     * รูปร่างของ key ให้ตรงกับกฎ shape-validation ใหม่ที่ ADR-20 บังคับ
     */
    private val key = "bigc-test|e2c56db5-dffb-48d2-b060-d0f5a71096e0|9902|2"
    private val txPower = -40

    /** ~2.51 m ที่ `pathLossExponent = 2.0` — อยู่ใน `enterMeters` (3.0) → NEAR */
    private val nearRssi = -48

    /** ~19.95 m — ใช้ priming ให้ยืนยัน FAR ก่อน (ค่าเดียวกับเทสต์ Dart กลุ่ม C/D) */
    private val farRssi = -66

    private fun mockContext(prefs: FakeSharedPreferences): Context {
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.applicationContext).thenReturn(context)
        Mockito.`when`(context.getSharedPreferences(anyString(), anyInt())).thenReturn(prefs)
        return context
    }

    private fun newGate(clock: FakeClock) = ProximityGate(
        clock = clock::read,
        windowSize = 1,
        // dwellSamples ใช้ค่า default (3) — ต้อง > 1 ถึงจะมี dwell ให้ขาดตอนได้
        pathLossExponent = 2.0,
    )

    /**
     * process ตายกลาง dwell แล้ว dwell ต้อง **ไม่** เริ่มนับหนึ่งใหม่
     *
     * ลำดับ: gate ตัวที่ 1 ยืนยัน FAR → เข้าใกล้ 2 sample (ยังไม่ครบ 3) → มี sample
     * ที่ถูกทิ้งเพราะไม่มี txPower 1 ตัว (ใส่ไว้เพื่อให้ `droppedNoTxPowerCount`
     * เป็นค่าที่**ไม่ใช่ค่า default** ไม่งั้นการ assert ว่ามัน round-trip กลับมาได้
     * จะแยกไม่ออกจาก "ได้ค่า default ของ object ใหม่") → `save()` → สร้าง gate/store
     * ใหม่ทั้งคู่ → `restoreStates(load())` → sample ที่ 3 ต้องยืนยัน NEAR ทันที
     */
    @Test
    fun `round-trip - dwell ที่ค้างอยู่ต้องรอดข้าม process แล้ว sample ที่ 3 ยืนยัน NEAR`() {
        val prefs = FakeSharedPreferences() // = "ดิสก์" สิ่งเดียวที่รอดข้าม process
        val clock = FakeClock()
        val savedAt = clock.nowMillis

        // ---- process ที่ 1 ----
        val gate1 = newGate(clock)
        val store1 = ProximityGateStore(mockContext(prefs))

        gate1.push(key = key, rssi = farRssi, txPower = txPower) // ยืนยัน FAR
        assertEquals(ProximityBucket.FAR, gate1.currentBucket(key))
        assertNull(gate1.push(key = key, rssi = nearRssi, txPower = txPower))
        assertNull(gate1.push(key = key, rssi = nearRssi, txPower = txPower))
        assertNull(gate1.push(key = key, rssi = nearRssi, txPower = null)) // ถูกทิ้ง
        assertEquals(2, gate1.stateOf(key)?.pendingCloserCount, "ยังไม่ครบ dwell (3)")

        store1.save(gate1.snapshotStates())

        // ---- process ที่ 2: ของใหม่ทุกตัว เหลือแค่ prefs ที่รอดมา ----
        val store2 = ProximityGateStore(mockContext(prefs))
        val gate2 = newGate(clock)
        val restored = store2.load()

        val state = assertNotNull(
            restored[key],
            "อ่านสถานะกลับมาไม่ได้เลย — dwell จะเริ่มนับหนึ่งใหม่ทุก sighting",
        )
        assertEquals(ProximityBucket.FAR, state.confirmedBucket)
        assertEquals(ProximityBucket.NEAR, state.pendingCloserBucket)
        assertEquals(2, state.pendingCloserCount)
        assertEquals(1, state.droppedNoTxPowerCount)
        assertEquals(1, state.window.size, "windowSize = 1 → เก็บตัวล่าสุดตัวเดียว")
        assertEquals(
            estimateDistanceMeters(
                rssi = nearRssi,
                txPower = txPower,
                pathLossExponent = 2.0,
            ),
            state.window.single(),
            absoluteTolerance = 1e-9,
            message = "ระยะในหน้าต่างต้อง round-trip กลับมาได้ ไม่ใช่ถูกปัดทิ้ง",
        )
        assertEquals(savedAt, state.lastSampleAt)

        gate2.restoreStates(restored)

        val t = gate2.push(key = key, rssi = nearRssi, txPower = txPower)

        val transition = assertNotNull(
            t,
            "sample ที่ 3 หลังกู้สถานะต้องทำให้ dwell ครบ 3 พอดี — ถ้าเป็น null แปลว่า " +
                "ตัวนับเริ่มใหม่ข้าม process ซึ่งคือปัญหาที่ ADR-20 หัวข้อ 3 มีไว้แก้",
        )
        assertEquals(ProximityTransitionReason.CLOSER, transition.reason)
        assertEquals(ProximityBucket.FAR, transition.from)
        assertEquals(ProximityBucket.NEAR, transition.to)
        assertEquals(ProximityBucket.NEAR, gate2.currentBucket(key))
    }

    /**
     * เพิ่มจากโจทย์: ค่าที่เสียหายบนดิสก์ต้องกลายเป็น "เริ่มนับใหม่" ไม่ใช่ exception
     * ที่ลอยขึ้นไปทำให้ชั้น 1 (region enter/exit ระดับ `observed` ตาม ADR-14) พัง
     * ไปด้วย — เป็น
     * สัญญาที่ kdoc ของ `ProximityGateStore` ประกาศไว้ตรง ๆ (ADR-20 หัวข้อ 1)
     */
    @Test
    fun `ค่าที่เสียหายบนดิสก์ต้องกลายเป็น map ว่าง ไม่ใช่ exception`() {
        val prefs = FakeSharedPreferences()
        prefs.edit().putString("states", "{ นี่ไม่ใช่ JSON เลย ").commit()

        val restored = ProximityGateStore(mockContext(prefs)).load()

        assertTrue(restored.isEmpty(), "JSON เสียหายต้องกลายเป็น 'เริ่มนับใหม่'")
    }

    /**
     * bucket ถูกเขียนด้วย `wireName` ไม่ใช่ `ordinal` — ถ้าค่าที่อ่านกลับมาไม่ตรงกับ
     * ชื่อใดเลย (ข้อมูลเก่าคนละเวอร์ชัน/เสียหาย) ต้องได้ `null` แปลว่า "ยังไม่เคย
     * ยืนยันอะไร" ไม่ใช่เดา bucket มั่ว ๆ ให้ตัวหนึ่ง
     */
    @Test
    fun `wireName ที่ไม่รู้จักต้องกลายเป็น null ไม่ใช่เดา bucket`() {
        val restored = ProximityGateStore.statesFromJson(
            """{"$key":{"confirmedBucket":"veryClose","pendingCloserCount":7}}""",
        )

        val state = assertNotNull(restored[key])
        assertNull(state.confirmedBucket)
        assertEquals(7, state.pendingCloserCount, "ฟิลด์อื่นที่ยังอ่านได้ต้องไม่หายไปด้วย")
    }

    /**
     * **หนึ่ง key = หนึ่ง entry เสมอ ไม่ว่าจะบันทึกซ้ำกี่รอบ** (สอบสวนข้อ A)
     *
     * ที่มา: ไฟล์หลักฐาน 9 ก.ย. 2026 มี `reason=stale` สามบรรทัดติดกันภายใน 34 ms
     * ที่ `regionIdentifier` เดียวกัน (16:45:20.702/.720/.736) ซึ่งอ่านเหมือน store
     * เก็บ entry ซ้ำต่อ key แล้ว `sweepStale()` ยิงซ้ำตามจำนวนนั้น
     *
     * เทสต์นี้ปิดข้อสงสัยนั้นจากสองด้าน:
     * 1. `save()` ซ้ำหลายรอบด้วย key เดิม → `load()` ต้องได้ **1 entry** เท่านั้น
     *    (โครงสร้างบนดิสก์เป็น `JSONObject` ที่ key ซ้ำกันไม่ได้อยู่แล้วโดยนิยาม
     *    — เทสต์นี้ล็อกไว้ไม่ให้ใครเปลี่ยนไปใช้ `JSONArray` แล้วเปิดช่องนั้นขึ้นมา)
     * 2. `sweepStale()` ที่มีหลาย key ค้างอยู่ ต้องคืน **transition ละ 1 ตัวต่อ key
     *    และ key ห้ามซ้ำกัน** — สามบรรทัดในไฟล์จริงจึงต้องเป็นบีคอนสามตัว
     *    (คนละ minor ใน key เดียวกันไม่ได้) ไม่ใช่ key เดียวยิงสามครั้ง
     *
     * **อัปเดต ADR-20 หัวข้อ 3 (11 ก.ย. 2026):** เดิมสาม key ต่างกันเฉพาะส่วน MAC
     * (`"k9p-default|AA:AA:AA:AA:AA:0N"`) เพราะตอนนั้น key คือ `region|MAC` — รูป
     * ร่างใหม่ไม่มี MAC ใน key แล้ว จึงเปลี่ยนมาต่างกันที่ minor แทน (major/uuid/region
     * เดิมหมด) เจตนาของเทสต์ไม่เปลี่ยน: ยังคือ "region กว้างเห็นบีคอนหลายตัว
     * (ADR-8) ต้องได้ entry แยกกันจริง ไม่ใช่ปนกันเป็นตัวเดียว"
     */
    @Test
    fun `หนึ่ง key มีได้ entry เดียว และ sweepStale ยิงได้ key ละครั้งเท่านั้น`() {
        val clock = FakeClock()
        val prefs = FakeSharedPreferences()
        val store = ProximityGateStore(mockContext(prefs))
        val gate = newGate(clock)

        // สาม key ต่างกันเฉพาะส่วน minor — region/uuid/major เดียวกันทั้งหมด
        // (เคสเดียวกับ region กว้างของ ADR-8 ที่เห็นบีคอนหลายตัว)
        val keys = listOf(
            "k9p-default|e2c56db5-dffb-48d2-b060-d0f5a71096e0|9902|1",
            "k9p-default|e2c56db5-dffb-48d2-b060-d0f5a71096e0|9902|2",
            "k9p-default|e2c56db5-dffb-48d2-b060-d0f5a71096e0|9902|3",
        )
        for (k in keys) {
            repeat(3) { gate.push(key = k, rssi = nearRssi, txPower = txPower) }
            assertEquals(ProximityBucket.NEAR, gate.currentBucket(k), "ต้อง confirm ก่อนถึงจะมี stale ให้ยิง")
        }

        // บันทึกซ้ำหลายรอบด้วย key ชุดเดิม — entry ต้องไม่งอกตาม
        repeat(3) { store.save(gate.snapshotStates()) }

        val restored = store.load()
        assertEquals(3, restored.size, "สาม key ต้องได้สาม entry ไม่ใช่เก้า")
        assertEquals(keys.toSet(), restored.keys, "key ต้องตรงกันเป๊ะ ไม่มีตัวซ้ำ ไม่มีตัวหาย")

        clock.nowMillis += 61_000L // เกิน staleAfterMillis (60 วินาที)

        val transitions = gate.sweepStale()

        assertEquals(3, transitions.size, "สาม key ที่ confirm ไว้ → สาม transition")
        assertEquals(
            keys.toSet(),
            transitions.map { it.key }.toSet(),
            "key ของ transition ต้องไม่ซ้ำกันเลย — ถ้าซ้ำแปลว่ายิงซ้ำจริง",
        )
        assertTrue(
            transitions.all { it.reason == ProximityTransitionReason.STALE && it.to == null },
            "ทุกตัวต้องเป็น STALE ที่ to เป็น null",
        )
        assertEquals(0, gate.sweepStale().size, "เรียกซ้ำทันทีต้องไม่ยิงอะไรอีก")
    }

    /**
     * `clear()` ต้องล้างจริง — ล็อกสัญญาที่ `monitorStop` ของ example app พึ่งอยู่
     *
     * ก่อนคอมมิตนี้ `clear()` **ไม่มีผู้เรียกแม้แต่รายเดียว**: `stop()` ของ
     * `BackgroundRegionMonitor` ล้างเฉพาะสถานะชั้น 1 (`BackgroundRegionStore`)
     * ทำให้ key ของบีคอนที่ไม่อยู่แล้วค้างข้ามรอบทดสอบ แล้วโผล่เป็น `stale` รัว ๆ
     * ตอน sighting แรกของรอบถัดไป — ซึ่งคืออาการที่ถูกสอบสวนในข้อ A พอดี
     */
    @Test
    fun `clear ต้องล้างสถานะทุก key ออกจากดิสก์จริง`() {
        val clock = FakeClock()
        val prefs = FakeSharedPreferences()
        val store = ProximityGateStore(mockContext(prefs))
        val gate = newGate(clock)

        gate.push(key = key, rssi = farRssi, txPower = txPower)
        store.save(gate.snapshotStates())
        assertEquals(1, store.load().size, "ต้องมีของให้ล้างก่อน ไม่งั้นเทสต์ผ่านฟรี")

        store.clear()

        assertTrue(store.load().isEmpty(), "หลัง clear() ต้องไม่เหลือ key ใดเลย")
        assertNull(store.lastError, "การล้างที่สำเร็จต้องไม่ทิ้ง error ค้างไว้")
    }

    /**
     * [beaconTagOf] — ตัวแยกบีคอนในไฟล์หลักฐาน (สอบสวนข้อ A/B)
     *
     * ถ้าไม่มีค่านี้ บรรทัด `stale` ของบีคอนคนละตัวใน region เดียวกันจะอ่านเหมือน
     * บรรทัดซ้ำ และ `from=none` ของ key ที่เพิ่งเจอครั้งแรกจะอ่านเหมือน state หาย
     *
     * **อัปเดต ADR-20 หัวข้อ 3 (11 ก.ย. 2026) — [beaconTagOf] เปลี่ยน signature**
     * เดิมฟังก์ชันนี้รับ gate key เต็ม (`"<region>|<MAC>"`) แล้วถอด MAC ออกจากมัน
     * เอง เพราะตอนนั้น MAC เป็นส่วนหนึ่งของ key จริง — ตอนนี้ key ไม่มี MAC แล้ว
     * (`"<region>|<uuid>|<major>|<minor>"`) ฟังก์ชันจึงรับ
     * `ScanResult.device?.address` **ตรง ๆ** แทน (ดู kdoc ของฟังก์ชันจริงใน
     * `BeaconScanReceiver.kt`) เทสต์เดิมที่ป้อน compound key เข้าไปตรง ๆ ใช้ไม่ได้
     * อีกต่อไปเพราะทดสอบผิดสัญญา (ยกตัวอย่างที่พังเงียบ: ป้อน
     * `"bigc-test|unknown-device"` เข้าไป ฟังก์ชันเห็นว่าไม่มี `:` เลยทั้งสตริง
     * จึงคืนค่าดิบทั้งก้อนรวม prefix `"bigc-test|"` ด้วย ไม่ใช่ `"unknown-device"`
     * ตามที่เทสต์เดิมคาดหวัง) เจตนาเดิม (แยกบีคอนคนละตัว + แยก unknown ออกจาก MAC
     * จริงได้) ยังทดสอบครบ เปลี่ยนแค่ค่าที่ป้อนให้ตรงสัญญาจริง
     */
    @Test
    fun `beaconTagOf คืนสองไบต์ท้ายของ MAC และแยก unknown-device ออกได้`() {
        assertEquals("EE:FF", beaconTagOf("AA:BB:CC:DD:EE:FF"))
        assertEquals("AA:01", beaconTagOf("AA:AA:AA:AA:AA:01"))
        assertEquals(
            "unknown-device",
            beaconTagOf("unknown-device"),
            "ที่อยู่ที่ไม่มี ':' เลย (รูปแบบที่ไม่คาดคิดจากระบบ) ต้องคืนค่าดิบทั้งก้อน " +
                "แทนการตัดผิดตัว — ยังอ่านแยกจาก MAC จริงได้ด้วยตาเปล่าเพราะไม่มีรูปแบบ MAC",
        )
        assertNull(
            beaconTagOf(null),
            "deviceAddress เป็น null เกิดจริงทุกครั้งกับ transition จาก sweepStale " +
                "ที่ไม่มี ScanResult คู่มาด้วย (เป็นการตรวจความเงียบ ไม่ใช่ sample ใหม่) " +
                "ต้องตอบ null ห้ามเดาค่าแทน",
        )
    }

    // ==== Migration ของ state บนดิสก์ (ADR-20 หัวข้อ 3) ====

    /**
     * เครื่องที่รันบิลด์เก่าค้างอยู่จะมี entry รูปแบบเดิม 2 ส่วน (`region|MAC`) อยู่ใต้
     * คีย์เก่า `"states"` — `load()` ต้องลบคีย์นั้นทิ้งจริง (ไม่ใช่แค่ไม่อ่าน) และนับ
     * จำนวนที่ทิ้งไปให้ถูกต้อง **ห้ามพยายามแปลงค่าเดา** เนื้อหาของแต่ละ entry ปล่อย
     * ว่างเปล่าได้เพราะ `countTopLevelKeys` นับแค่จำนวน top-level key ไม่สนใจเนื้อใน
     */
    @Test
    fun `migration - คีย์เก่า states รูปแบบเดิม 2 entry ถูกลบออกจากดิสก์จริงและนับ 2`() {
        val prefs = FakeSharedPreferences()
        prefs.edit().putString(
            "states",
            """{"bigc-test|AA:BB:CC:DD:EE:FF":{},"bigc-test|AA:BB:CC:DD:EE:00":{}}""",
        ).commit()

        val store = ProximityGateStore(mockContext(prefs))
        val restored = store.load()

        assertTrue(restored.isEmpty(), "รูปแบบเก่าต้องไม่ถูกแปลงมาเป็น state ใหม่ — เริ่มนับหนึ่งใหม่")
        assertEquals(
            2,
            store.lastMigrationDroppedCount,
            "คีย์เก่ามี 2 entry ต้องนับให้ครบ ไม่ใช่เดา 0 หรือ 1",
        )
        assertFalse(
            prefs.contains("states"),
            "คีย์เก่าต้องถูกลบออกจาก SharedPreferences จริง ไม่ใช่แค่ไม่ถูกอ่านตอน load()",
        )
        assertNull(store.lastError, "migration สำเร็จ ≠ ดิสก์พัง ต้องไม่ทิ้ง error ปลอมไว้")
    }

    /**
     * หลัง migration ลบคีย์เก่าทิ้งแล้ว ต้อง**ไม่มี state อะไรเหลือให้ `sweepStale`
     * ค้นเจอเลย** จาก key รูปแบบเก่านั้น — ถ้ามี transition โผล่มาแปลว่าค่าที่ควรถูก
     * drop รอดเข้ามาเป็น state จริงในหน่วยความจำ ซึ่งจะออกมาเป็น `stale` ปลอมที่ไม่มี
     * ใครเคย push ให้เกิดขึ้นจริง
     */
    @Test
    fun `migration - หลังลบคีย์เก่าแล้ว sweepStale ต้องไม่มี stale ปลอมจากคีย์นั้น`() {
        val clock = FakeClock()
        val prefs = FakeSharedPreferences()
        prefs.edit().putString(
            "states",
            """{"bigc-test|AA:BB:CC:DD:EE:FF":{"confirmedBucket":"near"}}""",
        ).commit()

        val store = ProximityGateStore(mockContext(prefs))
        val gate = newGate(clock)
        gate.restoreStates(store.load())

        clock.nowMillis += 61_000L // เกิน staleAfterMillis (60 วินาที) หลายเท่า

        assertTrue(
            gate.sweepStale().isEmpty(),
            "key รูปแบบเก่าที่ถูก drop ไปแล้วต้องไม่เหลือ state ให้ sweepStale เจอ",
        )
    }

    /**
     * entry รูปแบบเก่า (2 ส่วน) ที่ปนอยู่ใต้คีย์**ใหม่** `states_v2` เอง (ในทางทฤษฎี
     * เกิดจากบั๊กอื่นเขียนทับ) ก็ต้องถูก filter ทิ้งเหมือนกัน ไม่ใช่แค่ตอนเจอใต้คีย์
     * เก่าเท่านั้น — ใช้ [isValidKeyShape] ตัวเดียวกับที่กรองตอนอ่านคีย์เก่า
     */
    @Test
    fun `migration - entry รูปแบบเก่าที่ปนอยู่ใต้คีย์ใหม่ states_v2 ก็ถูก drop เหมือนกัน`() {
        val prefs = FakeSharedPreferences()
        prefs.edit().putString(
            "states_v2",
            """{"bigc-test|AA:BB:CC:DD:EE:FF":{},"$key":{"confirmedBucket":"near"}}""",
        ).commit()

        val store = ProximityGateStore(mockContext(prefs))
        val restored = store.load()

        assertEquals(setOf(key), restored.keys, "เหลือแค่ key รูปแบบใหม่ 4 ส่วนเท่านั้น")
        assertEquals(
            1,
            store.lastMigrationDroppedCount,
            "key รูปแบบเก่าที่ปนอยู่ใต้คีย์ใหม่ต้องถูกนับว่า drop ด้วยเช่นกัน",
        )
    }

    /**
     * `lastMigrationDroppedCount == null` ต้องแปลว่า **ไม่มี migration เกิดขึ้นเลย
     * ในรอบนี้** — ต่างจาก `0` ที่แปลว่า "เจอเงื่อนไข migration แต่ไม่มีอะไรให้ทิ้ง"
     * ความต่างนี้คือสิ่งที่ทำให้บรรทัดหลักฐานอ่านถูก (ดู kdoc ของฟิลด์จริง)
     */
    @Test
    fun `migration - lastMigrationDroppedCount เป็น null เมื่อไม่มี migration เกิดขึ้นเลย`() {
        val prefs = FakeSharedPreferences()
        // ไม่มีคีย์เก่า "states" และไม่มี entry รูปแบบเก่าปนอยู่ใต้คีย์ใหม่เลย
        prefs.edit().putString("states_v2", """{"$key":{"confirmedBucket":"near"}}""").commit()

        val store = ProximityGateStore(mockContext(prefs))
        store.load()

        assertNull(
            store.lastMigrationDroppedCount,
            "ไม่มี migration เกิดขึ้นเลยในรอบนี้ต้องเป็น null ไม่ใช่ 0",
        )
    }

    /** ตรงข้ามกับเทสต์ข้างบน: เจอเงื่อนไข migration จริง (คีย์เก่ามีอยู่) แต่เนื้อหาว่างเปล่า */
    @Test
    fun `migration - lastMigrationDroppedCount เป็น 0 เมื่อเจอคีย์เก่าแต่เนื้อหาว่างเปล่า`() {
        val prefs = FakeSharedPreferences()
        prefs.edit().putString("states", "{}").commit()

        val store = ProximityGateStore(mockContext(prefs))
        store.load()

        assertEquals(
            0,
            store.lastMigrationDroppedCount,
            "เจอคีย์เก่าแต่ไม่มีอะไรให้ทิ้งจริง ต้องเป็น 0 ไม่ใช่ null " +
                "— null แปลว่าไม่มี migration เกิดขึ้นเลย เป็นคนละเหตุการณ์",
        )
    }

    // ==== C1: regionIdentifier ที่มี | ปนอยู่ต้องรอดข้าม load() (ADR-20 หัวข้อ 3 ข้อ 6) ====

    /**
     * นี่คือเทสต์ที่พิสูจน์อาการจริงของบั๊ก C1: key ที่ `regionIdentifier` มี `|`
     * ปนอยู่ (เช่นตั้งชื่อ region ด้วยรหัสสาขาที่คั่นด้วย `|` เอง) ต้อง**ไม่**ถูก
     * `isValidKeyShape` ตัด state ทิ้งตอน `load()` — ก่อนแก้ C1 ฟังก์ชันนี้เช็คด้วย
     * `parts.size != 4` ตรง ๆ ซึ่งเห็น key 5 ส่วนนี้ (region มี `|` ทำให้ split ได้
     * 5 ส่วนแทนที่จะเป็น 4) เหมือน "รูปแบบเก่า" แล้วตัดทิ้งทุกรอบ — state หายเงียบ
     * ทุกรอบ ไม่ใช่แค่ event field เป็น null เหมือนที่เทสต์ pure function ใน
     * [ProximityKeyCodecTest] พิสูจน์แยกไว้แล้ว
     */
    @Test
    fun `round-trip - regionIdentifier ที่มี pipe ปนอยู่ต้องรอดข้าม load ไม่ถูก isValidKeyShape ตัดทิ้ง`() {
        val keyWithPipe = proximityKeyFor(
            regionIdentifier = "a|b",
            uuid = "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0",
            major = 9902,
            minor = 2,
        )
        val prefs = FakeSharedPreferences()
        prefs.edit().putString(
            "states_v2",
            """{"$keyWithPipe":{"confirmedBucket":"near"}}""",
        ).commit()

        val store = ProximityGateStore(mockContext(prefs))
        val restored = store.load()

        assertEquals(
            setOf(keyWithPipe),
            restored.keys,
            "key ที่ regionIdentifier มี pipe ปนอยู่ต้องไม่ถูก isValidKeyShape ตัดทิ้ง — " +
                "นี่คืออาการจริงของบั๊ก C1: state หายเงียบทุกรอบ",
        )
        assertEquals(ProximityBucket.NEAR, restored.getValue(keyWithPipe).confirmedBucket)
        assertNull(
            store.lastMigrationDroppedCount,
            "ไม่มี key ไหนควรถูกนับว่า drop ในเคสนี้เลย — ไม่มีเงื่อนไข migration เกิดขึ้น",
        )
        assertNull(store.lastError)

        // ต้องถอดกลับตรงกับที่ประกอบไว้เป๊ะ — regionIdentifier ครบ "a|b" ไม่ใช่ถูก
        // ตัดเหลือแค่ "a" (เทียบพฤติกรรมเดียวกับ ProximityKeyCodecTest ที่เทสต์
        // pure function ตรง ๆ โดยไม่ผ่านชั้น store)
        val parts = assertNotNull(proximityKeyPartsOrNull(keyWithPipe))
        assertEquals("a|b", parts.regionIdentifier)
        assertEquals("e2c56db5-dffb-48d2-b060-d0f5a71096e0", parts.uuid)
        assertEquals(9902, parts.major)
        assertEquals(2, parts.minor)
    }

    // ==== C2: commit() ตอนลบคีย์เก่าคืน false หรือโยน exception (ADR-20 หัวข้อ 3 ข้อ 1) ====

    /**
     * `commit()` คืน `false` โดยไม่โยน exception เมื่อเขียนไม่สำเร็จ — `runCatching`
     * เพียงอย่างเดียวจับสาขานี้ไม่ได้ ถ้า `load()` ไม่เช็คผลของ `commit()` ตรง ๆ
     * คีย์เก่าจะถูกนับว่า migrate สำเร็จทั้งที่ยังค้างอยู่บนดิสก์จริง
     *
     * เทสต์นี้ล็อกทั้งสามผลที่ต้องเกิดพร้อมกัน:
     * 1. ไม่มีการนับ migrated ของรอบนี้ ([lastMigrationDroppedCount] ต้องเป็น `null`)
     * 2. [lastError] ถูกตั้งแทน
     * 3. คีย์เก่ายังอยู่บนดิสก์จริง (ไม่ใช่ถูกลบไปแล้วทั้งที่รายงานว่าไม่สำเร็จ) —
     *    รอบถัดไป (จำลองด้วย store ตัวใหม่ ตรงกับที่ `BeaconScanReceiver.onReceive()`
     *    สร้าง `ProximityGateStore(context)` ใหม่ทุกครั้ง) ต้องพยายามลบใหม่ ไม่ใช่
     *    ยอมแพ้ถาวร
     */
    @Test
    fun `migration - commit() คืน false ตอนลบคีย์เก่า ไม่นับ migrated และคีย์เก่ายังอยู่ให้ลองใหม่รอบถัดไป`() {
        val prefs = FakeSharedPreferences()
        prefs.edit().putString(
            "states",
            """{"bigc-test|AA:BB:CC:DD:EE:FF":{},"bigc-test|AA:BB:CC:DD:EE:00":{}}""",
        ).commit()

        // รอบที่ 1: จำลอง commit() ตอนลบคีย์เก่าคืน false (ดิสก์เขียนไม่สำเร็จ แต่ไม่ throw)
        prefs.commitOverride = { false }
        val store1 = ProximityGateStore(mockContext(prefs))
        val restored1 = store1.load()

        assertTrue(restored1.isEmpty(), "ยังไม่มี state ใหม่อยู่ดี ไม่เกี่ยวกับผลของ migration")
        assertNull(
            store1.lastMigrationDroppedCount,
            "commit() คืน false ต้องไม่นับว่า migrate สำเร็จ — ไม่บวกเข้า migrationDropped",
        )
        assertEquals(
            "load:legacy-remove-commit-returned-false",
            store1.lastError,
            "ต้องตั้ง lastError แทนการนับ migrated เงียบ ๆ",
        )
        assertTrue(
            prefs.contains("states"),
            "commit() ล้มเหลว คีย์เก่าต้องยังอยู่บนดิสก์ ไม่ใช่ถูกลบไปแล้วทั้งที่รายงานว่าไม่สำเร็จ",
        )

        // รอบที่ 2: ดิสก์กลับมาเขียนได้ตามปกติ + store ใหม่ (ตรงกับที่ onReceive() สร้าง
        // ProximityGateStore ใหม่ทุกครั้ง) — ต้องพยายามลบคีย์เก่าอีกครั้ง ไม่มี flag
        // ค้างว่า "เคยล้มเหลว" มาบล็อกไว้
        prefs.commitOverride = null
        val store2 = ProximityGateStore(mockContext(prefs))
        val restored2 = store2.load()

        assertTrue(restored2.isEmpty())
        assertEquals(
            2,
            store2.lastMigrationDroppedCount,
            "รอบถัดไปต้องลบสำเร็จและนับ 2 entry ของคีย์เก่าได้ถูกต้อง — ไม่ใช่ยอมแพ้ถาวร",
        )
        assertNull(store2.lastError, "รอบที่ลบสำเร็จต้องไม่มี error ค้าง")
        assertFalse(prefs.contains("states"), "คีย์เก่าต้องถูกลบออกจริงในรอบที่ 2")
    }

    /**
     * `commit()` ที่โยน exception ตรง ๆ (ต่างจากคืน `false` เฉย ๆ) ต้องเข้าทางเดียวกัน
     * ทุกอย่าง — ไม่นับ migrated, ตั้ง lastError, คีย์เก่ายังอยู่ให้ลองใหม่รอบถัดไป
     */
    @Test
    fun `migration - commit() ที่ลบคีย์เก่าโยน exception ก็เข้าทางเดียวกับคืน false`() {
        val prefs = FakeSharedPreferences()
        prefs.edit().putString(
            "states",
            """{"bigc-test|AA:BB:CC:DD:EE:FF":{}}""",
        ).commit()

        prefs.commitOverride = { throw RuntimeException("disk-io") }
        val store = ProximityGateStore(mockContext(prefs))
        val restored = store.load()

        assertTrue(restored.isEmpty())
        assertNull(
            store.lastMigrationDroppedCount,
            "exception ตอนลบคีย์เก่าต้องไม่นับว่า migrate สำเร็จเช่นกัน",
        )
        assertEquals("load:legacy-remove-RuntimeException", store.lastError)
        assertTrue(
            prefs.contains("states"),
            "คีย์เก่าต้องยังอยู่หลัง exception เหมือนกรณีคืน false",
        )

        // รอบถัดไปยังพยายามลบใหม่ได้เหมือนกัน
        prefs.commitOverride = null
        val retried = ProximityGateStore(mockContext(prefs))
        retried.load()

        assertEquals(1, retried.lastMigrationDroppedCount)
        assertNull(retried.lastError)
        assertFalse(prefs.contains("states"))
    }

    /**
     * [ProximityGateStore.lastMigrationDroppedCount] กับ [ProximityGateStore.lastError]
     * ต้องเป็นคนละช่องกันเสมอ — migration ของคีย์เก่าสำเร็จได้ **พร้อมกัน** กับที่
     * `states_v2` เองพังจริงบนดิสก์ (คนละสาเหตุ คนละคอลัมน์) ไม่ใช่ผลของกันและกัน
     */
    @Test
    fun `migration - lastMigrationDroppedCount และ lastError เป็นคนละช่องกัน ไม่ปนกัน`() {
        val prefs = FakeSharedPreferences()
        prefs.edit()
            .putString("states", """{"bigc-test|AA:BB:CC:DD:EE:FF":{}}""")
            .putString("states_v2", "{ ไม่ใช่ JSON เลย ")
            .commit()

        val store = ProximityGateStore(mockContext(prefs))
        val restored = store.load()

        assertTrue(restored.isEmpty())
        assertEquals(
            1,
            store.lastMigrationDroppedCount,
            "migration ของคีย์เก่ายังนับได้ถูกต้อง แม้ states_v2 จะพังพร้อมกันก็ตาม",
        )
        assertNotNull(
            store.lastError,
            "states_v2 อ่านไม่ออกจริงต้องมี error — เป็นคนละเรื่องกับ migration ของคีย์เก่า",
        )
    }

    // ==== clearRegion() — PR A: exit-clear (docs/briefs/2026-09-14_pr-a-exit-clear-design.md §6.1) ====

    /**
     * [ข้อ 1] ต้องเป็น exact match ของ regionIdentifier ไม่ใช่ prefix — `"bigc"` กับ
     * `"bigc-test"` เป็นคนละ region แม้ชื่อหนึ่งจะขึ้นต้นด้วยอีกชื่อหนึ่งพอดี (§2 ของ
     * เอกสารออกแบบ) ถ้า `clearRegion()` เทียบด้วย `key.startsWith(regionIdentifier)`
     * ดิบ ๆ คีย์ของ `"bigc-test"` จะถูกลบไปด้วยตอนล้าง `"bigc"` ทั้งที่ไม่ควร
     */
    @Test
    fun `clearRegion - exact match เท่านั้น - ล้าง bigc ไม่กระทบ bigc-test`() {
        val prefs = FakeSharedPreferences()
        val store = ProximityGateStore(mockContext(prefs))
        val bigcKey = proximityKeyFor(
            regionIdentifier = "bigc",
            uuid = "e2c56db5-dffb-48d2-b060-d0f5a71096e0",
            major = 9902,
            minor = 1,
        )
        val bigcTestKey = proximityKeyFor(
            regionIdentifier = "bigc-test",
            uuid = "e2c56db5-dffb-48d2-b060-d0f5a71096e0",
            major = 9902,
            minor = 2,
        )
        store.save(
            mapOf(
                bigcKey to ProximityKeyState(confirmedBucket = ProximityBucket.NEAR),
                bigcTestKey to ProximityKeyState(confirmedBucket = ProximityBucket.NEAR),
            ),
        )

        val removedCount = store.clearRegion("bigc")

        assertEquals(1, removedCount, "ต้องลบแค่ key ของ bigc ตัวเดียว")
        val remaining = store.load()
        assertEquals(setOf(bigcTestKey), remaining.keys, "key ของ bigc-test ต้องยังอยู่ครบ ไม่ถูกลบ")
    }

    /**
     * [ข้อ 2] `regionIdentifier` ที่มี `|` ปนอยู่ข้างใน (`"a|b"`) ต้องล้างได้ถูกต้องครบ
     * โดยไม่กระทบ region `"a"` ที่เป็นคนละ region แม้ชื่อจะเป็นส่วนขึ้นต้นของ `"a|b"`
     * — พิสูจน์ว่า `clearRegion()` พึ่ง [proximityKeyPartsOrNull] จริง ไม่ใช่ตัดขอบเขต
     * string เอง (§2 ของเอกสารออกแบบ)
     */
    @Test
    fun `clearRegion - regionIdentifier ที่มี pipe ปนอยู่ ล้างได้ถูกต้อง ไม่กระทบ region a`() {
        val prefs = FakeSharedPreferences()
        val store = ProximityGateStore(mockContext(prefs))
        val keyWithPipe = proximityKeyFor(
            regionIdentifier = "a|b",
            uuid = "e2c56db5-dffb-48d2-b060-d0f5a71096e0",
            major = 9902,
            minor = 1,
        )
        val siblingKey = proximityKeyFor(
            regionIdentifier = "a",
            uuid = "e2c56db5-dffb-48d2-b060-d0f5a71096e0",
            major = 9902,
            minor = 2,
        )
        store.save(
            mapOf(
                keyWithPipe to ProximityKeyState(confirmedBucket = ProximityBucket.NEAR),
                siblingKey to ProximityKeyState(confirmedBucket = ProximityBucket.NEAR),
            ),
        )

        val removedCount = store.clearRegion("a|b")

        assertEquals(1, removedCount)
        val remaining = store.load()
        assertEquals(setOf(siblingKey), remaining.keys, "key ของ region \"a\" ต้องไม่ถูกลบไปด้วย")
    }

    /**
     * [ข้อ 3ก] store ว่างเปล่าไม่เคยมี key ใดเลย — ต้องได้ `removedCount == 0` และไม่มี
     * exception หลุดออกมา ไม่ทิ้ง [ProximityGateStore.lastError] ไว้
     */
    @Test
    fun `clearRegion - store ว่างเปล่า - removedCount เป็น 0 ไม่ throw`() {
        val prefs = FakeSharedPreferences()
        val store = ProximityGateStore(mockContext(prefs))

        val removedCount = store.clearRegion("ไม่มีจริง")

        assertEquals(0, removedCount)
        assertNull(store.lastError)
    }

    /**
     * [ข้อ 3ข] key รูปร่างพังถูก [load] กรองทิ้งไปแล้วตั้งแต่ก่อนถึง `clearRegion()`
     * (ผ่าน `statesFromJson()`/`isValidKeyShape()`) — `clearRegion()` จึงไม่มีทางเห็น
     * key พังเลย เป็นผลพลอยได้จากการสร้างบน [load]/[save] เดิม ไม่ throw · ปนคีย์
     * ที่รูปร่างถูกต้องไว้ด้วยหนึ่งตัว (fixture รูปแบบเดียวกับเทสต์ migration ที่มีอยู่
     * แล้วในไฟล์นี้ "entry รูปแบบเก่าที่ปนอยู่ใต้คีย์ใหม่ states_v2") เพื่อไม่ให้
     * `states` ว่างเปล่าทั้งหมดจนชน branch `unparsable` ของ [load] ที่ตั้งใจรายงาน
     * เคสคนละแบบ (ดิสก์เสียหายจริง ไม่ใช่แค่มี key รูปร่างเก่าปนมา)
     */
    @Test
    fun `clearRegion - key รูปร่างพังในดิสก์ - ไม่ throw เพราะถูก load กรองทิ้งไปก่อนแล้ว`() {
        val prefs = FakeSharedPreferences()
        prefs.edit().putString(
            "states_v2",
            """{"shape-invalid-key":{"confirmedBucket":"near"},"$key":{"confirmedBucket":"near"}}""",
        ).commit()
        val store = ProximityGateStore(mockContext(prefs))

        val removedCount = store.clearRegion("shape-invalid-key")

        assertEquals(0, removedCount, "key รูปร่างพังถูก load() กรองทิ้งไปแล้ว ไม่มีอะไรให้ clearRegion ลบ")
        assertNull(store.lastError)
        assertEquals(setOf(key), store.load().keys, "key ที่รูปร่างถูกต้องต้องไม่ถูกแตะ")
    }

    /**
     * [ข้อ 4] ไม่มี `commit()` เปล่าเมื่อไม่มีอะไรให้ลบ — พิสูจน์ทางอ้อมว่า `save()`
     * ไม่ถูกเรียกโดยไม่จำเป็นด้วยการยืนยันว่าเนื้อหาที่ [load] อ่านกลับมาหลังเรียก
     * ยังเหมือนเดิมทุกประการ (คนละ region จาก region ที่ขอล้าง)
     */
    @Test
    fun `clearRegion - ไม่มีอะไรให้ลบ - เนื้อหาเดิมไม่ถูกแตะ`() {
        val prefs = FakeSharedPreferences()
        val store = ProximityGateStore(mockContext(prefs))
        val otherKey = proximityKeyFor(
            regionIdentifier = "other-region",
            uuid = "e2c56db5-dffb-48d2-b060-d0f5a71096e0",
            major = 9902,
            minor = 1,
        )
        val before = mapOf(otherKey to ProximityKeyState(confirmedBucket = ProximityBucket.FAR))
        store.save(before)

        val removedCount = store.clearRegion("ไม่มีจริง")

        assertEquals(0, removedCount)
        val after = store.load()
        assertEquals(before.keys, after.keys)
        assertEquals(
            before.getValue(otherKey).confirmedBucket,
            after.getValue(otherKey).confirmedBucket,
            "เนื้อหาที่ไม่เกี่ยวข้องกับ region ที่ขอล้างต้องไม่ถูกแตะเลย",
        )
    }

    /**
     * [ข้อ 9 ของทั้งเอกสาร] `load()` ล้มเหลว (จำลอง `getString` throw) → ไม่ `save()`
     * → ข้อมูลเดิมบนดิสก์ไม่ถูกแตะเลย — ยืนยัน invariant ที่ท้าย §1.2 ของเอกสารออกแบบ
     *
     * ใช้ `Mockito.spy()` แยกสองมุมมองของ `SharedPreferences` ตัวเดียวกัน:
     * `spyPrefs` (มุมมองที่พัง เอาไว้ยิง `clearRegion()`) กับ `fakePrefs` ต้นฉบับ
     * (มุมมองที่ใช้ตรวจผลจริง — `Mockito.spy()` copy field state ไปยัง instance ใหม่
     * ตอนสร้าง ไม่ใช่ wrap object เดิม จึง `fakePrefs` ไม่ถูกแตะเลยหลังจากนี้)
     */
    @Test
    fun `clearRegion - load ล้มเหลว - ไม่ save และข้อมูลเดิมบนดิสก์ไม่ถูกแตะ`() {
        val fakePrefs = FakeSharedPreferences()
        ProximityGateStore(mockContext(fakePrefs)).save(mapOf(key to ProximityKeyState(confirmedBucket = ProximityBucket.NEAR)))

        val spyPrefs = Mockito.spy(fakePrefs)
        Mockito.doThrow(RuntimeException("simulated read failure"))
            .`when`(spyPrefs).getString(anyString(), Mockito.any())

        val storeOnSpy = ProximityGateStore(mockContext(spyPrefs))
        val removedCount = storeOnSpy.clearRegion(proximityKeyPartsOrNull(key)!!.regionIdentifier)

        assertEquals(0, removedCount)
        Mockito.verify(spyPrefs, Mockito.never()).edit()

        val restored = ProximityGateStore(mockContext(fakePrefs)).load()
        val state = assertNotNull(restored[key], "ข้อมูลเดิมบนดิสก์ต้องยังอยู่ครบหลัง load() ล้มเหลว")
        assertEquals(ProximityBucket.NEAR, state.confirmedBucket)
    }
}
