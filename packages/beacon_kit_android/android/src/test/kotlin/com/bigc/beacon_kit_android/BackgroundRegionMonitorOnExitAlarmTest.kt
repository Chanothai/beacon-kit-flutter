package com.bigc.beacon_kit_android

import android.content.Context
import android.os.SystemClock
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito

/**
 * เทสต์ว่า `onExitAlarm` ทุก return path ที่ **ไม่ประกาศ exit** ต้องทิ้ง
 * ร่องรอย `exitAlarmDeferred` เสมอ (ADR-17 หัวข้อ 6)
 *
 * **เหตุผลที่ต้องมี:** คืน 3-4 ก.ย. 2026 (`docs/test-data/
 * 2026-09-03_android_overnight_stale_inside.log`) เงียบสนิท 14 ชั่วโมงโดยไม่มี
 * ร่องรอยอะไรเลย เพราะสาขา "เลื่อนนาฬิกาปลุกแทนการประกาศ exit" ของ `onExitAlarm`
 * เดิม (ก่อน ADR-17) ไม่เคยเรียก `emit()` เลย — เทสต์ชุดนี้ล็อกไว้ว่าทุกสาขาที่
 * ไม่ใช่ exit ต้องเรียก [BackgroundRegionMonitor.RegionStateObserver] เสมอ
 *
 * ## ทำไมต้อง mock `Context` ทั้งที่ CONTRIBUTING ข้อ 4 เตือนว่า unit test ที่
 * เขียวไม่นับเป็นการยืนยันพฤติกรรมของ OS
 *
 * `onExitAlarm` อ่านสถานะผ่าน `BackgroundRegionStore` ซึ่งต้องมี `Context` จริง
 * ในการเปิด `SharedPreferences` — [FakeSharedPreferences] implement interface
 * ตรง ๆ (ไม่ต้อง Robolectric ดูเหตุผลในไฟล์นั้น) ส่วน `Context` เอง (abstract
 * class ที่มีเมธอดนับสิบ) mock ด้วย Mockito (`mockito-core` เป็น dependency
 * ที่มีอยู่แล้วในโมดูลนี้ก่อนรอบ ADR-17 — ไม่ได้เพิ่มใหม่ในรอบนี้) เฉพาะสองเมธอด
 * ที่ `BackgroundRegionStore`/`onExitAlarm` เรียกจริง
 * (`applicationContext`/`getSharedPreferences`) เมธอดอื่นที่ไม่ได้ stub จะได้
 * ค่า default ของ Mockito (`null`/`0`/`false`) ซึ่งพอดีกับสาขาที่เทสต์นี้คลุม:
 * `scheduleExitAlarm` เรียก `getSystemService(ALARM_SERVICE)` ได้ `null` ->
 * `as? AlarmManager` ได้ `null` -> `?: return` จบเงียบๆ โดยไม่ error (โค้ด
 * production เขียนกันไว้แบบนี้อยู่แล้ว)
 *
 * `SystemClock.elapsedRealtime()` (ใช้เฉพาะเคส `stillSeen`) เป็นคลาสจริงของ
 * android.jar ที่ **มี body และโยน "Stub!"** บน JVM ธรรมดา — ใช้
 * `Mockito.mockStatic` (มาพร้อม mock maker ค่าเริ่มต้นของ `mockito-core` ตั้งแต่
 * v5.0.0 ไม่ต้องเพิ่ม dependency ใหม่) ครอบเฉพาะช่วงที่จำเป็น **ไม่แตะ
 * `System.currentTimeMillis()`** เพราะนั่นคือ `java.lang` จริง ทำงานได้ปกติบน
 * JVM อยู่แล้วโดยไม่ต้อง mock (ไม่ใช่ android stub)
 *
 * ⚠️ **ยังไม่ครอบสาขาที่ประกาศ `exit` จริง (`alarm`/`staleBootMismatch`)** —
 * สาขาเหล่านั้นไม่ใช่ขอบเขตของคำถามนี้ (ทุก return path ที่ **ไม่**ประกาศ exit
 * ต้องทิ้งร่องรอย) แต่ทำได้ด้วยเทคนิคเดียวกันทุกประการถ้าจำเป็นในอนาคต (ตั้ง
 * `now` ให้ห่างจาก `lastSeenElapsedMillis` เกิน timeoutMillis แทนที่จะน้อยกว่า)
 * — ไม่เขียนไว้ในรอบนี้เพื่อคุมขอบเขตให้ตรงกับที่โจทย์ระบุ
 */
