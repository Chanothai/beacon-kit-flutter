package com.bigc.beacon_kit_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * เทสต์ `ProximityGate` ฝั่ง Kotlin (ADR-20 หัวข้อ 2) — **port ของเทสต์ Dart ต้นทาง**
 * `packages/beacon_kit/test/proximity/proximity_gate_test.dart` กลุ่ม C, D, G, J, K
 *
 * ## ตัวเลขทุกตัวมาจากเทสต์ Dart ตัวเดียวกัน ห้ามคิดใหม่
 *
 * `ProximityGate.kt` เป็น port ตรงของ `proximity_gate.dart` ถ้าตัวเลขในไฟล์นี้ถูก
 * คิดขึ้นใหม่ให้ "เข้ากับโค้ด Kotlin" เทสต์ชุดนี้จะเลิกทำหน้าที่จริงของมันทันที —
 * หน้าที่คือพิสูจน์ว่า **สองการ implement ให้ผลเหมือนกันเป๊ะบน input ชุดเดียวกัน**
 * ไม่ใช่พิสูจน์ว่าโค้ด Kotlin ไม่ throw
 *
 * ## เวลาเดินด้วยนาฬิกาปลอมเท่านั้น — ห้าม `Thread.sleep` เด็ดขาด
 *
 * `ProximityGate` รับ [ProximityGate.clock] ทาง constructor เสมอ (ไม่มี default
 * ตามที่ kdoc ของ production บังคับไว้) ทุกเทสต์ที่เกี่ยวกับ `staleAfterMillis`
 * เดินเวลาผ่าน [FakeClock.advance] ล้วน ๆ — ถ้าไฟล์นี้เผลอรอเวลาจริงแม้แต่ที่เดียว
 * เทสต์จะกลายเป็นเทสต์ที่ช้าและกระพริบ (flaky) โดยไม่ได้ความมั่นใจเพิ่มเลย
 *
 * ## สิ่งที่ต้อง "ดัดแปลง" จากเทสต์ Dart และเหตุผล
 *
 * เทสต์ Dart ข้อ G และ J[1] เดินเส้นทาง iOS (`_iosSample(proximity:)`) ซึ่ง
 * **ไม่มีอยู่ในฝั่ง Kotlin โดยตั้งใจ** (Android ไม่มี API ที่ให้ bucket ความใกล้
 * มาเลย มีแต่ RSSI ดิบ — ดู kdoc หัวข้อ "สิ่งที่ตั้งใจไม่ port" ของ `ProximityGate`)
 * จึงเขียนใหม่ให้เดินเส้นทาง RSSI แทน โดย**รักษาเจตนาและตัวเลขเวลา/threshold เดิม
 * ไว้ทุกตัว**:
 * - G: `proximity = near` ที่ยืนยันทันที → `rssi = -48, txPower = -40,`
 *   `pathLossExponent = 2.0` (~2.51 m ≤ `enterMeters` 3.0 → NEAR) + `dwellSamples = 1`
 * - J[1]: sample ที่ "ถูกทิ้ง" ฝั่ง Dart คือ `proximity = unknown` ส่วนฝั่ง Kotlin
 *   เส้นทางทิ้ง sample คือ `txPower == null` (ADR-19 หัวข้อ 6(จ)) — คนละเหตุผล
 *   ของการทิ้ง แต่**ล็อก invariant เดียวกัน**: sample ที่ถูกทิ้งห้ามต่ออายุ
 *   `lastSampleAt`
 *
 * ⚠️ นี่คือ JVM unit test ล้วน **ไม่ได้พิสูจน์อะไรเกี่ยวกับพฤติกรรมบนเครื่องจริง**
 * (ADR-20 ยังเป็น POC และ `SPRINT.md` ข้อห้ามข้อ 2 ห้ามนับ mock/unit test เป็นการ
 * ยืนยัน Track B) — พิสูจน์แค่ว่าตรรกะเลขคณิต/สถานะตรงกับ reference ฝั่ง Dart
 */
class ProximityGateTest {

