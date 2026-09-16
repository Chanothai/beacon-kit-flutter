package com.beaconkit.example

import com.bigc.beacon_kit_android.ProximityBucket
import com.bigc.beacon_kit_android.ProximityChangedEvent
import com.bigc.beacon_kit_android.ProximityTransitionReason
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * ล็อก**รูปแบบของฟิลด์ระบุบีคอน**ในบรรทัดหลักฐานฝั่ง Android (เพิ่ม 11 ก.ย. 2026)
 *
 * ## ทำไมต้องมีเทสต์นี้
 *
 * ฟิลด์ `beacon=` ฝั่ง Android เคยเป็น **MAC สองไบต์ท้าย** ส่วนฝั่ง iOS เป็น
 * `<major>/<minor>` — ชื่อฟิลด์เดียวกันแต่ความหมายคนละอย่าง ทำให้**จับคู่บรรทัดของ
 * สองแพลตฟอร์มเข้าหากันไม่ได้** และทำให้ `docs/beacon-inventory.md` เติมช่อง
 * "tag ↔ major/minor" ไม่ได้เลย
 *
 * รอบนี้แยกเป็นสองฟิลด์: `beacon=<major>/<minor>` (ตัวระบุเชิงตรรกะ ตรงกับ iOS)
 * และ `mac=<2 ไบต์ท้าย>` (ตัวแยกเชิงกายภาพ เป็นค่าเดียวกับใน gate key)
 *
 * **เทสต์นี้พิสูจน์จากผลลัพธ์จริงของฟังก์ชัน ไม่ใช่จากการอ่านโค้ด** ตามที่ผู้ตรวจ
 * รอบนี้กำหนดไว้
 *
 * ## สิ่งที่เทสต์นี้ **ไม่** พิสูจน์
 *
 * **ไม่ได้พิสูจน์ว่าค่าจริงในสนามจะไม่ใช่ `n/a`** — `ProximityChangedEvent.major/minor`
 * มาจาก **region spec ที่ลงทะเบียนไว้** ไม่ใช่จากเฟรม (ADR-14 หัวข้อ 4.1) และ
 * `main.dart` ลงทะเบียนทั้งสอง region ด้วย UUID อย่างเดียว **ค่าจริงวันนี้จึงเป็น
 * `n/a` ทุกบรรทัด** · ดูหนี้ที่ `docs/beacon-inventory.md`
 */
class ExampleProximityWatcherTest {

    private fun event(
        major: Int?,
        minor: Int?,
        beaconTag: String? = "55:4D",
        droppedNoIdentityCount: Int = 0,
        regionIdentifier: String = "bigc-test",
        uuid: String? = "7777772e-6b6b-6d63-6e2e-636f6d000001",
        reason: ProximityTransitionReason = ProximityTransitionReason.CLOSER,
    ) = ProximityChangedEvent(
        regionIdentifier = regionIdentifier,
        uuid = uuid,
        major = major,
        minor = minor,
        from = ProximityBucket.FAR,
        to = ProximityBucket.NEAR,
        reason = reason,
        medianMeters = 1.2,
        timestampMillis = 1_757_000_000_000L,
        rssi = -37,
        txPower = -51,
        beaconTag = beaconTag,
        storeError = null,
        droppedNoIdentityCount = droppedNoIdentityCount,
    )

    /** **เคสหลัก:** มี major/minor ครบ → ต้องพิมพ์ `<major>/<minor>` ตรง ๆ */
    @Test
    fun beaconFieldPrintsMajorSlashMinor() {
        assertEquals("9902/2", ExampleProximityWatcher.beaconField(event(9902, 2)))
        assertEquals("9903/3", ExampleProximityWatcher.beaconField(event(9903, 3)))
    }

    /**
     * ค่าใดค่าหนึ่งหาย → `n/a` **ไม่ใช่ `"9902/null"`**
     *
     * สตริงที่มี `null` ปนอ่านแล้วเข้าใจผิดว่า "รู้ major แต่ไม่รู้ minor" ทั้งที่
     * ทั้งคู่มาจากแหล่งเดียวกันและหายพร้อมกันเสมอ
     */
    @Test
    fun beaconFieldIsNotApplicableWhenEitherHalfIsMissing() {
        assertEquals("n/a", ExampleProximityWatcher.beaconField(event(null, null)))
        assertEquals("n/a", ExampleProximityWatcher.beaconField(event(9902, null)))
        assertEquals("n/a", ExampleProximityWatcher.beaconField(event(null, 2)))
    }

