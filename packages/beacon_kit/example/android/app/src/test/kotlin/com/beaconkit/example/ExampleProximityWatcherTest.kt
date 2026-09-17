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
    //
    // ⚠️ **แก้ 17 ก.ย. 2026 (ADR-25 §8/§8.4.1, commit 8b20433) — ถอนข้ออ้างข้างบน
    // บางส่วน อย่าลบทิ้ง:** `LONG_COOLDOWN_MILLIS` ถูก rename เป็น
    // `DEFAULT_LONG_COOLDOWN_MILLIS` และเปลี่ยนความหมายเป็น **ค่าเริ่มต้นของสินค้า
    // (24 ชม.)** ไม่ใช่ค่าเดียวที่ใช้จริงอีกต่อไป — `install()` รับพารามิเตอร์
    // `longCooldownMillis` ที่ override เป็น 30 นาทีที่จุดประกอบ
    // (`ExampleApplication.kt`, `TESTING_LONG_COOLDOWN_MILLIS`, **private** เข้าถึง
    // จากไฟล์นี้ไม่ได้) และ `longCooldownSinceLastPostedMillisOrNull` เพิ่ม
    // พารามิเตอร์ที่สาม `cooldownMillis` **ที่ไม่มีค่า default โดยตั้งใจ** (§8.4.1)
    // — ทุกจุดเรียกด้านล่างจึงต้องส่งพารามิเตอร์นี้ตรง ๆ ทุกครั้ง
    //
    // เทสกลุ่มนี้ตั้งใจทดสอบ**หน้าต่าง 30 นาทีที่ example app override จริง** (ไม่ใช่
    // ค่าสินค้า 24 ชม.) แต่ไม่มีสัญลักษณ์สาธารณะให้อ้างค่านั้นตรง ๆ
    // (`TESTING_LONG_COOLDOWN_MILLIS` เป็น private ของ `ExampleApplication` — ต่างจาก
    // ฝั่ง iOS ที่ `testingLongCooldownSeconds` เป็น `internal` เข้าถึงได้ผ่าน
    // `@testable import`) จึง copy ค่าไว้เองเป็น [TEST_LONG_COOLDOWN_MILLIS] ด้านล่าง
    // แทนการอ้าง `DEFAULT_LONG_COOLDOWN_MILLIS` ตรง ๆ — ถ้าอ้าง
    // `DEFAULT_LONG_COOLDOWN_MILLIS` แทน เทสกลุ่มนี้จะเขียวผิดที่ (ทดสอบหน้าต่าง
    // 24 ชม. แทน 30 นาทีโดยไม่มีอะไรฟ้อง ตามที่ §8.9 เตือนไว้)
    //
    // เพิ่มโดย beacon-qa, 17 ก.ย. 2026: สามเทสใหม่ท้ายกลุ่มนี้ (ค่าเริ่มต้นสินค้า
    // 24 ชม., pure function ใช้ค่าที่ส่งเข้ามาจริงไม่ใช่ค่าคงที่เดิม, ขอบเลื่อนตาม
    // ค่าที่ไม่ใช่ 30 นาที) ตามเกณฑ์ §8.8
    // ------------------------------------------------------------------

    companion object {
        /**
         * ค่าคูลดาวน์ที่กลุ่มเทสนี้ตั้งใจพิสูจน์ขอบเขต — **ตรงกับค่าที่ example app
         * override จริง** (`TESTING_LONG_COOLDOWN_MILLIS`, `ExampleApplication.kt`,
         * 30 นาที, ADR-25 §8.3) แต่ต้อง copy ไว้เองที่นี่เพราะสัญลักษณ์นั้นเป็น
         * `private const val` ของคลาสอื่น เข้าถึงจากไฟล์เทสนี้ไม่ได้ (ดูหมายเหตุ
         * ท้ายไฟล์นี้ — รายงานเป็นข้อจำกัดของ access level ให้ flutter-dev ตัดสินใจ
         * ไม่ใช่ QA เปิด access เอง) **ห้ามสับสนกับ [ExampleProximityWatcher
         * .DEFAULT_LONG_COOLDOWN_MILLIS]** ซึ่งเป็นค่าสินค้า 24 ชม. — คนละค่ากันโดย
         * ตั้งใจ
         */
        private const val TEST_LONG_COOLDOWN_MILLIS = 30 * 60 * 1_000L
    }

    /** เคส 1: ไม่เคยโพสต์คีย์นี้สำเร็จมาก่อน (`0L`) → ต้องยิงได้ (`null`) */
    @Test
    fun longCooldownAllowsFirstEverPostForKey() {
        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = 0L,
            nowElapsedMillis = 1_000_000L,
            cooldownMillis = TEST_LONG_COOLDOWN_MILLIS,
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
            cooldownMillis = TEST_LONG_COOLDOWN_MILLIS,
        )

        assertEquals(
            elapsedSinceLastPost,
            result,
            "ค่าที่คืนต้องเท่ากับ now - lastPosted เป๊ะ ไม่ใช่แค่ non-null",
        )
    }

    /**
     * เคส 3ก: ขอบล่าง — เหลืออีก 1 มิลลิวินาทีจะครบ 30 นาที → ยังติดคูลดาวน์
     * (`TEST_LONG_COOLDOWN_MILLIS - 1` ยังน้อยกว่าเพดาน)
     *
     * ⚠️ **แก้ 17 ก.ย. 2026 (ADR-25 §8.4.1):** เดิมอ้าง `ExampleProximityWatcher
     * .LONG_COOLDOWN_MILLIS` ตรง ๆ — สัญลักษณ์นั้นถูก rename เป็น
     * `DEFAULT_LONG_COOLDOWN_MILLIS` และเปลี่ยนความหมายเป็นค่าสินค้า 24 ชม. ไปแล้ว
     * ถ้าอ้างสัญลักษณ์ใหม่ตรง ๆ ต่อไปเทสนี้จะเขียวผิดที่ (ทดสอบขอบ 24 ชม. แทน
     * 30 นาที) จึงเปลี่ยนไปใช้ [TEST_LONG_COOLDOWN_MILLIS] ที่นิยามไว้ต้นกลุ่มเทส
     * แทน และส่งเป็นอาร์กิวเมนต์ที่สามของฟังก์ชันตรง ๆ (พารามิเตอร์ใหม่ ไม่มี
     * ค่า default โดยตั้งใจ)
     */
    @Test
    fun longCooldownStillBlocksOneMillisecondBeforeWindowElapses() {
        // lastPosted ต้องไม่เป็น 0L — 0L คือ sentinel ของ "ไม่เคยโพสต์มาก่อน"
        // (เข้าเงื่อนไขแรกของฟังก์ชันแล้วคืน null ทันทีโดยไม่ทดสอบขอบเวลาเลย)
        val lastPosted = 1L
        val now = lastPosted + TEST_LONG_COOLDOWN_MILLIS - 1

        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = now,
            cooldownMillis = TEST_LONG_COOLDOWN_MILLIS,
        )

        assertEquals(
            TEST_LONG_COOLDOWN_MILLIS - 1,
            result,
            "ยังไม่ครบ 30 นาที (ขาดอยู่ 1 ms) ต้องยังติดคูลดาวน์",
        )
    }

    /**
     * เคส 3ข: ขอบพอดี — `now - lastPosted == TEST_LONG_COOLDOWN_MILLIS` พอดี →
     * ต้องยิงได้ เพราะเงื่อนไขในโค้ดจริงเป็น `since < cooldownMillis` (ไม่ใช่ `<=`)
     *
     * ⚠️ แก้ 17 ก.ย. 2026 (ADR-25 §8.4.1) — เหตุผลเดียวกับเคส 3ก ข้างบน
     */
    @Test
    fun longCooldownAllowsExactlyAtWindowBoundary() {
        val lastPosted = 1L // ไม่ใช่ 0L ด้วยเหตุผลเดียวกับเคสข้างบน
        val now = lastPosted + TEST_LONG_COOLDOWN_MILLIS

        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = now,
            cooldownMillis = TEST_LONG_COOLDOWN_MILLIS,
        )

        assertEquals(null, result, "since == cooldownMillis พอดีต้องยิงได้ เพราะเงื่อนไขเป็น <")
    }

    /**
     * เคส 3ค: เกินขอบไปแล้ว 1 มิลลิวินาที → ต้องยิงได้เช่นกัน
     *
     * ⚠️ แก้ 17 ก.ย. 2026 (ADR-25 §8.4.1) — เหตุผลเดียวกับเคส 3ก/3ข ข้างบน
     */
    @Test
    fun longCooldownAllowsOneMillisecondAfterWindowElapses() {
        val lastPosted = 1L // ไม่ใช่ 0L ด้วยเหตุผลเดียวกับสองเคสข้างบน
        val now = lastPosted + TEST_LONG_COOLDOWN_MILLIS + 1

        val result = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = now,
            cooldownMillis = TEST_LONG_COOLDOWN_MILLIS,
        )

        assertEquals(null, result, "เกิน 30 นาทีไปแล้วต้องยิงได้")
    }

    /**
     * เคส 3ง (เพิ่มโดย beacon-qa, 17 ก.ย. 2026, ADR-25 §8.8) — **ขอบของหน้าต่าง
     * ต้องเลื่อนตามค่า `cooldownMillis` ที่ส่งเข้าไปจริง ไม่ใช่ค่าคงที่ที่ผูกตายตัว**
     * ใช้ค่าที่ **ไม่ใช่ 30 นาที** (45 นาที) โดยตั้งใจ เพื่อพิสูจน์ว่าพฤติกรรมของ
     * ฟังก์ชันไม่ได้ผูกกับตัวเลข 30 นาทีเป็นการเฉพาะ (ถ้ามีใคร hardcode ตัวเลข
     * 30 นาทีกลับเข้าไปในฟังก์ชันแทนการใช้พารามิเตอร์ เทสนี้จะแดงทันที ในขณะที่เทส
     * 3ก/3ข/3ค ที่ใช้ 30 นาทีอาจยังบังเอิญเขียวอยู่)
     */
    @Test
    fun longCooldownBoundaryShiftsWithProvidedCooldownMillisNotThirtyMinutes() {
        val differentCooldownMillis = 45 * 60 * 1_000L // 45 นาที — ไม่ใช่ 30 นาที
        val lastPosted = 1L

        val justBeforeBoundary = lastPosted + differentCooldownMillis - 1
        val stillBlocked = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = justBeforeBoundary,
            cooldownMillis = differentCooldownMillis,
        )
        assertEquals(
            differentCooldownMillis - 1,
            stillBlocked,
            "ยังไม่ครบ 45 นาที (ขาดอยู่ 1 ms) ต้องยังติดคูลดาวน์ — ตามค่าที่ส่งเข้ามา ไม่ใช่ 30 นาที",
        )

        val exactBoundary = lastPosted + differentCooldownMillis
        val allowedAtBoundary = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = exactBoundary,
            cooldownMillis = differentCooldownMillis,
        )
        assertEquals(
            null,
            allowedAtBoundary,
            "since == cooldownMillis (45 นาที) พอดีต้องยิงได้ เพราะเงื่อนไขเป็น < ไม่ใช่ <= " +
                "ไม่ว่าค่าที่ส่งเข้ามาจะเป็น 30 นาทีหรือไม่ก็ตาม",
        )
    }

    /**
     * เพิ่มโดย beacon-qa, 17 ก.ย. 2026 (ADR-25 §8.8, ข้อแรก) — **ค่าเริ่มต้นของ
     * สินค้า (product default) ต้องเป็น 24 ชั่วโมงจริง** ยืนยันค่าคงที่ตรง ๆ เป็น
     * มิลลิวินาที (`86_400_000L`) เพื่อกันคนเผลอแก้ค่านี้โดยไม่ตั้งใจ — เทสนี้**ไม่
     * ทดสอบ `install()`** (ต้องมี `Context` จริง ทดสอบไม่ได้ในไฟล์นี้ ดูหมายเหตุ
     * ท้ายไฟล์) แต่ยืนยันแหล่งความจริงเดียวที่ `install()` อ้างอิงเป็นค่า default
     * ของพารามิเตอร์
     */
    @Test
    fun defaultLongCooldownMillisIsProductDefaultTwentyFourHours() {
        assertEquals(
            86_400_000L,
            ExampleProximityWatcher.DEFAULT_LONG_COOLDOWN_MILLIS,
            "ค่าเริ่มต้นของสินค้าต้องเป็น 24 ชั่วโมง (24*60*60*1000 ms) ตาม ADR-25 §8.1",
        )
    }

    /**
     * เพิ่มโดย beacon-qa, 17 ก.ย. 2026 (ADR-25 §9.7, รอบสอง — หลัง `flutter-dev`
     * เปิด `LAYER1_NOTIFICATIONS_ENABLED` จาก `private` เป็น `internal const val`
     * ใน `ExampleApplication.kt:47`, precedent เดียวกับ `6e3470d` ฝั่ง iOS)
     *
     * ⚠️ **เทสนี้กันอะไร — อ่านให้ชัดก่อนเชื่อว่าเทสนี้ "ครอบคลุม" ADR-25 §9 ทั้งข้อ:**
     * เทสนี้**กันคนเผลอ merge สาขาที่เปิด flag ไว้ตอน debug** (เช่นเปิดชั่วคราวเพื่อ
     * เทสต์ notification บนโต๊ะแล้วลืมปิดก่อนส่ง PR) เท่านั้น — **ไม่ใช่การพิสูจน์ว่า
     * บรรทัดหลักฐาน `event=notification ... reason=disabled` ถูกเขียนจริงตอน flag
     * ปิด** ส่วนนั้นต้องมี `Context`/`Application` จริงเพื่อรัน closure ใน
     * `ExampleApplication.onCreate()` ซึ่งยืนยันไม่ได้ด้วย unit test ในไฟล์นี้ (ดู
     * หมายเหตุท้ายไฟล์ — ต้องยืนยันบนอุปกรณ์จริงเท่านั้น)
     */
    @Test
    fun layer1NotificationsFlagIsDisabledByDefault() {
        assertEquals(
            false,
            ExampleApplication.LAYER1_NOTIFICATIONS_ENABLED,
            "flag ชั้น 1 ต้องปิดเป็นค่าเริ่มต้น (ADR-25 §9) — ถ้าแดง แปลว่ามีคน merge " +
                "สาขาที่เปิด flag ไว้ตอน debug",
        )
    }

    /**
     * เพิ่มโดย beacon-qa, 17 ก.ย. 2026 (ADR-25 §8.8, ข้อสอง — **เคสสำคัญที่สุดของ
     * รอบนี้**) — **pure function ต้องใช้ค่า `cooldownMillis` ที่ส่งเข้ามาจริง
     * ไม่ใช่ค่าคงที่เดิมที่แฝงอยู่ในฟังก์ชัน** ส่งค่าคูลดาวน์เล็ก ๆ (1,000 ms — ต่าง
     * จากทั้งค่าสินค้า 24 ชม. และค่าทดสอบ 30 นาทีอย่างชัดเจน) แล้วยืนยันว่าขอบของ
     * หน้าต่างขยับตามค่านั้นจริง — **ถ้าใครเผลอ hardcode ค่าเดิม (30 นาทีหรือ 24
     * ชม.) กลับเข้าไปในฟังก์ชันแทนการอ่านพารามิเตอร์ `cooldownMillis` เทสนี้ต้องแดง
     * ทันที** เพราะ 1,000 ms เล็กกว่าทั้งสองค่านั้นมหาศาล
     */
    @Test
    fun longCooldownSinceLastPostedUsesProvidedCooldownMillisNotHardcodedConstant() {
        val tinyCooldownMillis = 1_000L
        val lastPosted = 1L

        // ยังไม่ครบ 1,000 ms (เหลืออีก 1 ms) — ต้องยังติดคูลดาวน์
        val stillBlocked = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = lastPosted + tinyCooldownMillis - 1,
            cooldownMillis = tinyCooldownMillis,
        )
        assertEquals(
            tinyCooldownMillis - 1,
            stillBlocked,
            "ต้องยังติดคูลดาวน์ตามค่าเล็ก ๆ ที่ส่งเข้ามา (1000ms) ไม่ใช่ค่าคงที่เดิม (30 นาที/24 ชม.)",
        )

        // เกิน 1,000 ms ไปแล้วเยอะมาก (5 วินาที) — ถ้าฟังก์ชัน hardcode ค่าเดิมไว้
        // (30 นาที = 1,800,000 ms) ผลตรงนี้จะยังเป็นคูลดาวน์อยู่ (ผิด) เพราะ 5
        // วินาทียังไม่ครบ 30 นาที — เทสนี้จึงแดงทันทีถ้ามีคนเผลอ hardcode กลับเข้าไป
        val allowedAfterTinyWindow = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = lastPosted,
            nowElapsedMillis = lastPosted + 5_000L,
            cooldownMillis = tinyCooldownMillis,
        )
        assertEquals(
            null,
            allowedAfterTinyWindow,
            "เกินคูลดาวน์เล็ก ๆ (1000ms) ที่ส่งเข้ามาไปนานแล้วต้องยิงได้ — ถ้าแดง แปลว่าฟังก์ชันใช้ " +
                "ค่าคงที่เดิมแทนพารามิเตอร์ที่ส่งเข้ามาจริง",
        )
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
            cooldownMillis = TEST_LONG_COOLDOWN_MILLIS,
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
            cooldownMillis = TEST_LONG_COOLDOWN_MILLIS,
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
        val resultA = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPosted,
            now,
            TEST_LONG_COOLDOWN_MILLIS,
        )
        val resultB = ExampleProximityWatcher.longCooldownSinceLastPostedMillisOrNull(
            lastPosted,
            now,
            TEST_LONG_COOLDOWN_MILLIS,
        )

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
 *
 * ## หนี้เพิ่ม (บันทึกโดย beacon-qa, 17 ก.ย. 2026, ADR-25 §8.8/§9.7)
 *
 * ✅ **ข้อ 1 (access level ของ `LAYER1_NOTIFICATIONS_ENABLED`) แก้แล้วรอบสอง (17
 * ก.ย. 2026) โดย `flutter-dev`:** เปลี่ยนจาก `private const val` เป็น
 * `internal const val` ใน `companion object` ของ `ExampleApplication`
 * (`ExampleApplication.kt:47`) — precedent เดียวกับที่ `6e3470d` เคยเปิด
 * `proximityCooldownKey(for:)`/`proximityLongNotificationCooldownSeconds` ฝั่ง
 * iOS จาก `private` เป็น `internal` — **ไม่แตะค่า/ชื่อ/ตรรกะ** เพิ่มแค่ access
 * modifier เทสยืนยันค่า default (`layer1NotificationsFlagIsDisabledByDefault`,
 * ต้นไฟล์นี้) เพิ่มแล้ว **แต่เทสนั้นกันแค่ "flag เปิดเผลอหลุดไป prod" เท่านั้น** —
 * ไม่ได้ปิดหนี้ข้อ 2 ข้างล่างซึ่งยังอยู่เหมือนเดิม
 *
 * ⚠️ **ข้อ 2 (พิสูจน์ว่าบรรทัดหลักฐาน `reason=disabled` ถูกเขียนจริงตอน flag ปิด)
 * ยังทำไม่ได้เหมือนเดิม** แม้ access level เปิดแล้ว เพราะตรรกะแยกสาขาเปิด/ปิด
 * (`ExampleApplication.kt:90-121`) อยู่ใน closure ของ
 * `BackgroundRegionMonitor.setRegionStateObserver` ภายใน `onCreate()` ซึ่งต้องมี
 * `Context`/`Application` จริงเพื่อรัน — เหตุผลเดียวกับหนี้ข้อ 5 ของ ADR-20 ที่
 * บันทึกไว้ข้างบนทั้งหมด (โมดูล `app` ไม่มี mockito/Robolectric) **ต้องยืนยันบน
 * อุปกรณ์จริงเท่านั้นในสถานะปัจจุบัน** (ดู
 * `docs/test-checklists/android_background_scanning.md`)
 *
 * ## หนี้ที่สาม (บันทึกโดย beacon-qa, 17 ก.ย. 2026, ADR-25 §8.8 ข้อสอง — เทียบเท่า
 * ฝั่ง Android ของเทส iOS `testNewAppDelegateInstanceDefaultsToProductCooldownNotTestingCooldown`)
 *
 * ฝั่ง iOS มีเทสยืนยันว่า instance ที่เพิ่งสร้าง (`AppDelegate()`) มี
 * `longCooldownSeconds` เริ่มต้นเป็นค่าสินค้าได้ เพราะ `AppDelegate` สร้าง instance
 * เปล่าได้ตรง ๆ โดยไม่ต้องมี `UIApplication`/engine จริง — **ฝั่ง Android ไม่มี
 * อะไรเทียบเท่าที่ทดสอบได้แบบเดียวกัน**: `ExampleProximityWatcher` เป็น Kotlin
 * `object` (singleton, ไม่มี constructor ให้เรียก, ดู §8.3) ค่าที่ "ใช้งานจริง ณ
 * runtime" (`longCooldownMillis`, `ExampleProximityWatcher.kt:57`) เป็น
 * `private var` ที่ตั้งค่าได้ทางเดียวคือผ่าน `install(context: Context, ...)`
 * เท่านั้น — ไม่มีทาง "สร้าง instance เปล่าแล้วอ่านค่า default" แบบ iOS ได้เลย
 * เพราะไม่มี instance ให้สร้าง (เป็น `object` ตัวเดียวทั้งโปรเซส) และการเรียก
 * `install()` เพื่อดูผลของค่า default ต้องมี `Context` จริง (แม้ `install()` จะ
 * ไม่ได้เรียกเมธอดของ `Context` มากไปกว่า `.applicationContext` แต่ `Context` เป็น
 * `abstract class` ที่มีเมธอด abstract หลายสิบตัว การเขียน stub มือโดยไม่มี
 * mockito/Robolectric ไม่คุ้มและเสี่ยง stub ผิดจนเทสให้ความมั่นใจปลอม) —
 * **รายงานว่าคลุมไม่ได้ ไม่ฝืนเขียน** ความไม่สมมาตรนี้เป็นผลจากดีไซน์ `object` vs
 * `class` ของสองแพลตฟอร์ม (§8.3 เทียบกับ §8.4) ไม่ใช่ช่องโหว่ที่ตั้งใจเปิดไว้ —
 * เทสที่ใกล้เคียงที่สุดที่ทำได้ในไฟล์นี้คือ
 * `defaultLongCooldownMillisIsProductDefaultTwentyFourHours` (ยืนยันแค่ค่าคงที่
 * `DEFAULT_LONG_COOLDOWN_MILLIS` เอง ไม่ใช่ผลของการเรียก `install()` โดยไม่ระบุ
 * พารามิเตอร์) — ยังต้องยืนยันว่า `install()` ใช้ default นี้จริงบนอุปกรณ์จริง
 * เท่านั้น (ดู `docs/test-checklists/android_background_scanning.md`)
 */
