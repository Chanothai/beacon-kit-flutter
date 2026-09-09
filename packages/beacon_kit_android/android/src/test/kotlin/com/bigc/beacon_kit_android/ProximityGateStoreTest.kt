package com.bigc.beacon_kit_android

import android.content.Context
import kotlin.test.Test
import kotlin.test.assertEquals
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

    private val key = "bigc-test|AA:BB:CC:DD:EE:FF"
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
     * ที่ลอยขึ้นไปทำให้ชั้น 1 (region enter/exit ที่พิสูจน์แล้ว) พังไปด้วย — เป็น
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
}
