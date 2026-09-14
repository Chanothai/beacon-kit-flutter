package com.bigc.beacon_kit_android

import android.content.Context
import android.os.SystemClock
import android.util.Log
import java.util.UUID
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.ArgumentMatchers
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito

/**
 * เทสต์ exit-clear ของ PR A (`docs/briefs/2026-09-14_pr-a-exit-clear-design.md` §6.2) —
 * ครอบ `emitExitAndMarkOutside()` ที่เพิ่มขั้นล้าง `ProximityGateStore` เข้าไป ผ่านทั้งสอง
 * เส้นทางที่เรียกมัน (`onExitAlarm`/`reconcile`) รวมถึง `stop()` ที่ล้างทั้งหมดแยกเส้นทาง
 *
 * ไม่มีไฟล์เทสเดิมที่ครอบ `reconcile()`/`stop()` แบบ end-to-end มาก่อน (มีแค่
 * `BackgroundRegionMonitorStaleReasonTest.kt` ซึ่งเทสเฉพาะ pure function `staleReason()`
 * และ `BackgroundRegionMonitorOnExitAlarmTest.kt` ซึ่งครอบแค่ `onExitAlarm()`) — ไฟล์นี้
 * ใหม่ทั้งหมด ใช้ `mockContext(prefs)` pattern เดียวกับ `BackgroundRegionMonitorOnExitAlarmTest.kt`
 *
 * ⚠️ JVM unit test ล้วน — **ไม่ได้พิสูจน์ว่าเส้นทางเบื้องหลังบนเครื่องจริงทำงาน**
 * (ดู `SPRINT.md` — งานนี้ยัง `code-complete, unverified` จนกว่าจะมีรอบเดินอุปกรณ์จริง)
 */
class BackgroundRegionMonitorProximityExitClearTest {

    private val regionIdentifier = "bigc-test"
    private val uuid = "e2c56db5-dffb-48d2-b060-d0f5a71096e0"

    @AfterTest
    fun tearDown() {
        // เหตุผลเดียวกับ BackgroundRegionMonitorOnExitAlarmTest.kt — flutterSink/observer
        // เป็น @Volatile var ระดับ object (อายุเท่า ClassLoader) ต้องล้างทุกครั้งกัน
        // เทสต์รั่วข้ามไฟล์กัน
        BackgroundRegionMonitor.setRegionStateObserver(null)
        BackgroundRegionMonitor.setFlutterSink(null)
    }

