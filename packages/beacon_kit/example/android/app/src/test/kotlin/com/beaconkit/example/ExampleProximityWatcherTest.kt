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
}
