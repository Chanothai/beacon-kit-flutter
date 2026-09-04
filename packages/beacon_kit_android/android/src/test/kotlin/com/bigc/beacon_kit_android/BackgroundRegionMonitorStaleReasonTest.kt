package com.bigc.beacon_kit_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * เทสต์ตรรกะการตัดสิน stale ของ `reconcile()` — `staleReason` (ADR-17 หัวข้อ 2)
 *
 * ## ทำไมทดสอบได้โดยไม่ต้องมี Android runtime
 *
 * `BackgroundRegionMonitor.staleReason` เป็น pure function ล้วน (แยกออกมาจาก
 * `staleReasonFor` เดิมในรอบนี้ ดูคอมเมนต์ของฟังก์ชันนั้นในไฟล์ production) — รับ
 * ค่าดิบทั้งหมดเป็นพารามิเตอร์ ไม่แตะ `BackgroundRegionStore`/`Context` เลย จึง
 * เขียนเทสต์แบบ JVM ธรรมดาได้เหมือน `BeaconRegionSpecTest`
 *
 * ⚠️ **นี่คือ refactor เชิงโครงสร้างเท่านั้น ห้ามพิสูจน์ว่า `reconcile()` ทำงาน
 * ถูกต้องบนเครื่องจริง** — K=10 (threshold 5 นาที) ยังไม่เคยทดสอบบนอุปกรณ์จริง
 * ตามที่ ADR-17 หัวข้อ 8 บันทึกไว้ เทสต์ชุดนี้พิสูจน์แค่ว่าตรรกะเลขคณิตถูกต้อง
 * ตามที่เอกสารออกแบบไว้ ไม่ใช่ว่าค่า K=10 เป็นค่าที่เหมาะสมกับพฤติกรรมจริงของ OS
 */
class BackgroundRegionMonitorStaleReasonTest {

    /** exitTimeoutSeconds ค่าเริ่มต้นของระบบ (`BackgroundRegionStore.DEFAULT_EXIT_TIMEOUT_SECONDS`) */
    private val defaultTimeoutSeconds = 30

    /** K=10 × 30s = 300,000ms (ADR-17 หัวข้อ 2) */
    private val thresholdMillisAtDefaultTimeout = 300_000L

    @Test
    fun `boot mismatch ชนะทุกอย่าง แม้ silence เป็น 0`() {
        val reason = BackgroundRegionMonitor.staleReason(
            sameBoot = false,
            nowElapsedMillis = 1_000_000L,
            lastSeenElapsedMillis = 1_000_000L, // เพิ่งเห็นเมื่อกี้นี้เอง — silence = 0
            exitTimeoutSeconds = defaultTimeoutSeconds,
        )

        assertEquals(
            "staleBootMismatch",
            reason,
            "boot mismatch ต้องเป็นความแน่นอน 100% ไม่ขึ้นกับ K เลย (ADR-17 หัวข้อ 2)",
        )
    }

    @Test
    fun `boot mismatch ชนะแม้ silence จะยังไม่ถึง threshold`() {
        val reason = BackgroundRegionMonitor.staleReason(
            sameBoot = false,
            nowElapsedMillis = thresholdMillisAtDefaultTimeout - 1,
            lastSeenElapsedMillis = 0L,
            exitTimeoutSeconds = defaultTimeoutSeconds,
        )

        assertEquals("staleBootMismatch", reason)
    }

    @Test
    fun `ต่ำกว่า threshold คืน null - ยังไม่ stale`() {
        val reason = BackgroundRegionMonitor.staleReason(
            sameBoot = true,
            nowElapsedMillis = 1_000_000L + 100_000L, // เงียบไปแค่ 100 วิ
            lastSeenElapsedMillis = 1_000_000L,
            exitTimeoutSeconds = defaultTimeoutSeconds,
        )

        assertNull(reason)
    }

