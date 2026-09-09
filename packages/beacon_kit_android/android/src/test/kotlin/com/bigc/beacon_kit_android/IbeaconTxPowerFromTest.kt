package com.bigc.beacon_kit_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * เทสต์ `ibeaconTxPowerFrom()` — pure function ที่อ่าน `txPower` จาก
 * manufacturer-specific data ของ iBeacon (ADR-20 หัวข้อ 1)
 *
 * ## ทำไมฟังก์ชันตัวเล็ก ๆ นี้ต้องมีเทสต์ของตัวเอง
 *
 * เป็นจุดที่ **พังเงียบที่สุด** ของเส้นทาง proximity ฝั่ง Android: อ่าน index ผิด
 * หรืออ่านเป็น unsigned แล้วผลที่ออกมาไม่ใช่ error แต่เป็น "ระยะที่เพี้ยนเป็น
 * หลักพันเมตร" ซึ่งไหลต่อเข้า `ProximityGate` ได้ตามปกติทุกขั้น ไม่มีอะไรฟ้อง —
 * อาการปลายทางคือ "gate ไม่เคยบอกว่าใกล้เลย" ซึ่งแยกไม่ออกจาก "ไม่มีบีคอนอยู่จริง"
 *
 * ## ข้อมูลนำเข้าอ้างอิงจาก fixture ที่มีอยู่แล้ว ไม่ได้แต่งเลขใหม่
 *
 * ไบต์ในเทสต์นี้มาจาก `docs/fixtures/ibeacon_valid_basic.json`
 * (`raw_hex = 4c00 0215 e2c5…96e0 0001 0064 c5`, `expect.frame.tx_power = -59`)
 * โดย**ตัด company ID (`4c00`) 2 ไบต์แรกออก** เพราะ
 * `ScanRecord.getManufacturerSpecificData(companyId)` ของ Android ตัดให้แล้วก่อน
 * ส่งถึงโค้ดเรา (ต่างจาก `IBeaconParser.parse()` ฝั่ง Dart ที่รับทั้ง company ID
 * — ดูหัวข้อธรรมเนียม `raw_hex` ใน `docs/fixtures/README.md`) ที่เหลือคือ 23 ไบต์:
 * `02 15 | uuid(16) | major(2) | minor(2) | txPower(1)`
 *
 * prefix ประกอบจาก [BeaconRegionSpec.IBEACON_PREFIX] ตัวจริง **ห้ามเขียนไบต์
 * `02 15` ซ้ำเองในไฟล์นี้** (ADR-20 หัวข้อ 1: วันที่ layout เปลี่ยน ต้องมีจุดแก้
 * จุดเดียว ไม่ใช่จุดที่สองที่ลืมแก้แล้วเทสต์ยังเขียว)
 */
class IbeaconTxPowerFromTest {

    /** uuid(16) + major(2) + minor(2) = 20 ไบต์ที่คั่นระหว่าง prefix กับ txPower */
    private val uuidMajorMinor = byteArrayOf(
        0xE2.toByte(), 0xC5.toByte(), 0x6D, 0xB5.toByte(),
        0xDF.toByte(), 0xFB.toByte(), 0x48, 0xD2.toByte(),
        0xB0.toByte(), 0x60, 0xD0.toByte(), 0xF5.toByte(),
        0xA7.toByte(), 0x10, 0x96.toByte(), 0xE0.toByte(),
        0x00, 0x01, // major = 1
        0x00, 0x64, // minor = 100
    )

    /** payload เต็ม 23 ไบต์ — `txPower` = `0xC5` = -59 ตาม fixture */
    private fun validPayload(txPowerByte: Byte = 0xC5.toByte()): ByteArray =
        BeaconRegionSpec.IBEACON_PREFIX + uuidMajorMinor + byteArrayOf(txPowerByte)

    @Test
    fun `payload ปกติ 23 ไบต์ - txPower ต้องเป็นค่า signed ไม่ใช่ unsigned`() {
        val data = validPayload()
        assertEquals(23, data.size, "layout ของ iBeacon หลังตัด company ID คือ 23 ไบต์")

        val txPower = ibeaconTxPowerFrom(data)

        assertEquals(
            -59,
            txPower,
            "ต้องอ่านเป็น signed — ถ้าได้ 197 (0xC5 แบบ unsigned) สูตรระยะจะพุ่งเป็น " +
                "หลักพันเมตรโดยไม่มีอะไรฟ้อง",
        )
    }

    @Test
    fun `array สั้นกว่า 23 ไบต์ ต้องคืน null ไม่ใช่ค่าเดาหรือ exception`() {
        // ตัดไบต์ txPower ทิ้งไปตัวเดียว — เหลือ 22 ไบต์ (เคส "ขาดพอดีหนึ่งไบต์"
        // ซึ่งอันตรายกว่าเคสสั้นมาก ๆ เพราะ off-by-one จะรอดไปได้ถ้าเช็คผิดเป็น `<`)
        val truncated = validPayload().copyOf(22)

        assertNull(ibeaconTxPowerFrom(truncated))
        assertNull(ibeaconTxPowerFrom(ByteArray(0)), "array ว่างก็ต้องคืน null เงียบ ๆ")
    }

    @Test
    fun `prefix ไม่ใช่ 02 15 ต้องคืน null`() {
        // เหมือน payload ปกติทุกไบต์ ยกเว้นไบต์แรกของ prefix — ตรงกับเคส
        // `docs/fixtures/ibeacon_invalid_prefix.json` (0215 → 0315)
        val wrongPrefix = validPayload().also { it[0] = 0x03 }

        assertNull(
            ibeaconTxPowerFrom(wrongPrefix),
            "ยาวพอและมีไบต์ที่ตำแหน่ง txPower อยู่จริง แต่ไม่ใช่ iBeacon — ห้ามอ่านมั่ว",
        )
    }

    @Test
    fun `null ต้องคืน null`() {
        // เกิดจริงเมื่อ `ScanRecord.getManufacturerSpecificData()` ไม่มีข้อมูลของ
        // company ID นั้นเลย — ProximityGate จะทิ้ง sample และนับ
        // droppedNoTxPowerCount ให้เอง (ADR-19 หัวข้อ 6(จ) ห้าม default ค่า txPower)
        assertNull(ibeaconTxPowerFrom(null))
    }

    @Test
    fun `payload ยาวเกิน 23 ไบต์ ยังต้องอ่านไบต์ที่ตำแหน่งเดิม`() {
        // อุปกรณ์บางรุ่นต่อท้าย byte ที่ไม่อยู่ใน spec มาด้วย — offset ของ txPower
        // ต้องนับจากต้น payload เสมอ ไม่ใช่จากท้าย array
        val padded = validPayload() + byteArrayOf(0x7F, 0x00, 0x11)

        assertEquals(-59, ibeaconTxPowerFrom(padded))
    }
}