    /**
     * นาฬิกาปลอมที่เทสต์คุมเองทั้งหมด — เทียบเท่า `_FakeClock` ของไฟล์เทสต์ Dart
     * ค่าเริ่มต้นเป็น epoch millis จริงค่าหนึ่งเพื่อให้เลขดูเหมือนของจริง (ค่าไหน
     * ก็ได้ ตรรกะทั้งหมดใช้แต่ "ผลต่าง" ไม่เคยใช้ค่าสัมบูรณ์)
     */
    private class FakeClock(var nowMillis: Long = 1_757_000_000_000L) {
        fun advance(millis: Long) {
            nowMillis += millis
        }

        fun read(): Long = nowMillis
    }

    /**
     * key ทึบตามรูปแบบที่ `BeaconScanReceiver` ประกอบจริง
     * (`"<regionIdentifier>|<ScanResult.device.address>"`) — `ProximityGate`
     * ไม่ตีความสตริงนี้เลย แต่ใช้ของจริงไว้กันคนเข้าใจผิดว่าเป็น uuid/major/minor
     */
    private val key = "bigc-test|AA:BB:CC:DD:EE:FF"

    /** txPower ที่ทุกเทสต์ในไฟล์นี้ใช้ ตรงกับค่าในเทสต์ Dart กลุ่ม C/D/K */
    private val txPower = -40

    // ---------------------------------------------------------------------
    // C: hysteresis
    // ---------------------------------------------------------------------

    /**
     * port ตรงจากเทสต์ Dart กลุ่ม "C: hysteresis"
     *
     * เดิน ~6.31 → ~3.98 → ~2.51 → ~3.98 → ~5.62 m ต้องได้ transition **แค่ 2 ครั้ง**
     * (เข้าที่ 2.51 ออกที่ 5.62) ไม่ใช่ 4 — dead zone ระหว่าง `enterMeters` 3.0 กับ
     * `exitMeters` 5.0 กันไม่ให้ทุกก้าวที่ไม่ได้ข้ามเกณฑ์เดิมกลายเป็น transition ใหม่
     *
     * `windowSize`/`dwellSamples` = 1 เพื่อแยกทดสอบ hysteresis ล้วน ๆ ไม่ปนกับผลของ
     * การ smoothing หน้าต่างหรือ dwell (มีเทสต์แยกของตัวเองแล้ว)
     */
    @Test
    fun `C - เดิน 6 ถึง 2_5 ถึง 5_5 เมตร ได้ transition แค่ 2 ครั้ง ไม่ใช่ 4`() {
        val clock = FakeClock()
        val gate = ProximityGate(
            clock = clock::read,
            windowSize = 1,
            dwellSamples = 1,
            pathLossExponent = 2.0,
            enterMeters = 3.0,
            exitMeters = 5.0,
            immediateMeters = 1.0,
        )

        // priming: ยืนยัน baseline FAR ก่อนเริ่มเดิน — sample แรกของ key ใด ๆ ใช้
        // baseline เท่ากับ FAR จึงยืนยันได้ทันทีและนับเป็น transition เสมอ ซึ่ง
        // **ไม่ใช่ transition ที่โจทย์ข้อ C สนใจ** จึงไม่เก็บ/ไม่ assert ผลของ push นี้
        gate.push(key = key, rssi = -66, txPower = txPower) // ~19.95 m

        // rssi ต่อไปนี้คำนวณย้อนกลับจาก d = 10^((txPower-rssi)/(10*2.0)) ให้ตรงกับ
        // ระยะที่โจทย์ระบุ (เท่ากับค่าในเทสต์ Dart ทุกตัว)
        val transitions = mutableListOf<ProximityTransition>()
        for (rssi in listOf(-56, -52, -48, -52, -55)) {
            // ~6.31, ~3.98, ~2.51, ~3.98, ~5.62 m ตามลำดับ
            gate.push(key = key, rssi = rssi, txPower = txPower)?.let { transitions += it }
        }

        assertEquals(
            2,
            transitions.size,
            "ต้องมี transition 2 ครั้งพอดี (เข้าที่ ~2.51m ออกที่ ~5.62m) — ถ้าได้ 4 " +
                "แปลว่า dead zone ของ hysteresis หายไป",
        )
        assertEquals(ProximityTransitionReason.CLOSER, transitions[0].reason)
        assertEquals(ProximityBucket.FAR, transitions[0].from)
        assertEquals(ProximityBucket.NEAR, transitions[0].to)
        assertEquals(ProximityTransitionReason.FARTHER, transitions[1].reason)
        assertEquals(ProximityBucket.NEAR, transitions[1].from)
        assertEquals(ProximityBucket.FAR, transitions[1].to)
    }