class BackgroundRegionMonitorOnExitAlarmTest {

    private val regionIdentifier = "bigc-test"

    @AfterTest
    fun tearDown() {
        BackgroundRegionMonitor.setRegionStateObserver(null)
    }

    private fun mockContext(prefs: FakeSharedPreferences): Context {
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.applicationContext).thenReturn(context)
        Mockito.`when`(context.getSharedPreferences(anyString(), anyInt())).thenReturn(prefs)
        return context
    }

    @Test
    fun `การเฝ้าเบื้องหลังถูกสั่งหยุดแล้ว - บันทึก exitAlarmDeferred reason=notActive`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        // ไม่ตั้ง isActive เลย -> ค่า default ของ BackgroundRegionStore คือ false

        val events = mutableListOf<BackgroundRegionStateEvent>()
        BackgroundRegionMonitor.setRegionStateObserver { events += it }

        BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)

        assertEquals(1, events.size, "ต้องมีร่องรอยแม้จะไม่ active — ห้ามเงียบแบบเดิม")
        assertEquals("exitAlarmDeferred", events.single().state)
        assertEquals("notActive", events.single().deferReason)
    }

    @Test
    fun `active แต่ region นี้ไม่ inside อยู่แล้ว - บันทึก exitAlarmDeferred reason=notInside`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        BackgroundRegionStore(context).isActive = true
        // ไม่เคยเรียก recordSighting -> isInside("bigc-test") เป็น false โดย default

        val events = mutableListOf<BackgroundRegionStateEvent>()
        BackgroundRegionMonitor.setRegionStateObserver { events += it }

        BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)

        assertEquals(1, events.size)
        assertEquals("exitAlarmDeferred", events.single().state)
        assertEquals("notInside", events.single().deferReason)
    }

    @Test
    fun `นาฬิกาปลุกดังก่อนครบเวลาจริง - เลื่อนแทนประกาศ exit และบันทึก reason=stillSeen`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        val store = BackgroundRegionStore(context)
        store.isActive = true
        store.exitTimeoutSeconds = 30 // ค่าเริ่มต้นของระบบ -> timeoutMillis = 30,000

        Mockito.mockStatic(SystemClock::class.java).use { systemClock ->
            // T0: sighting แรกเข้ามา -> isInside=true, lastSeenElapsed=T0,
            // นาฬิกาปลุกถูกตั้งไว้ที่ T0+30000 (scheduledAt ที่คาดว่าจะได้กลับมา)
            val t0 = 1_000_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t0)
            store.stampBootToken()
            store.recordSighting(regionIdentifier, alarmAtElapsedMillis = t0 + 30_000L)

            // T1 = T0 + 5s: นาฬิกาปลุกดังขึ้นมา (สมมติว่าดังเร็วกว่าที่ตั้งไว้ หรือ
            // เห็น sighting ใหม่ก่อนครบเวลา) — sinceLastSeen=5000 < timeoutMillis=30000
            // ดังนั้นต้องเลื่อน ไม่ใช่ประกาศ exit — เลือก 5s (ไม่ใช่ค่าใกล้ tolerance
            // ของ boot token 10s) เพื่อไม่ให้ jitter ของนาฬิกาจริงทำให้ storedElapsed
            // TimesAreFromThisBoot() ผันผวนเป็น flaky test
            val t1 = t0 + 5_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t1)

            val events = mutableListOf<BackgroundRegionStateEvent>()
            BackgroundRegionMonitor.setRegionStateObserver { events += it }

            BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)

            assertEquals(1, events.size)
            val event = events.single()
            assertEquals("exitAlarmDeferred", event.state)
            assertEquals("stillSeen", event.deferReason)
            assertEquals(5_000L, event.exitSinceLastSeenMillis)
            assertEquals(t0 + 30_000L, event.exitScheduledAtElapsedMillis)
            assertEquals(t1, event.exitFiredAtElapsedMillis)

            // ต้องยังอยู่ในสถานะ inside — สาขานี้แค่เลื่อน ไม่ใช่พลิกสถานะ
            assertEquals(true, store.isInside(regionIdentifier))
        }
    }
}