    /**
     * ขอบเขต K=10 × timeout=30s = 300,000ms พอดี — เงื่อนไขในโค้ดคือ
     * `sinceLastSeen > thresholdMillis` (strictly greater) **ไม่ใช่ `>=`**
     *
     * สามเคสที่ต้องแยกให้ออก:
     * - 299,999ms (ต่ำกว่าเส้น 1ms) → ยังไม่ stale
     * - 300,000ms (เท่ากับเส้นพอดี) → **ยังไม่ stale** (`>` ไม่ใช่ `>=`)
     * - 300,001ms (เกินเส้น 1ms) → stale
     */
    @Test
    fun `ขอบเขต K10 คูณ timeout30 - ต่ำกว่าเส้นพอดี 1ms ยังไม่ stale`() {
        val reason = BackgroundRegionMonitor.staleReason(
            sameBoot = true,
            nowElapsedMillis = thresholdMillisAtDefaultTimeout - 1, // 299,999ms
            lastSeenElapsedMillis = 0L,
            exitTimeoutSeconds = defaultTimeoutSeconds,
        )

        assertNull(reason, "299999ms ต้องยังไม่ถึงเส้น 300000ms")
    }

    @Test
    fun `ขอบเขต K10 คูณ timeout30 - เท่ากับเส้นพอดี ยังไม่ stale เพราะเงื่อนไขเป็น strictly greater`() {
        val reason = BackgroundRegionMonitor.staleReason(
            sameBoot = true,
            nowElapsedMillis = thresholdMillisAtDefaultTimeout, // 300,000ms พอดี
            lastSeenElapsedMillis = 0L,
            exitTimeoutSeconds = defaultTimeoutSeconds,
        )

        assertNull(
            reason,
            "300000ms เท่ากับ threshold พอดี — โค้ดใช้ `sinceLastSeen > thresholdMillis` " +
                "(strictly greater) จึงยังไม่ stale ที่จุดนี้ ต้องเกินไปอีกอย่างน้อย 1ms",
        )
    }

    @Test
    fun `ขอบเขต K10 คูณ timeout30 - เกินเส้นพอดี 1ms กลายเป็น stale`() {
        val reason = BackgroundRegionMonitor.staleReason(
            sameBoot = true,
            nowElapsedMillis = thresholdMillisAtDefaultTimeout + 1, // 300,001ms
            lastSeenElapsedMillis = 0L,
            exitTimeoutSeconds = defaultTimeoutSeconds,
        )

        assertEquals("staleReconcile", reason, "300001ms ต้องเกินเส้น 300000ms แล้ว")
    }

    @Test
    fun `K ขยับตาม exitTimeoutSeconds ที่ผู้ใช้ SDK ตั้งเอง ไม่ใช่ค่าคงที่ตายตัว`() {
        // exitTimeoutSeconds = 5s -> threshold = 5 * 1000 * 10 = 50,000ms
        val justBelow = BackgroundRegionMonitor.staleReason(
            sameBoot = true,
            nowElapsedMillis = 50_000L,
            lastSeenElapsedMillis = 0L,
            exitTimeoutSeconds = 5,
        )
        val justAbove = BackgroundRegionMonitor.staleReason(
            sameBoot = true,
            nowElapsedMillis = 50_001L,
            lastSeenElapsedMillis = 0L,
            exitTimeoutSeconds = 5,
        )

        assertNull(justBelow, "50000ms เท่ากับ threshold ของ timeout=5s พอดี ยังไม่ stale")
        assertEquals("staleReconcile", justAbove)
    }

    @Test
    fun `สอดคล้องกับหลักฐานคืนวันที่ 3 ถึง 4 กันยายน 2026 - ความเงียบ 14 ชั่วโมงต้อง stale แน่นอน`() {
        // docs/test-data/2026-09-03_android_overnight_stale_inside.log: enter 18:00:14 ->
        // ไม่มี exit จนถึงเช้า ~08:39 = เงียบ ~14 ชม. 14 นาที ≈ 51,240,000ms ซึ่งมากกว่า
        // threshold 300,000ms (5 นาที) หลายร้อยเท่า — ไฟล์นี้ยืนยันแค่ว่า "ความเงียบ
        // 14 ชม. เกิดขึ้นจริง" ไม่ได้ยืนยันว่า K=10 คือค่าที่ถูกต้อง (ADR-17 หัวข้อ 1/8)
        val fourteenHoursFourteenMinutesMillis = 51_240_000L

        val reason = BackgroundRegionMonitor.staleReason(
            sameBoot = true,
            nowElapsedMillis = fourteenHoursFourteenMinutesMillis,
            lastSeenElapsedMillis = 0L,
            exitTimeoutSeconds = defaultTimeoutSeconds,
        )

        assertEquals("staleReconcile", reason)
    }
}