    /**
     * **บรรทัดจริงต้องมีทั้ง `beacon=` และ `mac=` และต้องเป็นคนละค่า** — ถ้าใครรวม
     * สองฟิลด์กลับเป็นตัวเดียวในอนาคต เทสต์นี้ต้องแดงทันที
     */
    @Test
    fun rawSignalsSuffixCarriesBothLogicalAndPhysicalIdentifiers() {
        val suffix = ExampleProximityWatcher.rawSignalsSuffix(event(9902, 2, "55:4D"))

        assertTrue(suffix.contains(" beacon=9902/2 "), "ต้องมี beacon=<major>/<minor>: $suffix")
        assertTrue(suffix.contains(" mac=55:4D"), "ต้องมี mac=<2 ไบต์ท้าย>: $suffix")
    }

    /** ค่าที่หายต้องอ่านออกว่า "ตอบไม่ได้" ทั้งสองฟิลด์ ห้ามเป็นช่องว่าง */
    @Test
    fun missingIdentifiersStillPrintReadableValues() {
        val suffix = ExampleProximityWatcher.rawSignalsSuffix(event(null, null, null))

        assertTrue(suffix.contains(" beacon=n/a "), suffix)
        assertTrue(suffix.contains(" mac=n/a"), suffix)
    }

    /**
     * บีคอนคนละตัวใน region เดียวกันต้องให้ suffix ที่ต่างกัน **แม้ `beacon=` จะเป็น
     * `n/a` ทั้งคู่** — ซึ่งเป็นสภาพจริงของ example app วันนี้ (region ลงทะเบียนด้วย
     * UUID อย่างเดียว) · ถ้าข้อนี้พังแปลว่า `mac=` หลุดหายไปและเรากลับไปสู่ปัญหา
     * "stale หลายบรรทัดติดกันอ่านเหมือนบั๊กยิงซ้ำ" ของ 9 ก.ย. 2026
     */
    @Test
    fun physicalIdentifierStillSeparatesBeaconsWhenLogicalOneIsUnknown() {
        val first = ExampleProximityWatcher.rawSignalsSuffix(event(null, null, "55:4D"))
        val second = ExampleProximityWatcher.rawSignalsSuffix(event(null, null, "55:50"))

        assertTrue(first != second, "บีคอนคนละตัวต้องแยกออกจากกันได้เสมอ")
    }

    /**
     * สองบีคอนที่มี major/minor ถอดจากเฟรมได้จริง (สภาพหลัง ADR-20 หัวข้อ 1 แก้
     * 11 ก.ย. 2026 — ต่างจากเทสต์ข้างบนที่จำลองสภาพเก่าตอน region ลงทะเบียนด้วย
     * UUID อย่างเดียว) ต้องได้บรรทัดหลักฐานที่ต่างกันทั้งฟิลด์ตรรกะ (`beacon=`) และ
     * ข้อความที่จะถูกใช้ประกอบ title ของ notification (`ExampleProximityWatcher
     * .onProximityChanged` ต่อ `จุด ${beaconField(event)}` ตรง ๆ) — พิสูจน์ที่
     * `beaconField()` ตรง ๆ เพราะ `onProximityChanged` ที่ประกอบ title จริงเป็น
     * `private` และเรียก `Context` (ดูหมายเหตุท้ายไฟล์นี้ว่าทำไมส่วนคูลดาวน์จริง
     * ยังทดสอบเป็น unit test ไม่ได้ในรอบนี้)
     */
    @Test
    fun rawSignalsSuffixDiffersAcrossRealBeaconsInSameRegion() {
        val first = ExampleProximityWatcher.rawSignalsSuffix(event(9902, 2, "55:4D"))
        val second = ExampleProximityWatcher.rawSignalsSuffix(event(9903, 3, "55:50"))

        assertTrue(first != second, "บีคอนคนละตัว (9902/2 vs 9903/3) ต้องได้บรรทัดที่ต่างกันเสมอ")
        assertTrue(first.contains("beacon=9902/2"))
        assertTrue(second.contains("beacon=9903/3"))
    }

