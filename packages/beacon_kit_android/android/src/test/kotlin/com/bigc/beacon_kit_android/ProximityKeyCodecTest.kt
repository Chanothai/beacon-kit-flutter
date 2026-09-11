package com.bigc.beacon_kit_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * เทสต์ pure function `proximityKeyFor()`/`proximityKeyPartsOrNull()` ล้วน ๆ —
 * ไม่ต้องมี `Context`/`SharedPreferences` เลย (ต่างจาก `ProximityGateStoreTest` ที่
 * เทสต์ผ่านชั้น store) เพราะสองฟังก์ชันนี้เป็น pure function ที่ประกอบ/ถอด key ของ
 * `ProximityGate` ล้วน ๆ
 *
 * ## โฟกัสของไฟล์นี้: C1 (รอบแก้ 11 ก.ย. 2026)
 *
 * `proximityKeyPartsOrNull()` เดิมใช้ `parts.size != 4` + ตัดตำแหน่งคงที่ ต่างจาก
 * `ProximityKeyCodec.parse()` ฝั่ง Swift
 * (`packages/beacon_kit_ios/ios/beacon_kit_ios/Sources/beacon_kit_ios/ProximityGate.swift`)
 * ที่ตัดจากท้าย (`parts.count >= 4` + 3 ส่วนท้ายคงที่เป็น uuid/major/minor + ที่เหลือ
 * รวมกลับด้วย `|` เป็น regionIdentifier) เพราะ `regionIdentifier` เป็นสตริงที่ host
 * app ตั้งเองได้อิสระ (`BeaconRegionSpec.kt` ไม่มีการกัน `|` เลย) — ไฟล์นี้ล็อกว่า
 * ทั้งสองภาษาต้องถอด key แบบเดียวกันเป๊ะ ทั้งเคสปกติและเคสขอบ (major/minor ไม่ใช่
 * ตัวเลข, นอกช่วง uint16)
 *
 * เทียบทีละเงื่อนไขกับ `ProximityKeyCodec.parse()` ของ Swift:
 * - Swift: `parts.count >= 4` → Kotlin: `parts.size < 4` return null (ตัวเดียวกัน)
 * - Swift: `UInt16(parts[...])` คืน `nil` เมื่อไม่ใช่ตัวเลขหรือค่านอกช่วง 0..65535
 *   → Kotlin: `uint16OrNull()` = `toIntOrNull()?.takeIf { it in 0..65535 }`
 *   (ครอบทั้ง "ไม่ใช่ตัวเลข" และ "นอกช่วง" เหมือนกันทั้งคู่)
 * - Swift: ส่วนที่เหลือก่อนสามส่วนท้ายต่อกลับด้วย `|` → Kotlin:
 *   `parts.subList(0, parts.size - 3).joinToString("|")` (ตัวเดียวกัน)
 * - ทั้งสองภาษาแยก parts ด้วย `split` ที่**ไม่ omit ส่วนว่าง**
 *   (Swift ระบุ `omittingEmptySubsequences: false` ตรง ๆ, Kotlin's
 *   `String.split(Char)` ไม่ omit ส่วนว่างเป็นค่า default อยู่แล้ว) — พฤติกรรมตรงกัน
 *   โดยไม่ต้องเขียนอะไรเพิ่ม
 */
class ProximityKeyCodecTest {

    private val uuid = "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0"
    private val uuidLower = "e2c56db5-dffb-48d2-b060-d0f5a71096e0"

    @Test
    fun `round-trip ปกติ ไม่มี pipe ปนใน regionIdentifier`() {
        val key = proximityKeyFor("bigc-test", uuid, 9902, 2)
        assertEquals("bigc-test|$uuidLower|9902|2", key)

        val parts = assertNotNull(proximityKeyPartsOrNull(key))
        assertEquals("bigc-test", parts.regionIdentifier)
        assertEquals(uuidLower, parts.uuid)
        assertEquals(9902, parts.major)
        assertEquals(2, parts.minor)
    }

