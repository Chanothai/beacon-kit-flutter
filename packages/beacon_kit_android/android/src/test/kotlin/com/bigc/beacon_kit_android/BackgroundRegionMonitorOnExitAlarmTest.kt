package com.bigc.beacon_kit_android

import android.content.Context
import android.os.SystemClock
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito

/**
 * เทสต์ทุก return path ของ `onExitAlarm` — ทั้งสองฝั่ง: สาขาที่ไม่ประกาศ exit
 * (ต้องทิ้งร่องรอย `exitAlarmDeferred` เสมอ, ADR-17 หัวข้อ 6) และสาขาที่ประกาศ
 * exit จริง (`alarm`/`staleBootMismatch`, ADR-17 หัวข้อ 4)
 *
 * **เหตุผลที่ต้องมี:** คืน 3-4 ก.ย. 2026 (`docs/test-data/
 * 2026-09-03_android_overnight_stale_inside.log`) เงียบสนิท 14 ชั่วโมงโดยไม่มี
 * ร่องรอยอะไรเลย เพราะสาขา "เลื่อนนาฬิกาปลุกแทนการประกาศ exit" ของ `onExitAlarm`
 * เดิม (ก่อน ADR-17) ไม่เคยเรียก `emit()` เลย — เทสต์ชุดนี้ล็อกไว้ว่าทุกสาขาที่
 * ไม่ใช่ exit ต้องเรียก [BackgroundRegionMonitor.RegionStateObserver] เสมอ
 * และล็อกไว้ด้วยว่าสาขาที่ประกาศ exit จริงยังรักษาลำดับ "หลักฐานลงดิสก์ก่อน
 * พลิกสถานะ" ตามที่ commit `735bce0` แก้ไว้
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
 * `SystemClock.elapsedRealtime()` เป็นคลาสจริงของ android.jar ที่ **มี body
 * และโยน "Stub!"** บน JVM ธรรมดา — ใช้ `Mockito.mockStatic` (มาพร้อม mock maker
 * ค่าเริ่มต้นของ `mockito-core` ตั้งแต่ v5.0.0 ไม่ต้องเพิ่ม dependency ใหม่)
 * ครอบเฉพาะช่วงที่จำเป็น **ไม่แตะ `System.currentTimeMillis()`** เพราะนั่นคือ
 * `java.lang` จริง ทำงานได้ปกติบน JVM อยู่แล้วโดยไม่ต้อง mock (ไม่ใช่ android
 * stub)
 *
 * ## ทำไมต้องมี `testImplementation("org.json:json:20240303")`
 *
 * สาขา `alarm`/`staleBootMismatch` เรียก `store.markOutsideAndEnqueueEvent()`
 * ซึ่งเรียก `BackgroundRegionStateEvent.toJson()` → `JSONObject().apply {
 * put(...) }` ตรง ๆ (`BackgroundRegionStore.kt`) — ต่างจาก `SharedPreferences`
 * ที่เป็น interface ปลอมเองได้ `org.json.JSONObject`/`JSONArray` ใน android.jar
 * ที่ unit test คอมไพล์ด้วยเป็น**คลาสจริงที่มี body** ซึ่งโยน
 * `RuntimeException("Method put in org.json.JSONObject not mocked")` เสมอบน
 * JVM ธรรมดา (คนละปัญหากับ `SystemClock`/`Context` ที่ mock ด้วย Mockito ได้)
 * — เพิ่ม dependency ตัวจริงของ `org.json` ลง test classpath แก้ปัญหานี้ตรง ๆ
 * โดยได้ตรวจ JSON ที่เขียนจริงไปด้วย ไม่ใช่แค่ผ่านเพราะไม่ throw
 *
 * ## ทำไมต้องเทสต์ทั้งสองเส้นทาง (`flutterSink == null` และ `!= null`)
 *
 * `emitExitAndMarkOutside` (`BackgroundRegionMonitor.kt`) แยกสองเส้นทางตามว่ามี
 * Flutter engine ทำงานอยู่หรือไม่:
 * - **`flutterSink == null`** (ไม่มี engine — เส้นทางเบื้องหลังจริงตอนแอปโดน
 *   ระบบฆ่า) → `store.markOutsideAndEnqueueEvent()` → เดิน JSON — **นี่คือ
 *   เส้นทางที่บั๊กของ ADR-17 ทั้งฉบับเกิด** (คืน 3-4 ก.ย. 2026 ไม่มี Flutter
 *   engine ทำงานอยู่เลยตลอดคืน)
 * - **`flutterSink != null`** (แอปเปิดอยู่ foreground) → `sink.onRegionStateEvent`
 *   แล้ว `store.markOutside()` เฉยๆ — ไม่แตะ JSON เลย
 *
 * ทั้งสองเส้นทางเรียก [BackgroundRegionMonitor.RegionStateObserver] (`observer`,
 * ตัวเขียนไฟล์หลักฐานของ host app) **ก่อนเสมอ** ไม่ว่าจะมี sink หรือไม่ — เทสต์
 * ที่ครอบแค่เส้นทางเดียวพิสูจน์ไม่ได้ว่าอีกเส้นทางยังรักษาลำดับเดิมอยู่ (พบจาก
 * reviewer ตอนรีวิวรอบสุดท้ายของ ADR-17)
 */