    // ---------------------------------------------------------------------
    // D: dwell
    // ---------------------------------------------------------------------

    /**
     * port ตรงจากเทสต์ Dart กลุ่ม "D: dwell"
     *
     * 2 sample ที่อยู่ใน `enterMeters` แล้วหลุดกลับไปไกลก่อนครบ `dwellSamples` (3)
     * → ไม่มี transition เลย และ pending ต้องถูกล้าง ไม่ใช่ค้างไว้สานต่อรอบหน้า
     * (ADR-19 หัวข้อ 6(ค))
     */
    @Test
    fun `D - เข้าใกล้ 2 sample แล้วหลุดก่อนครบ dwell ต้องไม่มี transition และ pending ถูกล้าง`() {
        val clock = FakeClock()
        val gate = ProximityGate(
            clock = clock::read,
            windowSize = 1,
            pathLossExponent = 2.0,
            // dwellSamples ใช้ค่า default (3) ตรง ๆ ตามโจทย์ "2 sample แล้วหลุด"
        )

        // priming: ยืนยัน baseline FAR ก่อน (เหตุผลเดียวกับข้อ C — ไม่ assert ผล)
        gate.push(key = key, rssi = -66, txPower = txPower) // ~19.95 m
        assertEquals(ProximityBucket.FAR, gate.currentBucket(key))

        val nearRssi = -48 // ~2.51 m — อยู่ใน enterMeters (3.0)
        val t1 = gate.push(key = key, rssi = nearRssi, txPower = txPower)
        val t2 = gate.push(key = key, rssi = nearRssi, txPower = txPower)

        assertNull(t1, "sample ที่ 1 ยังไม่ครบ dwell ห้ามคืน transition")
        assertNull(t2, "sample ที่ 2 ยังไม่ครบ dwell ห้ามคืน transition")
        assertEquals(ProximityBucket.NEAR, gate.stateOf(key)?.pendingCloserBucket)
        assertEquals(2, gate.stateOf(key)?.pendingCloserCount)

        // "หลุด" — กลับไปไกลกว่า enterMeters ก่อนครบ 3 sample ติดกัน
        val t3 = gate.push(key = key, rssi = -56, txPower = txPower) // ~6.31 m

        assertNull(t3, "กลับไป FAR ซึ่งเท่ากับ bucket ที่ยืนยันอยู่แล้ว → ไม่มี transition")
        assertEquals(
            ProximityBucket.FAR,
            gate.currentBucket(key),
            "confirmedBucket ต้องไม่เคยขยับเลยตลอดเทสต์นี้",
        )
        val state = assertNotNull(gate.stateOf(key))
        assertNull(state.pendingCloserBucket, "pending ต้องถูกล้าง ไม่ใช่ค้างไว้")
        assertEquals(0, state.pendingCloserCount)
    }

    // ---------------------------------------------------------------------
    // G: stale ด้วยนาฬิกาปลอม
    // ---------------------------------------------------------------------