    private fun mockContext(prefs: FakeSharedPreferences): Context {
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.applicationContext).thenReturn(context)
        Mockito.`when`(context.getSharedPreferences(anyString(), anyInt())).thenReturn(prefs)
        return context
    }

    // ==== [ข้อ 5] reconcile() และ onExitAlarm() ไหลผ่านจุดคอขวดเดียวกัน ====

    /**
     * [ข้อ 5 — ครึ่งแรก] `reconcile()` ตัดสินว่า region stale จริง (`staleReconcile`,
     * K=10 เท่าของ `exitTimeoutSeconds`) ต้องล้าง `ProximityGateStore` ของ region นั้น
     * ผ่าน `emitExitAndMarkOutside()` พร้อม log `source=reconcile`
     */
    @Test
    fun `reconcile - region stale เกิน K เท่า - ล้าง proximity ของ region นั้นและ log source=reconcile`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        val store = BackgroundRegionStore(context)
        store.regions = listOf(BeaconRegionSpec(regionIdentifier, UUID.fromString(uuid)))
        store.isActive = true
        store.exitTimeoutSeconds = 5 // K=10 -> thresholdMillis = 50,000

        val proximityKey = proximityKeyFor(regionIdentifier, uuid, major = 9902, minor = 1)
        ProximityGateStore(context).save(
            mapOf(proximityKey to ProximityKeyState(confirmedBucket = ProximityBucket.NEAR)),
        )

        Mockito.mockStatic(SystemClock::class.java).use { systemClock ->
            val t0 = 1_000_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t0)
            store.stampBootToken()
            store.recordSighting(regionIdentifier, alarmAtElapsedMillis = t0 + 5_000L)

            // จำลอง "เงียบมานาน" โดยตรงผ่าน prefs แทนการกระโดด elapsedRealtime() —
            // boot token คำนวณจาก wall-clock จริงลบ elapsedRealtime() (mocked) ถ้า
            // ขยับ elapsedRealtime() ไปมากกว่า bootTokenToleranceMillis (10,000ms คงที่
            // ของ BackgroundRegionStore.kt) จะไปโดน "staleBootMismatch" ก่อนเสมอ ไม่ว่า
            // exitTimeoutSeconds จะเป็นเท่าไหร่ก็ตาม (เพราะ threshold ของ staleReconcile
            // ที่ K=10 ย่อมมากกว่า tolerance 10,000ms เสมอสำหรับ exitTimeoutSeconds ที่
            // สมเหตุสมผล) — เขียนทับคีย์ `lastSeenElapsed.<region>` ตรง ๆ (ชื่อคีย์ตรงกับ
            // `BackgroundRegionStore.PREFIX_LAST_SEEN_ELAPSED` ที่ `BackgroundRegionStore.kt`)
            // ให้ห่างจาก `now` (ยังคง elapsedRealtime()=t0 เดิม ไม่ขยับ) เกิน threshold
            // (50,000ms) โดยไม่แตะ boot token เลย
            prefs.edit().putLong("lastSeenElapsed.$regionIdentifier", t0 - 60_000L).commit()

            val events = mutableListOf<BackgroundRegionStateEvent>()
            BackgroundRegionMonitor.setRegionStateObserver { events += it }

            Mockito.mockStatic(Log::class.java).use { log ->
                BackgroundRegionMonitor.reconcile(context)

                log.verify {
                    Log.i(
                        Mockito.eq("BgRegionMonitor"),
                        ArgumentMatchers.argThat<String> {
                            it.contains("proximityGateStore.clearRegion") &&
                                it.contains("region=$regionIdentifier") &&
                                it.contains("source=reconcile")
                        },
                    )
                }
            }

            assertEquals(1, events.size)
            assertEquals("exit", events.single().state)
            assertEquals("staleReconcile", events.single().exitReason)
            assertTrue(
                ProximityGateStore(context).load().isEmpty(),
                "proximity key ของ region ที่ reconcile ตัดสินว่า exit จริง ต้องถูกล้างออกจากดิสก์",
            )
        }
    }

    /**
     * [ข้อ 5 — ครึ่งหลัง] `onExitAlarm()` สาขา `alarm` (นาฬิกาปลุกดังหลังครบเวลาจริง)
     * ต้องได้ผลเดียวกันทุกประการกับ `reconcile()` ข้างบน — พิสูจน์ว่าทั้งสองเส้นทาง
     * ไหลผ่านจุดคอขวดเดียวกัน (`emitExitAndMarkOutside`) ไม่ใช่ implement แยกกันสองชุด
     * ที่บังเอิญให้ผลเหมือนกัน ต่างกันแค่ `source=onExitAlarm`
     */
    @Test
    fun `onExitAlarm - สาขา alarm - ล้าง proximity ของ region นั้นและ log source=onExitAlarm`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        val store = BackgroundRegionStore(context)
        store.isActive = true
        store.exitTimeoutSeconds = 5

        val proximityKey = proximityKeyFor(regionIdentifier, uuid, major = 9902, minor = 1)
        ProximityGateStore(context).save(
            mapOf(proximityKey to ProximityKeyState(confirmedBucket = ProximityBucket.NEAR)),
        )

        Mockito.mockStatic(SystemClock::class.java).use { systemClock ->
            val t0 = 1_000_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t0)
            store.stampBootToken()
            store.recordSighting(regionIdentifier, alarmAtElapsedMillis = t0 + 5_000L)

            // sinceLastSeen = 6,000 >= timeoutMillis(5,000) -> สาขา alarm
            val t1 = t0 + 6_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t1)

            val events = mutableListOf<BackgroundRegionStateEvent>()
            BackgroundRegionMonitor.setRegionStateObserver { events += it }

            Mockito.mockStatic(Log::class.java).use { log ->
                BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)

                log.verify {
                    Log.i(
                        Mockito.eq("BgRegionMonitor"),
                        ArgumentMatchers.argThat<String> {
                            it.contains("proximityGateStore.clearRegion") &&
                                it.contains("region=$regionIdentifier") &&
                                it.contains("source=onExitAlarm")
                        },
                    )
                }
            }

            assertEquals(1, events.size)
            assertEquals("exit", events.single().state)
            assertEquals("alarm", events.single().exitReason)
            assertTrue(
                ProximityGateStore(context).load().isEmpty(),
                "proximity key ของ region ที่ onExitAlarm ประกาศ exit จริง ต้องถูกล้างออกจากดิสก์ " +
                    "— ผลต้องเหมือนกับ reconcile() ข้างบนทุกประการ",
            )
        }
    }

    // ==== [ข้อ 6] สาขาที่ไม่ใช่ exit จริง ต้องไม่ล้าง proximity ====

    private fun assertProximityUntouchedAfter(
        context: Context,
        proximityKey: String,
        act: () -> Unit,
    ) {
        act()
        val remaining = ProximityGateStore(context).load()
        assertEquals(
            setOf(proximityKey),
            remaining.keys,
            "สาขาที่ไม่ใช่ exit จริง (ไม่ผ่าน emitExitAndMarkOutside) ต้องไม่แตะ proximity เลย",
        )
    }

    @Test
    fun `onExitAlarm - reason=notActive - proximity ไม่ถูกแตะ`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        // ไม่ตั้ง isActive เลย -> ค่า default คือ false

        val proximityKey = proximityKeyFor(regionIdentifier, uuid, major = 9902, minor = 1)
        ProximityGateStore(context).save(
            mapOf(proximityKey to ProximityKeyState(confirmedBucket = ProximityBucket.NEAR)),
        )

        assertProximityUntouchedAfter(context, proximityKey) {
            Mockito.mockStatic(Log::class.java).use {
                BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)
            }
        }
    }

    @Test
    fun `onExitAlarm - reason=notInside - proximity ไม่ถูกแตะ`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        BackgroundRegionStore(context).isActive = true
        // ไม่เคยเรียก recordSighting -> isInside เป็น false

        val proximityKey = proximityKeyFor(regionIdentifier, uuid, major = 9902, minor = 1)
        ProximityGateStore(context).save(
            mapOf(proximityKey to ProximityKeyState(confirmedBucket = ProximityBucket.NEAR)),
        )

        assertProximityUntouchedAfter(context, proximityKey) {
            Mockito.mockStatic(Log::class.java).use {
                BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)
            }
        }
    }

    @Test
    fun `onExitAlarm - reason=stillSeen - proximity ไม่ถูกแตะ`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        val store = BackgroundRegionStore(context)
        store.isActive = true
        store.exitTimeoutSeconds = 30

        val proximityKey = proximityKeyFor(regionIdentifier, uuid, major = 9902, minor = 1)
        ProximityGateStore(context).save(
            mapOf(proximityKey to ProximityKeyState(confirmedBucket = ProximityBucket.NEAR)),
        )

        Mockito.mockStatic(SystemClock::class.java).use { systemClock ->
            val t0 = 1_000_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t0)
            store.stampBootToken()
            store.recordSighting(regionIdentifier, alarmAtElapsedMillis = t0 + 30_000L)

            // sinceLastSeen = 5,000 < timeoutMillis(30,000) -> เลื่อนนาฬิกาปลุก ไม่ใช่ exit
            val t1 = t0 + 5_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t1)

            assertProximityUntouchedAfter(context, proximityKey) {
                Mockito.mockStatic(Log::class.java).use {
                    BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)
                }
            }
        }
    }

    // ==== [ข้อ 7] stop() ล้างทั้งหมด ไม่เลือก region ====

    @Test
    fun `stop() ล้าง ProximityGateStore ทุก region ไม่เลือก`() {
        val prefs = FakeSharedPreferences()
        val context = mockContext(prefs)
        val regionA = "bigc"
        val regionB = "bigc-test"

        val store = BackgroundRegionStore(context)
        store.regions = listOf(
            BeaconRegionSpec(regionA, UUID.fromString(uuid)),
            BeaconRegionSpec(regionB, UUID.fromString(uuid)),
        )
        store.isActive = true

        val proximityStore = ProximityGateStore(context)
        proximityStore.save(
            mapOf(
                proximityKeyFor(regionA, uuid, major = 9902, minor = 1) to
                    ProximityKeyState(confirmedBucket = ProximityBucket.NEAR),
                proximityKeyFor(regionB, uuid, major = 9902, minor = 2) to
                    ProximityKeyState(confirmedBucket = ProximityBucket.FAR),
            ),
        )
        assertEquals(2, proximityStore.load().size, "ต้องมีของให้ล้างก่อน ไม่งั้นเทสต์ผ่านฟรี")

        Mockito.mockStatic(Log::class.java).use {
            BackgroundRegionMonitor.stop(context)
        }

        assertTrue(
            ProximityGateStore(context).load().isEmpty(),
            "หลัง stop() ต้องไม่เหลือ proximity key ของ region ใดเลย ไม่ใช่แค่ region เดียว",
        )
        assertTrue(store.regions.isEmpty(), "stop() ต้องล้าง BackgroundRegionStore ด้วยเช่นกัน (ชั้น 1)")
    }

    // ==== [ข้อ 8] ชั้น 2 พังไม่ทำให้ชั้น 1 พัง (regression ของ §3) ====

    /**
     * บังคับให้ `ProximityGateStore(context)` **construction เอง** throw จริง โดย stub
     * `Context.getSharedPreferences(...)` แยกตามชื่อไฟล์ prefs — คืน [FakeSharedPreferences]
     * ปกติให้ `BackgroundRegionStore` (`"beacon_kit_android.background"`, ดู
     * `BackgroundRegionStore.kt`) แต่โยน exception ให้ `ProximityGateStore`
     * (`"beacon_kit_android.proximity"`, ดู `ProximityGateStore.kt`) เท่านั้น — ต่างจาก
     * `mockContext(prefs)` ทั่วไปของไฟล์นี้ที่คืนตัวเดียวกันทุกชื่อ
     */
    @Test
    fun `ชั้น 2 พัง - exit ของชั้น 1 ยังถูกส่งและ isInside ยังพลิกเป็น false ตามปกติ`() {
        val regionPrefs = FakeSharedPreferences()
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.applicationContext).thenReturn(context)
        Mockito.`when`(
            context.getSharedPreferences(Mockito.eq("beacon_kit_android.background"), anyInt()),
        ).thenReturn(regionPrefs)
        Mockito.`when`(
            context.getSharedPreferences(Mockito.eq("beacon_kit_android.proximity"), anyInt()),
        ).thenThrow(RuntimeException("simulated proximity store failure"))

        val store = BackgroundRegionStore(context)
        store.isActive = true
        store.exitTimeoutSeconds = 5

        Mockito.mockStatic(SystemClock::class.java).use { systemClock ->
            val t0 = 1_000_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t0)
            store.stampBootToken()
            store.recordSighting(regionIdentifier, alarmAtElapsedMillis = t0 + 5_000L)

            val t1 = t0 + 6_000L
            systemClock.`when`<Long> { SystemClock.elapsedRealtime() }.thenReturn(t1)

            val events = mutableListOf<BackgroundRegionStateEvent>()
            BackgroundRegionMonitor.setRegionStateObserver { events += it }

            // ไม่ครอบ try/catch ที่ฝั่งเทสต์เอง — ถ้า assert ผ่านทั้งหมดแปลว่าไม่มี
            // exception หลุดออกมาจาก onExitAlarm() จริง
            Mockito.mockStatic(Log::class.java).use { log ->
                BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)

                log.verify {
                    Log.w(
                        Mockito.eq("BgRegionMonitor"),
                        ArgumentMatchers.argThat<String> {
                            it.contains("proximityGateStore.clearRegion ล้มเหลว") &&
                                it.contains("region=$regionIdentifier") &&
                                it.contains("source=onExitAlarm")
                        },
                        ArgumentMatchers.any(Throwable::class.java),
                    )
                }
            }

            assertEquals(1, events.size, "event exit ของชั้น 1 ยังต้องถูกส่งไปที่ observer ตามปกติ")
            assertEquals("exit", events.single().state)
            assertEquals(
                false,
                store.isInside(regionIdentifier),
                "isInside ต้องพลิกเป็น false ตามปกติ ไม่ค้างเป็น true เพราะชั้น 2 พัง",
            )
        }
    }
}
