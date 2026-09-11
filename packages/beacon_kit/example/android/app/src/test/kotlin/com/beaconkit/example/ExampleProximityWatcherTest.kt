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
    ) = ProximityChangedEvent(
        regionIdentifier = "bigc-test",
        uuid = "7777772e-6b6b-6d63-6e2e-636f6d000001",
        major = major,
        minor = minor,
        from = ProximityBucket.FAR,
        to = ProximityBucket.NEAR,
        reason = ProximityTransitionReason.CLOSER,
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