    /**
     * port จากเทสต์ Dart กลุ่ม "G: stale ด้วย clock ปลอม" — **ดัดแปลงจากเส้นทาง iOS
     * มาเป็นเส้นทาง RSSI** (เหตุผลอยู่ใน kdoc ของคลาสนี้) โดยคง `staleAfter` = 10
     * วินาที และการเดินนาฬิกา 11 วินาทีไว้เท่าเดิมทุกตัว
     *
     * เลยเวลา `staleAfterMillis` → `push()` คืน transition ที่ `to == null` พร้อม
     * reason STALE (ADR-19 หัวข้อ 6(ฉ)) — วัดจาก clock ที่ฉีดเข้ามา ไม่ใช่เวลาจริง
     *
     * assert เพิ่มจาก Dart: **sample ที่จุดชนวน stale ถูกทิ้งไปพร้อมกัน** (window ว่าง
     * และ `lastSampleAt == null` หลัง transition) ซึ่งเป็น design choice ที่บันทึกไว้
     * ใน ADR-19 หัวข้อ 7 และคอมเมนต์ใน `push()` ของฝั่ง Kotlin ตรง ๆ
     */
    @Test
    fun `G - เงียบเกิน staleAfter แล้ว push ใหม่ ต้องได้ reason STALE และ to เป็น null`() {
        val clock = FakeClock()
        val gate = ProximityGate(
            clock = clock::read,
            windowSize = 1,
            dwellSamples = 1,
            pathLossExponent = 2.0,
            staleAfterMillis = 10_000L,
        )

        gate.push(key = key, rssi = -48, txPower = txPower) // ~2.51 m → NEAR
        assertEquals(ProximityBucket.NEAR, gate.currentBucket(key))

        clock.advance(11_000L) // เกิน staleAfterMillis — ไม่มีการรอเวลาจริงเลย

        val t = gate.push(key = key, rssi = -48, txPower = txPower)

        val transition = assertNotNull(t, "เลย staleAfter แล้วต้องคืน transition")
        assertEquals(ProximityTransitionReason.STALE, transition.reason)
        assertEquals(ProximityBucket.NEAR, transition.from)
        assertNull(transition.to, "STALE แปลว่า 'ไม่มีคำตอบแล้ว' ไม่ใช่ FAR")
        assertNull(transition.medianMeters, "ไม่มีหน้าต่างให้คิด median อีกแล้ว")
        assertNull(gate.currentBucket(key))

        val state = assertNotNull(gate.stateOf(key))
        assertTrue(
            state.window.isEmpty(),
            "sample ที่จุดชนวน stale ต้องถูกทิ้ง ไม่ถูกประมวลผลต่อในรอบเดียวกัน",
        )
        assertNull(state.lastSampleAt)
    }

    // ---------------------------------------------------------------------
    // J[1]: sample ที่ถูกทิ้งห้ามต่ออายุ staleness
    // ---------------------------------------------------------------------

    /**
     * port จากเทสต์ Dart กลุ่ม "J: บั๊ก 4 ข้อที่แก้ใน ea7e12c" ข้อ [1/4] —
     * **ดัดแปลงเส้นทางการทิ้ง sample**: ฝั่ง Dart ทิ้งเพราะ `proximity == unknown`
     * ฝั่ง Kotlin ทิ้งเพราะ `txPower == null` (ADR-19 หัวข้อ 6(จ)) ซึ่งเป็นเส้นทาง
     * drop เดียวที่มีอยู่จริงใน Android — invariant ที่ล็อกคือตัวเดียวกันเป๊ะ
     *
     * ถ้า sample ที่ถูกทิ้งที่ t=5s เผลอต่ออายุ `lastSampleAt` (บั๊กเดิม) ช่องว่างจาก
     * t=5 ถึง t=11 จะเหลือแค่ 6 วินาที แล้วจะไม่ stale — bucket จะค้าง NEAR ตลอดไป
     * ทั้งที่ไม่มี sample ที่ใช้ตัดสินได้เลยมา 11 วินาที
     */
    @Test
    fun `J1 - sample ที่ถูก drop เพราะไม่มี txPower ห้ามต่ออายุ staleness`() {
        val clock = FakeClock()
        val startedAt = clock.nowMillis
        val gate = ProximityGate(
            clock = clock::read,
            windowSize = 1,
            dwellSamples = 1,
            pathLossExponent = 2.0,
            staleAfterMillis = 10_000L,
        )

        gate.push(key = key, rssi = -48, txPower = txPower) // t=0 ยืนยัน NEAR
        assertEquals(ProximityBucket.NEAR, gate.currentBucket(key))
        assertEquals(startedAt, gate.stateOf(key)?.lastSampleAt)

        clock.advance(5_000L)
        val dropped = gate.push(key = key, rssi = -48, txPower = null) // t=5s

        assertNull(dropped, "sample ที่ไม่มี txPower ต้องถูกทิ้งเงียบ ๆ")
        assertEquals(
            ProximityBucket.NEAR,
            gate.currentBucket(key),
            "5 วินาที ยังไม่เกิน staleAfter — bucket ต้องยังอยู่",
        )
        val afterDrop = assertNotNull(gate.stateOf(key))
        assertEquals(1, afterDrop.droppedNoTxPowerCount, "counter วินิจฉัยต้องนับขึ้นจริง")
        assertEquals(
            startedAt,
            afterDrop.lastSampleAt,
            "lastSampleAt ต้องค้างอยู่ที่ t=0 — นี่คือหัวใจของบั๊ก 1/4",
        )

        clock.advance(6_000L) // now = t=11s เทียบกับ sample ที่ใช้ตัดสินได้จริงล่าสุด
        val t = gate.push(key = key, rssi = -48, txPower = null)

        val transition = assertNotNull(
            t,
            "ช่องว่างจริงคือ 11 วินาที (> staleAfter) — ต้องหลุด stale ไม่ใช่ค้าง NEAR",
        )
        assertEquals(ProximityTransitionReason.STALE, transition.reason)
        assertEquals(ProximityBucket.NEAR, transition.from)
        assertNull(transition.to)
    }

