package com.bigc.beacon_kit_android

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals

/**
 * เทสต์ลำดับไบต์ของ `ScanFilter` — **ตรรกะที่เสี่ยงที่สุดในเส้นทางเบื้องหลังทั้งหมด**
 *
 * ## ทำไมต้องมีเทสต์นี้ทั้งที่มีเครื่องจริงให้ทดสอบอยู่แล้ว
 *
 * ถ้าลำดับไบต์ผิด `ScanFilter` จะไม่ match อะไรเลย **โดยไม่มี error ใด ๆ** —
 * `startScan` คืน 0 (สำเร็จ) การลงทะเบียนอยู่ครบ แต่ไม่มี broadcast มาสักครั้ง
 * อาการที่ผู้ทดสอบเห็นคือ "ไม่มี event" ซึ่ง **แยกไม่ออกจาก** "ไม่มี beacon อยู่ใกล้",
 * "MIUI ฆ่าแอป", "Bluetooth ปิดอยู่" หรือ "ระบบ throttle" — ทั้งหมดคือสมมติฐานที่
 * ต้องไล่ตัดออกทีละข้อบนเครื่องจริง ซึ่งกินเวลาเป็นชั่วโมงต่อรอบ
 *
 * เทสต์นี้ตัดสมมติฐานหนึ่งข้อนั้นออกไปได้ในเวลาเป็นมิลลิวินาที
 *
 * ⚠️ **ไม่ได้พิสูจน์ว่ากลไกทำงานบนเครื่องจริง** ตาม CONTRIBUTING ข้อ 4 —
 * พิสูจน์แค่ว่าไบต์ที่เราประกอบตรงกับสเปกของ iBeacon ที่เราเข้าใจ
 */
class BeaconRegionSpecTest {

    /** UUID ค่าโรงงานของ K9P ที่ใช้ในเดโมทั้งโปรเจกต์ */
    private val k9pUuid = UUID.fromString("7777772e-6b6b-6d63-6e2e-636f6d000001")

    /**
     * ไบต์ของ UUID ต้องเรียง **ตามลำดับที่อ่านเห็นในสตริง** ไม่ใช่กลับด้าน
     *
     * เป็นจุดที่พลาดง่ายที่สุด เพราะ company ID (`0x4C 0x00`) ที่อยู่ก่อนหน้าใน
     * payload เดียวกัน **เป็น little-endian** คนเขียนจึงมักเผลอกลับ UUID ตามไปด้วย
     */
    @Test
    fun `uuid ถูกเรียงไบต์ตามลำดับเดียวกับที่เห็นในสตริง`() {
        val (data, _) = BeaconRegionSpec("wide", k9pUuid).scanFilterDataAndMask()

        assertContentEquals(
            byteArrayOf(
                0x02, 0x15, // iBeacon type + length
                0x77, 0x77, 0x77, 0x2E,
                0x6B, 0x6B, 0x6D, 0x63,
                0x6E, 0x2E, 0x63, 0x6F,
                0x6D, 0x00, 0x00, 0x01,
            ),
            data,
        )
    }

    /**
     * ไม่ระบุ major = ตัด array ให้สั้นลง ไม่ใช่ใส่ mask `0x00`
     *
     * ผลลัพธ์ในการ match เหมือนกัน แต่ array ที่สั้นกว่าถูกส่งลงไปให้ตัวกรองใน
     * ฮาร์ดแวร์ทำงานน้อยลง — และสำคัญกว่านั้นคือมันอ่านแล้วตรงกับเจตนา
     */
    @Test
    fun `ไม่ระบุ major - ไม่มีไบต์ของ major หรือ minor เลย`() {
        val (data, mask) = BeaconRegionSpec("wide", k9pUuid).scanFilterDataAndMask()

        assertEquals(18, data.size, "2 (prefix) + 16 (uuid)")
        assertEquals(data.size, mask.size, "data กับ mask ต้องยาวเท่ากันเสมอ")
    }

    /** major เป็น big-endian บนสาย BLE — 0x0102 ต้องออกมาเป็น `01 02` */
    @Test
    fun `major ถูกเขียนแบบ big-endian`() {
        val (data, mask) = BeaconRegionSpec("branch", k9pUuid, major = 0x0102)
            .scanFilterDataAndMask()

        assertEquals(20, data.size, "2 + 16 + 2")
        assertEquals(0x01.toByte(), data[18])
        assertEquals(0x02.toByte(), data[19])
        assertEquals(data.size, mask.size)
    }

    @Test
    fun `minor ถูกเขียนต่อจาก major แบบ big-endian`() {
        val (data, mask) = BeaconRegionSpec(
            "device",
            k9pUuid,
            major = 1,
            minor = 0xABCD,
        ).scanFilterDataAndMask()

        assertEquals(22, data.size, "2 + 16 + 2 + 2")
        assertEquals(0xAB.toByte(), data[20])
        assertEquals(0xCD.toByte(), data[21])
        assertEquals(data.size, mask.size)
    }

    /**
     * mask ต้องเป็น `0xFF` ทุกไบต์ที่ระบุ
     *
     * ถ้ามีไบต์ไหนเป็น `0x00` โดยไม่ตั้งใจ ตัวกรองจะกว้างกว่าที่คิด แล้ว beacon ของ
     * สาขาอื่นจะถูกรายงานว่าเป็นสาขานี้ — ผิดแบบที่ **ยังมี event ออกมา** จึงหา
     * ไม่เจอจนกว่าจะเอาไปเทียบกับข้อมูลจากแหล่งอื่น
     */
    @Test
    fun `mask เป็น 0xFF ทุกไบต์ที่ระบุ`() {
        val (_, mask) = BeaconRegionSpec("device", k9pUuid, major = 1, minor = 2)
            .scanFilterDataAndMask()

        assertEquals(
            emptyList(),
            mask.withIndex().filter { it.value != 0xFF.toByte() }.map { it.index },
        )
    }

    /**
     * `minor` ที่ไม่มี `major` ต้องถูกเมิน ไม่ใช่เขียนลงไปผิดตำแหน่ง
     *
     * ฝั่ง Dart มี `assert` กันไว้แล้ว แต่ `assert` ถูกตัดทิ้งใน release build —
     * ฝั่ง Kotlin จึงต้องไม่พังถ้าค่าหลุดมาถึง ถ้าเขียน minor ลงตำแหน่งของ major
     * ตัวกรองจะเจาะจงผิดตัวโดยที่ยังมี event ออกมา ซึ่งหาไม่เจอ
     */
    @Test
    fun `minor ที่ไม่มี major ถูกเมิน ไม่ใช่เขียนลงตำแหน่งของ major`() {
        val (data, _) = BeaconRegionSpec("bad", k9pUuid, major = null, minor = 5)
            .scanFilterDataAndMask()

        assertEquals(18, data.size, "ต้องเหลือแค่ prefix + uuid")
    }
}