    /**
     * `droppedNoIdentity=<n>` ต้องพิมพ์**เสมอ**ทุกบรรทัด ไม่ใช่แค่ตอนมากกว่า 0
     * (ต่างจากพฤติกรรมของ `store=` ที่มีค่า `ok` เป็น sentinel — ที่นี่ใช้ตัวเลข `0`
     * ตรง ๆ เป็น sentinel ของ "ถามแล้วไม่มีอะไรถูกทิ้ง") ถ้าฟิลด์นี้หายไปจากบรรทัด
     * จะแยกไม่ออกระหว่าง "ไม่มีอะไรถูกทิ้งจริง" กับ "log รุ่นเก่าที่ยังไม่มีคอลัมน์นี้"
     */
    @Test
    fun droppedNoIdentityAlwaysPrintedEvenWhenZero() {
        val zero = ExampleProximityWatcher.rawSignalsSuffix(event(9902, 2, droppedNoIdentityCount = 0))
        val nonZero = ExampleProximityWatcher.rawSignalsSuffix(event(9902, 2, droppedNoIdentityCount = 3))

        assertTrue(zero.contains("droppedNoIdentity=0"), zero)
        assertTrue(nonZero.contains("droppedNoIdentity=3"), nonZero)
    }

    // ------------------------------------------------------------------
    // ADR-25 §3/§3.1 — คูลดาวน์ที่สอง 30 นาที (เพิ่มโดย beacon-qa, 16 ก.ย. 2026)
    //
    // เจ็ดเคสข้างล่างครอบคลุมสัญญาที่ 8d31df0 แยกไว้เป็น pure function เพื่อให้
    // เทสต์ได้จริงโดยไม่ต้องมี Context/SharedPreferences: `LONG_COOLDOWN_MILLIS`,
    // `longCooldownKeyFor(event)`, `longCooldownSinceLastPostedMillisOrNull(...)`
    // ------------------------------------------------------------------

    /** เคส 1: ไม่เคยโพสต์คีย์นี้สำเร็จมาก่อน (`0L`) → ต้องยิงได้ (`null`) */
    @Test
    fun longCooldownAllowsFirstEverPostForKey() {
        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = 0L,
            nowElapsedMillis = 1_000_000L,
        )

