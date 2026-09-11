package com.bigc.beacon_kit_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * เทสต์ `ibeaconIdentityFrom()` — pure function ที่อ่าน major/minor จาก
 * manufacturer-specific data ของ iBeacon (ADR-20 หัวข้อ 1)
 *
 * ## ทำไมต้องใช้ byte fixture ชุดเดียวกับ `ibeacon_parser_test.dart` (ADR-20 หัวข้อ 1(ข))
 *
 * `ibeaconIdentityFrom()` เป็น parser ตัวที่สองของฟิลด์เดียวกันกับที่ `IBeaconParser`
 * (Dart) ทำอยู่แล้ว (ดู kdoc ของฟังก์ชันนี้ใน `BeaconScanReceiver.kt` ว่าทำไมการ
 * เบี่ยงจาก ADR-14 หัวข้อ 4.1 ครั้งนี้ยอมรับได้) — ถ้าเทสต์ทั้งสองฝั่งใช้เลขคนละชุด
 * ที่แต่งขึ้นเองอิสระต่อกัน สองฝั่งจะ drift กันได้โดยไม่มีเทสต์ไหนจับ (เช่น Kotlin
 * อ่าน offset ผิดไปสองไบต์แต่ยังทดสอบผ่านเพราะเทสต์ก็เขียน offset ผิดแบบเดียวกัน)
 *
 * ทุกไบต์ในไฟล์นี้จึงมาจาก `docs/fixtures/ibeacon_valid_major_minor_*.json` ตรง ๆ
 * (คนละไฟล์กับ `IbeaconTxPowerFromTest.kt` ที่ใช้ `ibeacon_valid_basic.json` เพราะ
 * ไฟล์นั้น major=1/minor=100 ไม่ครอบขอบ 0/65535 ที่ต้องการที่นี่) — ค่าที่ต้องมีตาม
 * โจทย์ของ beacon-qa: `9902 = 0x26AE`, `2 = 0x0002`, ขอบ `0` และ `65535`
 *
 * ## ⚠️ offset ต่างจาก Dart 2 ไบต์ — อย่าลอกเลขข้ามภาษา
 *
 * `raw_hex` ของ fixture คือ input ของ `IBeaconParser.parse()` ฝั่ง Dart ซึ่ง**รวม
 * company ID 2 ไบต์แรก** (`4c 00`) — major ของฝั่งนั้นจึงอยู่ที่ index `[20]`/`[21]`
 * ส่วน `ibeaconIdentityFrom()` ฝั่งนี้รับ `ByteArray` ที่
 * `ScanRecord.getManufacturerSpecificData()` **ตัด company ID ออกให้แล้ว**
 * (`ScanFilter.java:618-638`) — byte ที่ป้อนเข้าฟังก์ชันนี้จึงเป็น `raw_hex` ของ
 * fixture **หัก 2 ไบต์แรกออก** เท่านั้น (major ที่นี่จึงอยู่ที่ index `18`/`19`
 * ตรงกับที่ kdoc ของ `ibeaconIdentityFrom()` ระบุไว้: `prefix.size(2) + 16`)
 *
 * layout ที่ป้อนเข้าฟังก์ชันนี้ (23 ไบต์): `02 15 | uuid(16) | major(2) | minor(2) | txPower(1)`
 */
class IbeaconIdentityFromTest {

    /** uuid(16) เดียวกับทุก fixture `ibeacon_valid_major_minor_*` — คงที่ ไม่ใช่ตัวแปรที่ทดสอบ */
    private val uuid = byteArrayOf(
        0xE2.toByte(), 0xC5.toByte(), 0x6D, 0xB5.toByte(),
        0xDF.toByte(), 0xFB.toByte(), 0x48, 0xD2.toByte(),
        0xB0.toByte(), 0x60, 0xD0.toByte(), 0xF5.toByte(),
        0xA7.toByte(), 0x10, 0x96.toByte(), 0xE0.toByte(),
    )

    /** ประกอบ payload 23 ไบต์จาก major/minor — txPower คงที่ `0xC5` (-59) ตามทุก fixture */
    private fun payload(major: ByteArray, minor: ByteArray): ByteArray =
        BeaconRegionSpec.IBEACON_PREFIX + uuid + major + minor + byteArrayOf(0xC5.toByte())

    /**
     * `docs/fixtures/ibeacon_valid_major_minor_9902_2.json` หัก company id (`4c00`)
     * 2 ไบต์แรกออก — `raw_hex` เต็ม: `...96e026ae0002c5` → `26ae`=major(9902) `0002`=minor(2)
     */
    @Test
    fun `9902 slash 2 - ค่าจริงจาก fixture ที่ใช้ร่วมกับ ibeacon_parser_test dart`() {
        val data = payload(
            major = byteArrayOf(0x26, 0xAE.toByte()),
            minor = byteArrayOf(0x00, 0x02),
        )
        assertEquals(23, data.size)

        val identity = ibeaconIdentityFrom(data)

        assertEquals(IBeaconIdentity(major = 9902, minor = 2), identity)
    }