class BackgroundRegionMonitorOnExitAlarmTest {

    private val regionIdentifier = "bigc-test"

    @AfterTest
    fun tearDown() {
        BackgroundRegionMonitor.setRegionStateObserver(null)
        // ต้องล้างเสมอ — `flutterSink` เป็น `@Volatile var` ระดับ `object` (อายุ
        // เท่า ClassLoader) เทสต์ไหนตั้งค่านี้ไว้แล้วไม่ล้าง จะรั่วไปกระทบเทสต์
        // อื่นในไฟล์เดียวกันหรือไฟล์ถัดไปที่รันใน JVM worker เดียวกัน
        BackgroundRegionMonitor.setFlutterSink(null)
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

    // ---- สาขา `alarm` (ADR-17 หัวข้อ 4) — ทั้งสองเส้นทาง flutterSink ----

    /**
     * ทำไมใช้ `exitTimeoutSeconds = 5` แทนค่าเริ่มต้น 30: `storedElapsedTimes
     * AreFromThisBoot()` เทียบ "boot token" สองค่าด้วย tolerance คงที่ 10
     * วินาที (`BackgroundRegionStore.kt`, `bootTokenToleranceMillis`) — ในเทสต์
     * `System.currentTimeMillis()` จริงแทบไม่ขยับระหว่างสอง call (ทดสอบใช้เวลา
     * ระดับมิลลิวินาที ไม่ใช่ 30 วินาทีจริงบนอุปกรณ์) มีแต่ `elapsedRealtime()`
     * ที่ mock ให้กระโดด ผลคือช่องว่างระหว่างสอง `elapsedRealtime()` เท่ากับ
     * ผลต่างของ boot token โดยตรง — ถ้าใช้ timeout เริ่มต้น 30s (มากกว่า
     * tolerance 10s) การจำลอง "sinceLastSeen ≥ timeout" จะไปโดน boot-mismatch
     * ก่อนเสมอ (คนละสาขา) — ลดเหลือ 5s แล้วเลื่อนแค่ 6,000ms จึงได้ทั้ง "เกิน
     * timeout" และ "ยังอยู่ใต้ tolerance" พร้อมกัน — เทคนิคจำลองนาฬิกาในเทสต์
     * เท่านั้น **ไม่ได้แตะค่าเริ่มต้น 30s ของระบบจริงเลย**
     */
    @Test
    fun `alarm - ไม่มี flutterSink - exit reason=alarm ครบฟิลด์เวลา และเรียก observer ก่อน markOutside`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        val store = BackgroundRegionStore(context)
        store.isActive = true
        store.exitTimeoutSeconds = 5

        Mockito.mockStatic(SystemClock::class.java).use { systemClock ->
            val t0 = 1_000_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t0)
            store.stampBootToken()
            store.recordSighting(regionIdentifier, alarmAtElapsedMillis = t0 + 5_000L)

            // sinceLastSeen = 6000 >= timeoutMillis(5000) -> สาขา alarm
            val t1 = t0 + 6_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t1)

            val events = mutableListOf<BackgroundRegionStateEvent>()
            var isInsideWhenObserverCalled: Boolean? = null
            BackgroundRegionMonitor.setRegionStateObserver { event ->
                // อ่านค่าจากดิสก์ทันทีตอนถูกเรียก — ถ้า markOutside ถูกเรียกไป
                // ก่อนหน้าแล้ว ค่านี้จะกลายเป็น false
                isInsideWhenObserverCalled = store.isInside(regionIdentifier)
                events += event
            }
            // ไม่ตั้ง flutterSink -> เดินเส้นทาง markOutsideAndEnqueueEvent()
            // (JSON) ซึ่งเป็นเส้นทางที่บั๊กจริงของ ADR-17 เกิด

            BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)

            assertEquals(1, events.size)
            val event = events.single()
            assertEquals("exit", event.state)
            assertEquals("alarm", event.exitReason)
            assertEquals(6_000L, event.exitSinceLastSeenMillis)
            assertEquals(t0 + 5_000L, event.exitScheduledAtElapsedMillis)
            assertEquals(t1, event.exitFiredAtElapsedMillis)

            assertEquals(
                true,
                isInsideWhenObserverCalled,
                "observer ต้องเห็น isInside=true ตอนถูกเรียก เพราะยังไม่ถูก markOutside " +
                    "(ลำดับที่ commit 735bce0 แก้ไว้ — หลักฐานลงดิสก์ก่อนพลิกสถานะ)",
            )
            assertEquals(
                false,
                store.isInside(regionIdentifier),
                "หลัง onExitAlarm จบการทำงานแล้ว ต้องถูกพลิกเป็น outside แล้วจริง",
            )
            assertEquals(
                1,
                store.pendingEventCount(),
                "ไม่มี flutterSink -> event ต้องถูก enqueue ลงดิสก์ (ผ่าน JSON) รอ Dart มารับ",
            )
        }
    }

    @Test
    fun `alarm - มี flutterSink - observer และ sink ได้ event เดียวกัน ก่อน markOutside แบบไม่ผ่าน JSON`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        val store = BackgroundRegionStore(context)
        store.isActive = true
        store.exitTimeoutSeconds = 5

        Mockito.mockStatic(SystemClock::class.java).use { systemClock ->
            val t0 = 2_000_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t0)
            store.stampBootToken()
            store.recordSighting(regionIdentifier, alarmAtElapsedMillis = t0 + 5_000L)

            val t1 = t0 + 6_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t1)

            val observerEvents = mutableListOf<BackgroundRegionStateEvent>()
            var isInsideWhenObserverCalled: Boolean? = null
            BackgroundRegionMonitor.setRegionStateObserver { event ->
                isInsideWhenObserverCalled = store.isInside(regionIdentifier)
                observerEvents += event
            }

            val sinkEvents = mutableListOf<BackgroundRegionStateEvent>()
            var isInsideWhenSinkCalled: Boolean? = null
            BackgroundRegionMonitor.setFlutterSink { event ->
                isInsideWhenSinkCalled = store.isInside(regionIdentifier)
                sinkEvents += event
            }

            BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)

            assertEquals(1, observerEvents.size)
            assertEquals(1, sinkEvents.size)
            for (event in listOf(observerEvents.single(), sinkEvents.single())) {
                assertEquals("exit", event.state)
                assertEquals("alarm", event.exitReason)
                assertEquals(6_000L, event.exitSinceLastSeenMillis)
                assertEquals(t0 + 5_000L, event.exitScheduledAtElapsedMillis)
                assertEquals(t1, event.exitFiredAtElapsedMillis)
            }

            assertEquals(
                true,
                isInsideWhenObserverCalled,
                "observer (ตัวเขียนไฟล์หลักฐานของ host app) ต้องถูกเรียกก่อน markOutside " +
                    "เสมอ ไม่ว่าจะมี flutterSink หรือไม่",
            )
            assertEquals(
                true,
                isInsideWhenSinkCalled,
                "sink (ไปหา Dart) ก็ต้องถูกเรียกก่อน markOutside เช่นกัน — เส้นทางนี้เรียก " +
                    "sink ก่อนแล้วค่อย store.markOutside() ตามโค้ด emitExitAndMarkOutside",
            )
            assertEquals(false, store.isInside(regionIdentifier))
            assertEquals(
                0,
                store.pendingEventCount(),
                "มี flutterSink -> ส่งตรงถึง Dart ไม่ต้อง enqueue ลงดิสก์ (ไม่แตะ JSON เลย " +
                    "ในเส้นทางนี้)",
            )
        }
    }

    // ---- สาขา `staleBootMismatch` (ADR-17 หัวข้อ 2/4) — ทั้งสองเส้นทาง flutterSink ----

    /**
     * จำลอง boot mismatch ด้วยการทำให้ `elapsedRealtime()` "กระโดดกลับ" เหมือน
     * เพิ่งรีบูตจริง (ค่าที่นับจากตอนบูตรีเซ็ตกลับไปใกล้ 0) — ผลต่างของ boot
     * token ที่ได้ใหญ่กว่า tolerance 10 วินาทีมาก ไม่ว่า `exitTimeoutSeconds`
     * จะเป็นเท่าไหร่ก็ตาม จึงใช้ค่าเริ่มต้นของระบบได้ตามปกติ
     */
    @Test
    fun `staleBootMismatch - ไม่มี flutterSink - exit reason=staleBootMismatch โดยไม่มีเลขเวลาปลอม`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        val store = BackgroundRegionStore(context)
        store.isActive = true

        Mockito.mockStatic(SystemClock::class.java).use { systemClock ->
            // ก่อน "รีบูต" — เครื่องเปิดมานานแล้ว elapsedRealtime จึงมีค่าสูง
            val beforeReboot = 999_000_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(beforeReboot)
            store.stampBootToken()
            store.recordSighting(regionIdentifier, alarmAtElapsedMillis = beforeReboot + 30_000L)

            // จำลองรีบูต: elapsedRealtime นับจากตอนบูตเสมอ ค่าที่รีเซ็ตกลับไป
            // ใกล้ 0 ทำให้ boot token ที่เก็บไว้ก่อนหน้าเทียบกับตอนนี้ไม่ได้อีก
            val afterReboot = 500L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(afterReboot)

            val events = mutableListOf<BackgroundRegionStateEvent>()
            var isInsideWhenObserverCalled: Boolean? = null
            BackgroundRegionMonitor.setRegionStateObserver { event ->
                isInsideWhenObserverCalled = store.isInside(regionIdentifier)
                events += event
            }
            // ไม่ตั้ง flutterSink -> เดินเส้นทาง markOutsideAndEnqueueEvent() (JSON)

            BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)

            assertEquals(1, events.size)
            val event = events.single()
            assertEquals("exit", event.state)
            assertEquals("staleBootMismatch", event.exitReason)
            assertNull(
                event.exitSinceLastSeenMillis,
                "ห้ามมีเลขปลอม — เทียบเวลาข้ามรอบบูตไม่ได้จริง ๆ",
            )
            assertNull(event.exitScheduledAtElapsedMillis, "ห้ามมีเลขปลอม")
            assertNull(event.exitFiredAtElapsedMillis, "ห้ามมีเลขปลอม")

            assertEquals(true, isInsideWhenObserverCalled, "observer ต้องถูกเรียกก่อน markOutside")
            assertEquals(false, store.isInside(regionIdentifier))
            assertEquals(1, store.pendingEventCount())
        }
    }

    @Test
    fun `staleBootMismatch - มี flutterSink - observer และ sink ได้ event เดียวกัน ฟิลด์เวลาเป็น null ทั้งสามค่า`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        val store = BackgroundRegionStore(context)
        store.isActive = true

        Mockito.mockStatic(SystemClock::class.java).use { systemClock ->
            val beforeReboot = 888_000_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(beforeReboot)
            store.stampBootToken()
            store.recordSighting(regionIdentifier, alarmAtElapsedMillis = beforeReboot + 30_000L)

            val afterReboot = 700L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(afterReboot)

            val observerEvents = mutableListOf<BackgroundRegionStateEvent>()
            var isInsideWhenObserverCalled: Boolean? = null
            BackgroundRegionMonitor.setRegionStateObserver { event ->
                isInsideWhenObserverCalled = store.isInside(regionIdentifier)
                observerEvents += event
            }

            val sinkEvents = mutableListOf<BackgroundRegionStateEvent>()
            var isInsideWhenSinkCalled: Boolean? = null
            BackgroundRegionMonitor.setFlutterSink { event ->
                isInsideWhenSinkCalled = store.isInside(regionIdentifier)
                sinkEvents += event
            }

            BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)

            assertEquals(1, observerEvents.size)
            assertEquals(1, sinkEvents.size)
            for (event in listOf(observerEvents.single(), sinkEvents.single())) {
                assertEquals("exit", event.state)
                assertEquals("staleBootMismatch", event.exitReason)
                assertNull(event.exitSinceLastSeenMillis, "ห้ามมีเลขปลอม")
                assertNull(event.exitScheduledAtElapsedMillis, "ห้ามมีเลขปลอม")
                assertNull(event.exitFiredAtElapsedMillis, "ห้ามมีเลขปลอม")
            }

            assertEquals(true, isInsideWhenObserverCalled)
            assertEquals(true, isInsideWhenSinkCalled)
            assertEquals(false, store.isInside(regionIdentifier))
            assertEquals(
                0,
                store.pendingEventCount(),
                "มี flutterSink -> ไม่ enqueue ลงดิสก์ ไม่แตะ JSON เลยในเส้นทางนี้",
            )
        }
    }
}