        assertEquals(null, result, "ไม่เคยโพสต์คีย์นี้มาก่อนต้องยิงได้เสมอ")
    }

    /**
     * เคส 2: โพสต์ครั้งที่สองภายใน 30 นาที → ต้องไม่ยิง (non-null) **และค่า
     * `sinceLastPostedMs` ที่คืนต้องตรงกับส่วนต่างจริง** ไม่ใช่แค่ตรวจว่า non-null
     */
    @Test
    fun longCooldownBlocksSecondPostWithinWindowAndReturnsExactElapsed() {
        val lastPosted = 1_000_000L
        val elapsedSinceLastPost = 5 * 60 * 1_000L // 5 นาที — ยังไม่ครบ 30 นาที
        val now = lastPosted + elapsedSinceLastPost

        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = now,
        )

        assertEquals(
            elapsedSinceLastPost,
            result,
            "ค่าที่คืนต้องเท่ากับ now - lastPosted เป๊ะ ไม่ใช่แค่ non-null",
        )
    }

    /**
     * เคส 3ก: ขอบล่าง — เหลืออีก 1 มิลลิวินาทีจะครบ 30 นาที → ยังติดคูลดาวน์
     * (`LONG_COOLDOWN_MILLIS - 1` ยังน้อยกว่าเพดาน)
     */
    @Test
    fun longCooldownStillBlocksOneMillisecondBeforeWindowElapses() {
        // lastPosted ต้องไม่เป็น 0L — 0L คือ sentinel ของ "ไม่เคยโพสต์มาก่อน"
        // (เข้าเงื่อนไขแรกของฟังก์ชันแล้วคืน null ทันทีโดยไม่ทดสอบขอบเวลาเลย)
        val lastPosted = 1L
        val now = lastPosted + ExampleProximityWatcher.LONG_COOLDOWN_MILLIS - 1

        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = now,
        )

        assertEquals(
            ExampleProximityWatcher.LONG_COOLDOWN_MILLIS - 1,
            result,
            "ยังไม่ครบ 30 นาที (ขาดอยู่ 1 ms) ต้องยังติดคูลดาวน์",
        )
    }

    /**
     * เคส 3ข: ขอบพอดี — `now - lastPosted == LONG_COOLDOWN_MILLIS` พอดี → ต้อง
     * ยิงได้ เพราะเงื่อนไขในโค้ดจริงเป็น `since < LONG_COOLDOWN_MILLIS` (ไม่ใช่ `<=`)
     */
    @Test
    fun longCooldownAllowsExactlyAtWindowBoundary() {
        val lastPosted = 1L // ไม่ใช่ 0L ด้วยเหตุผลเดียวกับเคสข้างบน
        val now = lastPosted + ExampleProximityWatcher.LONG_COOLDOWN_MILLIS

        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = now,
        )

        assertEquals(null, result, "since == LONG_COOLDOWN_MILLIS พอดีต้องยิงได้ เพราะเงื่อนไขเป็น <")
    }

    /** เคส 3ค: เกินขอบไปแล้ว 1 มิลลิวินาที → ต้องยิงได้เช่นกัน */
    @Test
    fun longCooldownAllowsOneMillisecondAfterWindowElapses() {
        val lastPosted = 1L // ไม่ใช่ 0L ด้วยเหตุผลเดียวกับสองเคสข้างบน
        val now = lastPosted + ExampleProximityWatcher.LONG_COOLDOWN_MILLIS + 1

        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = now,
        )

        assertEquals(null, result, "เกิน 30 นาทีไปแล้วต้องยิงได้")
    }

    /**
     * เคส 4ก: `longCooldownKeyFor()` ต้องได้คีย์ต่างกันเมื่อ event ต่างกันแม้แค่
     * ฟิลด์เดียว (region / uuid / major / minor) — ทดสอบทีละฟิลด์
     */
    @Test
    fun longCooldownKeyDiffersWhenAnySingleFieldDiffers() {
        val base = event(major = 9902, minor = 2, regionIdentifier = "bigc-test", uuid = "7777772e-6b6b-6d63-6e2e-636f6d000001")
        val diffRegion = event(major = 9902, minor = 2, regionIdentifier = "bigc-other", uuid = "7777772e-6b6b-6d63-6e2e-636f6d000001")
        val diffUuid = event(major = 9902, minor = 2, regionIdentifier = "bigc-test", uuid = "aaaaaaaa-6b6b-6d63-6e2e-636f6d000001")
        val diffMajor = event(major = 9903, minor = 2, regionIdentifier = "bigc-test", uuid = "7777772e-6b6b-6d63-6e2e-636f6d000001")
        val diffMinor = event(major = 9902, minor = 3, regionIdentifier = "bigc-test", uuid = "7777772e-6b6b-6d63-6e2e-636f6d000001")

        val baseKey = ExampleProximityWatcher.longCooldownKeyFor(base)

        assertTrue(baseKey != ExampleProximityWatcher.longCooldownKeyFor(diffRegion), "region ต่างกันต้องได้คีย์ต่างกัน")
        assertTrue(baseKey != ExampleProximityWatcher.longCooldownKeyFor(diffUuid), "uuid ต่างกันต้องได้คีย์ต่างกัน")
        assertTrue(baseKey != ExampleProximityWatcher.longCooldownKeyFor(diffMajor), "major ต่างกันต้องได้คีย์ต่างกัน")
        assertTrue(baseKey != ExampleProximityWatcher.longCooldownKeyFor(diffMinor), "minor ต่างกันต้องได้คีย์ต่างกัน")
    }

    /**
     * เคส 4ข: รูปร่างของคีย์ต้องเป็น `region|uuid|major|minor` โดย `uuid` เป็น
     * ตัวพิมพ์เล็กเสมอ — ต้องตรงกับ `proximityKeyFor()` ใน `BeaconScanReceiver.kt`
     * (`"$regionIdentifier|${uuid.lowercase()}|$major|$minor"`) เพราะนี่คือหัวใจ
     * ของ ADR-25 §2: ถ้ารูปร่างไม่ตรงกับ key ของ gate จะกันสแปมจากการล้าง state
     * ไม่ได้ตรงจุด
     */
    @Test
    fun longCooldownKeyShapeMatchesProximityGateKeyFormat() {
        val upperUuid = event(
            major = 9902,
            minor = 2,
            regionIdentifier = "bigc-test",
            uuid = "7777772E-6B6B-6D63-6E2E-636F6D000001", // ตัวพิมพ์ใหญ่โดยตั้งใจ
        )

        val key = ExampleProximityWatcher.longCooldownKeyFor(upperUuid)

        assertEquals(
            "bigc-test|7777772e-6b6b-6d63-6e2e-636f6d000001|9902|2",
            key,
            "ต้องเป็น region|uuid(lowercase)|major|minor ตรงกับ proximityKeyFor() ของ BeaconScanReceiver.kt",
        )
    }

    /** เคส 4ค: ฟิลด์ที่เป็น `null` (uuid/major/minor) ต้องแทนด้วย `-` ไม่ใช่ปล่อยว่างหรือ `"null"` */
    @Test
    fun longCooldownKeyUsesDashForNullFields() {
        val allMissing = event(major = null, minor = null, regionIdentifier = "bigc-test", uuid = null)

        val key = ExampleProximityWatcher.longCooldownKeyFor(allMissing)

        assertEquals("bigc-test|-|-|-", key, "ฟิลด์ที่หายต้องเป็น - ไม่ใช่ null หรือช่องว่าง")
    }

    /**
     * เคส 5: cooldown รอดข้ามการ "สร้าง process ใหม่" — **ทดสอบได้แค่บางส่วน**
     * pure function นี้ไม่แตะ `SharedPreferences` เลย จึงพิสูจน์ได้เพียงว่า
     * "ถ้าค่าที่ persist ไว้ (สมมติว่าอ่านคืนมาได้ถูกต้องจาก prefs) ถูกส่งเข้ามา
     * เป็นพารามิเตอร์ มันยังทำให้ติดคูลดาวน์เหมือนเดิม" — **ไม่ได้พิสูจน์ว่า
     * `SharedPreferences.commit()`/การอ่านค่าคืนจริงหลัง process ถูกฆ่าทำงานถูกต้อง**
     * ส่วนนั้นเป็น I/O ที่ยืนยันได้เฉพาะบนอุปกรณ์จริงเท่านั้น (ดู
     * `docs/test-checklists/android_background_scanning.md`)
     */
    @Test
    fun longCooldownStillBlocksWhenPersistedValueIsPassedInAfterSimulatedRestart() {
        // จำลอง "process เดิมโพสต์สำเร็จแล้วจด elapsedRealtime ไว้ที่ 100_000L
        // ก่อนถูกฆ่า — process ใหม่อ่านค่านี้กลับมาได้จาก SharedPreferences" ซึ่ง
        // ส่วนการอ่าน/เขียนจริงไม่ได้ถูกทดสอบที่นี่ มีแค่ผลลัพธ์ของค่านั้นเท่านั้น
        val valueAsIfReadBackFromPrefsAfterProcessRestart = 100_000L
        val nowAfterRestart = valueAsIfReadBackFromPrefsAfterProcessRestart + 60_000L // 1 นาทีถัดมา

        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = valueAsIfReadBackFromPrefsAfterProcessRestart,
            nowElapsedMillis = nowAfterRestart,
        )

        assertEquals(60_000L, result, "ค่าที่ persist ไว้ (จำลองว่าอ่านคืนมาได้) ต้องยังทำให้ติดคูลดาวน์")
    }

    /**
     * เคส 6: ค่าที่เก็บไว้มากกว่าเวลาปัจจุบัน (เครื่อง reboot ทำให้
     * `elapsedRealtime` รีเซ็ตกลับไปนับจาก 0) → ต้องยิงได้ ตามที่โจทย์กำหนดตรง ๆ
     * ว่า "ถือว่าไม่อยู่ใน cooldown"
     */
    @Test
    fun longCooldownAllowsWhenStoredValueIsAheadOfNowDueToReboot() {
        val storedBeforeReboot = 10_000_000L
        val nowAfterReboot = 500L // เครื่อง reboot แล้ว elapsedRealtime นับใหม่จาก 0

        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = storedBeforeReboot,
            nowElapsedMillis = nowAfterReboot,
        )

        assertEquals(null, result, "ค่าที่เก็บไว้มากกว่าปัจจุบันแปลว่า reboot แล้ว ต้องยิงได้")
    }

    /**
     * เคส 7 — เคสหลักของ ADR-20 §12.6: "stale แล้ว near ใหม่ภายในคูลดาวน์ →
     * ไม่ยิง" **สิ่งที่เทสต์นี้พิสูจน์ได้จริง:** เวลาที่จดไว้ (`lastPostedElapsedMillisOrZero`)
     * เป็นพารามิเตอร์ตัวเลขล้วน ๆ ที่ฟังก์ชันนี้ไม่มีทางรู้ได้เลยว่ามันมาจาก
     * transition ชนิดไหน (`closer`/`farther`/`stale`/`reconcile`/...) ผลลัพธ์จึง
     * ขึ้นกับ **เวลาที่ผ่านไปเท่านั้น** ไม่ขึ้นกับว่า state ของ `ProximityGate`
     * ถูกล้างไปก่อนหน้านั้นหรือไม่ — ทดสอบด้วยการยืนยันว่าเวลาที่ผ่านมาเท่ากัน
     * ให้ผลเหมือนกันไม่ว่า `reason` ของ event ปัจจุบันจะเป็นอะไร (ฟังก์ชันนี้ไม่
     * รับ `reason`/`event` เป็นพารามิเตอร์เลยด้วยซ้ำ — พิสูจน์เชิงลายเซ็นของ
     * ฟังก์ชัน ไม่ใช่แค่ผลการรัน)
     *
     * ⚠️ **ข้ออ้าง "stale ไม่ล้างคูลดาวน์นี้" ไม่ได้ถูกยืนยันโดยเทสต์นี้ (หรือเทสต์
     * ใดในไฟล์นี้)** — มันเป็นข้อสรุปเชิงโครงสร้างจากการที่คูลดาวน์ 30 นาทีนี้เก็บ
     * อยู่ใน `SharedPreferences` ไฟล์ `notification_cooldown_v1` ซึ่งเป็นไฟล์คนละ
     * ไฟล์จาก `ProximityGateStore` (`beacon_kit_android.proximity`) ที่เส้นทาง
     * `stale`/`sweepStale()` แก้ไข — ไม่มีโค้ดจุดใดใน `ExampleProximityWatcher.kt`
     * เรียก `.clear()`/`clearRegion()` ของไฟล์ `notification_cooldown_v1` เลย
     * (อ่านจากซอร์สโดยตรง ไม่ได้พิสูจน์ด้วยการรันเทสต์) ยืนยันเชิง behavior เต็ม
     * รูปแบบว่า "stale ล้าง state ของ gate แล้ว near ใหม่ยังไม่ยิงจริง" ทำได้แค่
     * บนอุปกรณ์จริงเท่านั้น (ต้องมี `BackgroundProximityMonitor`/`BeaconScanReceiver`
     * ทำงานจริงเพื่อสร้างลำดับ transition นั้น)
     */
    @Test
    fun longCooldownTimingIsIndependentOfTransitionReason() {
        val lastPosted = 1_000_000L
        val elapsed = 10 * 60 * 1_000L // 10 นาที — ยังอยู่ในคูลดาวน์
        val now = lastPosted + elapsed

        // ฟังก์ชันนี้ไม่รับ ProximityChangedEvent/reason เลย — ยืนยันว่าผลลัพธ์
        // ขึ้นกับเวลาที่ผ่านไปเท่านั้น เรียกซ้ำด้วยพารามิเตอร์เวลาเดียวกันต้องได้
        // ผลเดียวกันเสมอไม่ว่า caller จะอยู่ในเส้นทางไหน (stale/reconcile/นาฬิกาปลุก/
        // การเดินข้ามขอบจริง — ทั้งหมดเรียกฟังก์ชันเดียวกันด้วยพารามิเตอร์เดียวกัน)
        val resultA = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(lastPosted, now)
        val resultB = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(lastPosted, now)

        assertEquals(elapsed, resultA)
        assertEquals(resultA, resultB, "เวลาที่ผ่านไปเท่ากันต้องได้ผลเดียวกันเสมอ ไม่ขึ้นกับ transition ใด ๆ")
    }
}