    /**
     * ขอบล่างของ uint16 (`docs/fixtures/ibeacon_valid_major_minor_zero_boundary.json`)
     * — `0x0000` ให้ผลเดียวกันไม่ว่าจะอ่านเป็น signed หรือ unsigned จึงต้องคู่กับเคส
     * ขอบบนด้านล่างเสมอถึงจะครอบพฤติกรรม unsigned ได้จริง
     */
    @Test
    fun `ขอบล่าง 0 - major และ minor เป็น 0 พร้อมกัน`() {
        val data = payload(
            major = byteArrayOf(0x00, 0x00),
            minor = byteArrayOf(0x00, 0x00),
        )

        assertEquals(IBeaconIdentity(major = 0, minor = 0), ibeaconIdentityFrom(data))
    }

    /**
     * ขอบบนของ uint16 (`docs/fixtures/ibeacon_valid_major_minor_max_boundary.json`)
     * — เคสสำคัญที่สุดของขอบเขต: `0xFFFF` อ่านเป็น **signed** จะได้ `-1` ไม่ใช่
     * `65535` ถ้าฟังก์ชันนี้ลืม mask `0xFF` ก่อน shift เทสต์นี้จะจับได้ทันที
     */
    @Test
    fun `ขอบบน 65535 - ต้องเป็น unsigned ไม่ใช่ -1`() {
        val data = payload(
            major = byteArrayOf(0xFF.toByte(), 0xFF.toByte()),
            minor = byteArrayOf(0xFF.toByte(), 0xFF.toByte()),
        )

        val identity = ibeaconIdentityFrom(data)

        assertEquals(65535, identity?.major, "อ่านเป็น signed จะได้ -1 ไม่ใช่ 65535")
        assertEquals(65535, identity?.minor, "อ่านเป็น signed จะได้ -1 ไม่ใช่ 65535")
    }

    @Test
    fun `array เป็น null ต้องคืน null`() {
        assertNull(ibeaconIdentityFrom(null))
    }

    @Test
    fun `array สั้นกว่า minor ต้องคืน null ไม่ใช่ค่าเดาหรือ exception`() {
        // ตัดไปให้เหลือแค่ prefix+uuid+major (20 ไบต์) — ไม่มี minor เลยแม้แต่ไบต์เดียว
        val truncated = payload(
            major = byteArrayOf(0x26, 0xAE.toByte()),
            minor = byteArrayOf(0x00, 0x02),
        ).copyOf(20)

        assertNull(ibeaconIdentityFrom(truncated))
        assertNull(ibeaconIdentityFrom(ByteArray(0)), "array ว่างก็ต้องคืน null เงียบ ๆ")
    }

    /**
     * ขาดไปพอดีหนึ่งไบต์ (22 จาก 23) — เคสอันตรายกว่าสั้นมาก ๆ เพราะ off-by-one
     * ในเงื่อนไข `data.size < minorIndex + 2` จะรอดไปได้ถ้าเช็คผิดเป็น `<=`
     */
    @Test
    fun `array ขาดไปพอดี 1 ไบต์ ก่อนถึง minor ตัวสุดท้าย ต้องคืน null`() {
        val oneShort = payload(
            major = byteArrayOf(0x26, 0xAE.toByte()),
            minor = byteArrayOf(0x00, 0x02),
        ).copyOf(21) // เหลือ prefix+uuid+major+minor[0] ไม่มี minor[1]

        assertNull(ibeaconIdentityFrom(oneShort))
    }

    @Test
    fun `prefix ไม่ใช่ 02 15 ต้องคืน null ทั้งก้อน ห้ามเดา major minor บางส่วน`() {
        val wrongPrefix = payload(
            major = byteArrayOf(0x26, 0xAE.toByte()),
            minor = byteArrayOf(0x00, 0x02),
        ).also { it[0] = 0x03 }

        assertNull(ibeaconIdentityFrom(wrongPrefix))
    }

    @Test
    fun `payload ยาวเกิน 23 ไบต์ ยังต้องอ่านไบต์ที่ตำแหน่งเดิม`() {
        val padded = payload(
            major = byteArrayOf(0x26, 0xAE.toByte()),
            minor = byteArrayOf(0x00, 0x02),
        ) + byteArrayOf(0x7F, 0x00, 0x11)

        assertEquals(IBeaconIdentity(major = 9902, minor = 2), ibeaconIdentityFrom(padded))
    }
}