    // ---------------------------------------------------------------------
    // K.a: stale ขณะ pending dwell
    // ---------------------------------------------------------------------

    /**
     * port ตรงจากเทสต์ Dart "[K.a] stale ขณะ pending dwell (ยังไม่ confirmed)"
     *
     * **เทสต์ตัวนี้ครอบบั๊ก 2/4 ของ `ea7e12c` ไปพร้อมกัน — "stale reset ต้องล้าง
     * pending dwell"** (ADR-19 หัวข้อ 6(ฉ): "สิ่งที่ต้อง reset เมื่อหลุด stale")
     * key ที่ค้าง dwell อยู่แล้วหายไปนานเกิน `staleAfterMillis` ต้องไม่กลับมาสานต่อ
     * ตัวนับเดิมราวกับข้อมูลต่อเนื่องกัน ไม่งั้นการ "ยืนยันความใกล้" จะเกิดจาก
     * sample ที่ห่างกันเป็นนาที ซึ่งไม่ใช่ dwell ตามความหมายที่ออกแบบไว้
     *
     * เทสต์นี้จงใจล็อกไว้ในเทสต์เดียว (ไม่มีเทสต์เปล่าที่ `skip` ถาวรสำหรับ J[2]
     * — commit `357c1aa` ลบ pattern นั้นทิ้งไปแล้วโดยตั้งใจ เพราะเทสต์ที่ถูกข้าม
     * ตลอดกาลมีค่าเป็นศูนย์แต่บดบัง skip จริงที่ควรถูกเห็นในอนาคต)
     */
    @Test
    fun `K_a - stale ขณะ pending dwell ต้องล้าง pending และไม่มี stale transition`() {
        val clock = FakeClock()
        val gate = ProximityGate(
            clock = clock::read,
            windowSize = 1,
            // dwellSamples ใช้ค่า default (3) — ต้อง > 1 เพื่อให้มีสถานะ "pending"
            // (ยังไม่ confirmed) ให้ทดสอบตามที่โจทย์ต้องการ
            pathLossExponent = 2.0,
            staleAfterMillis = 10_000L,
        )
        val nearRssi = -48 // ~2.51 m อยู่ใน enterMeters (3.0) → NEAR

        val t1 = gate.push(key = key, rssi = nearRssi, txPower = txPower)
        val t2 = gate.push(key = key, rssi = nearRssi, txPower = txPower)

        assertNull(t1)
        assertNull(t2)
        assertEquals(2, gate.stateOf(key)?.pendingCloserCount)
        assertNull(gate.currentBucket(key), "ยังไม่เคย confirmed อะไรเลย")

        clock.advance(11_000L) // เกิน staleAfterMillis

        val t3 = gate.push(key = key, rssi = nearRssi, txPower = txPower)

        assertNull(
            t3,
            "ไม่เคย confirmed มาก่อน จึงไม่มีอะไรให้ประกาศว่าหลุด — ห้ามมี STALE " +
                "transition ที่ from เป็น null",
        )
        val state = assertNotNull(gate.stateOf(key))
        assertEquals(ProximityBucket.NEAR, state.pendingCloserBucket)
        assertEquals(
            1,
            state.pendingCloserCount,
            "ต้องเริ่มนับใหม่จาก 1 ไม่ใช่สานต่อจาก 2 (บั๊ก 2/4)",
        )
        assertNull(gate.currentBucket(key))
    }
}