    /**
     * นี่คืออาการจริงของบั๊ก C1 — ก่อนแก้ `parts.size != 4` จะตัด key 5 ส่วนนี้ทิ้ง
     * ทันที (เห็นเหมือน "รูปแบบเก่า") แล้ว `ProximityGateStore.isValidKeyShape` จะ
     * ตัด state ทิ้งทุกรอบ `load()` — state หายเงียบทุกรอบ ไม่ใช่แค่ event field
     * เป็น null
     */
    @Test
    fun `round-trip regionIdentifier ที่มี pipe ปนอยู่ต้องได้ regionIdentifier ครบ ไม่ใช่ถูกตัดเหลือส่วนแรก`() {
        val key = proximityKeyFor("a|b", uuid, 9902, 2)
        assertEquals("a|b|$uuidLower|9902|2", key)

        val parts = assertNotNull(proximityKeyPartsOrNull(key))
        assertEquals("a|b", parts.regionIdentifier, "ต้องได้ \"a|b\" ครบ ไม่ใช่ \"a\" (บั๊ก C1 เดิม)")
        assertEquals(uuidLower, parts.uuid)
        assertEquals(9902, parts.major)
        assertEquals(2, parts.minor)
    }

    @Test
    fun `round-trip regionIdentifier ที่มี pipe หลายตัวก็ยังประกอบกลับได้ถูก`() {
        val key = proximityKeyFor("สาขา|ชั้น2|โซนเอ", uuid, 1, 0)

        val parts = assertNotNull(proximityKeyPartsOrNull(key))
        assertEquals("สาขา|ชั้น2|โซนเอ", parts.regionIdentifier)
        assertEquals(uuidLower, parts.uuid)
        assertEquals(1, parts.major)
        assertEquals(0, parts.minor)
    }

    /** รูปแบบเก่า `region|MAC` (2 ส่วน) ต้องยังถูกปฏิเสธเหมือนเดิม — C1 ต้องไม่ทำให้ migration เสีย */
    @Test
    fun `key รูปแบบเก่า region MAC สองส่วนต้องถูกปฏิเสธเป็น null`() {
        assertNull(proximityKeyPartsOrNull("bigc-test|AA:BB:CC:DD:EE:FF"))
    }

    /** เคสขอบรอบ >= 4: ว่างเปล่า/ส่วนเดียว/สามส่วน (ยังไม่ถึง 4) ต้องถูกปฏิเสธทั้งหมด */
    @Test
    fun `key ที่มีจำนวนส่วนน้อยกว่า 4 ต้องถูกปฏิเสธทุกกรณี`() {
        assertNull(proximityKeyPartsOrNull(""))
        assertNull(proximityKeyPartsOrNull("bigc-test"))
        assertNull(proximityKeyPartsOrNull("a|b|c"))
    }

    @Test
    fun `major หรือ minor ที่ไม่ใช่ตัวเลขต้องถูกปฏิเสธ`() {
        assertNull(proximityKeyPartsOrNull("bigc-test|$uuidLower|abc|2"))
        assertNull(proximityKeyPartsOrNull("bigc-test|$uuidLower|9902|xyz"))
    }

    /** uint16OrNull ต้องปฏิเสธค่าติดลบ เหมือน `UInt16(String)` ฝั่ง Swift */
    @Test
    fun `major หรือ minor ที่ติดลบต้องถูกปฏิเสธ`() {
        assertNull(proximityKeyPartsOrNull("bigc-test|$uuidLower|-1|2"))
        assertNull(proximityKeyPartsOrNull("bigc-test|$uuidLower|9902|-1"))
    }

    /** uint16OrNull ต้องปฏิเสธค่าเกินช่วง uint16 (65535) เหมือน `UInt16(String)` ฝั่ง Swift */
    @Test
    fun `major หรือ minor ที่เกินช่วง uint16 (เกิน 65535) ต้องถูกปฏิเสธ`() {
        assertNull(proximityKeyPartsOrNull("bigc-test|$uuidLower|65536|2"))
        assertNull(proximityKeyPartsOrNull("bigc-test|$uuidLower|9902|65536"))
    }

    /** ขอบเขตที่ถูกต้องพอดี (0 และ 65535) ต้องยอมรับ ไม่ใช่ถูกปฏิเสธไปด้วยความผิดพลาดของช่วง */
    @Test
    fun `major และ minor ที่ขอบเขตพอดี 0 และ 65535 ต้องยอมรับ`() {
        val parts = assertNotNull(proximityKeyPartsOrNull("bigc-test|$uuidLower|65535|0"))
        assertEquals(65535, parts.major)
        assertEquals(0, parts.minor)
    }
}