/*
 * ## หนี้ที่ยังไม่ได้ทดสอบในไฟล์นี้ (บันทึกโดย beacon-qa, 11 ก.ย. 2026)
 *
 * ข้อ 5 ของโจทย์ ADR-20 ขั้นทดสอบต้องการยืนยันสามเรื่องที่**ต้องการ `Context` จริง
 * หรือ mock**:
 * 1. บีคอนสองตัวในเวลาใกล้กัน → 2 notification จริง (ไม่ถูกคูลดาวน์กลืนเป็นใบเดียว)
 * 2. บีคอนตัวเดิมซ้ำภายใน 60 วินาที → ยังคูลดาวน์เหมือนเดิม 1 ใบ
 * 3. บรรทัด log (`event=proximity`) เขียนทุกครั้งแม้ notification ติดคูลดาวน์
 *
 * ทั้งสามข้อทดสอบไม่ได้ที่นี่เพราะ `consumeCooldown()`/`onProximityChanged()`
 * (private) ต้องมี `android.content.Context` จริงเพื่อเปิด `SharedPreferences`
 * (คูลดาวน์) และเขียนไฟล์ผ่าน `BackgroundEvidenceLog.append()` (`context.filesDir`)
 * — โมดูล `beacon_kit_android` มี `mockito-core` + `FakeSharedPreferences` ให้ mock
 * `Context` ได้แล้ว (ดู `ProximityGateStoreTest.kt`) แต่โมดูล `app` **ไม่มี**
 * `mockito-core` เป็น dependency เลย (ดู `packages/beacon_kit/example/android/app/
 * build.gradle.kts`) และ QA agent ไม่มีสิทธิ์แก้ไฟล์ build/dependency เพื่อเพิ่มเอง
 * ในรอบนี้ (ขอบเขตงานระบุห้ามไว้ตรง ๆ)
 *
 * **ทางแก้ที่แนะนำ (ให้ flutter-dev ตัดสินใจ ไม่ใช่ QA แก้เอง):**
 * (ก) เพิ่ม `testImplementation("org.mockito:mockito-core:5.0.0")` ใน
 *     `app/build.gradle.kts` ให้เหมือน `beacon_kit_android/build.gradle.kts` แล้ว
 *     เขียน `FakeSharedPreferences`/mock `Context` แบบเดียวกับที่นั่น หรือ
 * (ข) แยกตรรกะการตัดสินใจของคูลดาวน์ (เทียบเวลา/สร้าง key) ออกจาก I/O ของ
 *     `SharedPreferences` เป็น pure function ที่รับ "เวลาที่ยิงล่าสุดของ key นี้"
 *     เป็นพารามิเตอร์ตรง ๆ (แพทเทิร์นเดียวกับที่ `ProximityGate` แยกออกจาก
 *     `ProximityGateStore`) — จะทำให้ทดสอบตรรกะคูลดาวน์ได้แบบ pure Kotlin ล้วน ๆ
 *     โดยไม่ต้องมี `Context` เลย ซึ่งน่าจะยั่งยืนกว่าทางเลือก (ก) ในระยะยาว
 *
 * ก่อนมีทางแก้ใดทางหนึ่ง พฤติกรรมคูลดาวน์รายบีคอนของ example app ยังอยู่ในสถานะ
 * **code-complete, unverified by unit test** — ยืนยันได้จริงเฉพาะ (1) การอ่านโค้ด
 * (`cooldownKeyFor` ใน `ExampleProximityWatcher.kt` ใช้ `region|major|minor`) และ
 * (2) การทดสอบบนอุปกรณ์จริงเท่านั้น
 */
