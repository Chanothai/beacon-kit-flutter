package com.bigc.beacon_kit_android

import android.bluetooth.le.ScanFilter
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * region หนึ่งอันที่แอปขอให้เฝ้าดูตอนอยู่เบื้องหลัง
 *
 * โครงเหมือน `IBeaconRegionConfig` ฝั่ง Dart และ `CLBeaconIdentityConstraint`
 * ฝั่ง iOS: UUID บังคับ ส่วน major/minor เป็นตัวเลือก (ไม่ระบุ = wildcard ตาม
 * ADR-5/ADR-8) — **แต่ความหมายของ "เฝ้าดู" ไม่เหมือนกัน** ดู ADR-14
 *
 * @param identifier ชื่อที่ผู้เรียกตั้งเอง ใช้อ้างถึง region นี้ใน event และเป็น
 *   กุญแจของทุกอย่างที่เก็บลงดิสก์ — **ต้องไม่ซ้ำกัน** และไม่ควรเปลี่ยนระหว่าง
 *   เวอร์ชัน ไม่งั้นสถานะที่เก็บไว้จะกลายเป็นขยะที่ไม่มีใครล้าง
 */
data class BeaconRegionSpec(
    val identifier: String,
    val uuid: UUID,
    val major: Int? = null,
    val minor: Int? = null,
) {
    companion object {
        /** company ID ของ Apple ที่ iBeacon ใช้ */
        const val APPLE_COMPANY_ID = 0x004C

        /**
         * สอง byte แรกของ manufacturer data ของ iBeacon: `0x02` = type "proximity"
         * `0x15` = ความยาว 21 byte ที่ตามมา — คงที่เสมอสำหรับ iBeacon
         */
        private val IBEACON_PREFIX = byteArrayOf(0x02, 0x15)

        fun fromMap(map: Map<*, *>): BeaconRegionSpec? {
            val identifier = map["identifier"] as? String ?: return null
            val rawUuid = map["uuid"] as? String ?: return null
            val uuid = runCatching { UUID.fromString(rawUuid) }.getOrNull() ?: return null
            return BeaconRegionSpec(
                identifier = identifier,
                uuid = uuid,
                major = (map["major"] as? Number)?.toInt(),
                minor = (map["minor"] as? Number)?.toInt(),
            )
        }

        fun listFromJson(raw: String): List<BeaconRegionSpec> =
            listFromJsonReporting(raw).regions

        /**
         * อ่านรายการ region พร้อม **เหตุผลเมื่ออ่านไม่สำเร็จ**
         *
         * [listFromJson] คืน list ว่างทั้งกรณี "ไม่มี region เก็บไว้จริง ๆ" และกรณี
         * "มีค่าเก็บไว้แต่อ่านไม่ออก" — สองกรณีนี้มีวิธีแก้คนละทางโดยสิ้นเชิง แต่
         * ให้อาการเดียวกันเป๊ะคือ `restoredRegions=[]` ในไฟล์หลักฐาน ซึ่งเป็นความ
         * ล้มเหลวเงียบชนิดที่ทำให้ตีความผลทดสอบเบื้องหลังผิดทั้งรอบ (สงสัยว่ามีโค้ด
         * ล้างสถานะทิ้ง ทั้งที่จริงคือ JSON เสีย หรือกลับกัน)
         *
         * `dropped` นับ element ที่อ่านไม่ได้ทีละอัน (ไม่มี identifier / uuid ผิด
         * รูปแบบ) — เดิมถูกทิ้งเงียบ ๆ ด้วย `mapNotNull` + `filter`
         */
        fun listFromJsonReporting(raw: String): ParsedRegionList {
            val array = runCatching { JSONArray(raw) }.getOrNull()
                ?: return ParsedRegionList(emptyList(), "invalid-json")

            val regions = mutableListOf<BeaconRegionSpec>()
            var dropped = 0
            for (index in 0 until array.length()) {
                val obj = array.optJSONObject(index)
                val uuid = obj?.let {
                    runCatching { UUID.fromString(it.optString("uuid")) }.getOrNull()
                }
                val identifier = obj?.optString("identifier").orEmpty()
                if (obj == null || uuid == null || identifier.isEmpty()) {
                    dropped++
                    continue
                }
                regions.add(
                    BeaconRegionSpec(
                        identifier = identifier,
                        uuid = uuid,
                        major = if (obj.has("major")) obj.optInt("major") else null,
                        minor = if (obj.has("minor")) obj.optInt("minor") else null,
                    ),
                )
            }

            return ParsedRegionList(
                regions = regions,
                readError = if (dropped > 0) {
                    "unreadable-entries=$dropped/${array.length()}"
                } else {
                    null
                },
            )
        }

        fun listToJson(regions: List<BeaconRegionSpec>): String {
            val array = JSONArray()
            for (region in regions) {
                array.put(
                    JSONObject().apply {
                        put("identifier", region.identifier)
                        put("uuid", region.uuid.toString())
                        region.major?.let { put("major", it) }
                        region.minor?.let { put("minor", it) }
                    },
                )
            }
            return array.toString()
        }
    }

    /**
     * `ScanFilter` ที่ตรงกับ **region นี้ตัวเดียว**
     *
     * ## ทำไมต้องเจาะจงถึงระดับ region ไม่ใช่กรองกว้าง ๆ แล้วมาแยกทีหลัง
     *
     * นี่คือหัวใจของการออกแบบตาม ADR-14: เราลงทะเบียนสแกน **หนึ่งครั้งต่อหนึ่ง
     * region** โดยแต่ละครั้งมี `PendingIntent` ของตัวเองที่พก `identifier` ติดไป
     * ด้วย เมื่อผลสแกนกลับมา ผู้รับจึงรู้ทันทีว่าเป็น region ไหน
     * **โดยไม่ต้องถอด byte แม้แต่ตัวเดียวในฝั่ง Kotlin**
     *
     * ข้อนี้สำคัญเพราะกติกาของโปรเจกต์คือ **ไม่มี parser ในฝั่ง Kotlin** (ทั้งสอง
     * แพลตฟอร์มต้องใช้โค้ดถอดรหัสชุดเดียวกันใน `beacon_kit_platform_interface`)
     * แต่เส้นทางเบื้องหลังไม่มี Flutter engine ให้เรียก parser ฝั่ง Dart เลย
     * ถ้าเลือกทางกรองกว้างแล้วแยกทีหลัง เราจะ**ถูกบังคับ**ให้เขียน parser ตัวที่
     * สองในฝั่ง Kotlin ซึ่งจะ drift จากตัวหลักโดยไม่มีเทสต์ไหนจับได้
     *
     * ## รูปแบบของ byte ที่กรอง
     *
     * `ScanFilter` เทียบกับผลของ `ScanRecord.getManufacturerSpecificData(id)` ซึ่ง
     * **ตัด company ID ออกไปแล้ว** (ยืนยันจาก `ScanFilter.java:618-638`) byte แรก
     * ที่กรองจึงเป็น `0x02 0x15` ไม่ใช่ `0x4C 0x00`
     *
     * ```
     * 02 15 | uuid (16 byte) | major (2) | minor (2) | txPower (1)
     * ```
     *
     * mask เป็น `0xFF` เฉพาะช่วงที่ระบุจริง — ไม่ระบุ major = ตัด array ให้สั้นลง
     * แทนการใส่ mask `0x00` เพื่อให้ตัวกรองในฮาร์ดแวร์ทำงานกับข้อมูลน้อยที่สุด
     */
    fun toScanFilter(): ScanFilter {
        val (data, mask) = scanFilterDataAndMask()
        return ScanFilter.Builder()
            .setManufacturerData(APPLE_COMPANY_ID, data, mask)
            .build()
    }

    /**
     * byte ที่จะยื่นให้ `ScanFilter` — **pure function จึงมี unit test คลุมได้จริง**
     *
     * แยกออกมาจาก [toScanFilter] โดยตั้งใจ: `ScanFilter.Builder` เป็นคลาสของ
     * framework ซึ่งเรียกใน JVM unit test ไม่ได้ ถ้าปล่อยตรรกะการเรียงไบต์ไว้ข้างใน
     * มันจะเป็น**ตรรกะที่เสี่ยงที่สุดในไฟล์นี้และทดสอบไม่ได้เลย** — ลำดับไบต์ของ
     * UUID ที่ผิดจะทำให้กรองไม่เจออะไรเลย โดยไม่มี error ใด ๆ อาการที่ออกมาคือ
     * "ไม่มี event" ซึ่งแยกไม่ออกจาก "ไม่มี beacon อยู่ใกล้"
     */
    fun scanFilterDataAndMask(): Pair<ByteArray, ByteArray> {
        val data = ArrayList<Byte>(23)
        val mask = ArrayList<Byte>(23)

        IBEACON_PREFIX.forEach {
            data.add(it)
            mask.add(0xFF.toByte())
        }

        // UUID บนสาย BLE เรียงแบบ big-endian (most significant byte ก่อน) ซึ่งตรง
        // กับลำดับที่คนอ่านเห็นในสตริง UUID — แต่ `UUID.mostSignificantBits` เป็น
        // `Long` ที่ต้องแตกออกมาเองให้ถูกลำดับ ไม่มี API สำเร็จรูปให้ใช้
        uuidToBytes(uuid).forEach {
            data.add(it)
            mask.add(0xFF.toByte())
        }

        if (major != null) {
            data.add((major shr 8).toByte())
            data.add(major.toByte())
            mask.add(0xFF.toByte())
            mask.add(0xFF.toByte())

            // minor ระบุได้ก็ต่อเมื่อระบุ major ด้วย เพราะ byte ของ minor อยู่ถัด
            // จาก major — จะข้ามไปกรองเฉพาะ minor ไม่ได้ด้วยโครงของ ScanFilter
            if (minor != null) {
                data.add((minor shr 8).toByte())
                data.add(minor.toByte())
                mask.add(0xFF.toByte())
                mask.add(0xFF.toByte())
            }
        }

        return data.toByteArray() to mask.toByteArray()
    }

    private fun uuidToBytes(uuid: UUID): ByteArray {
        val bytes = ByteArray(16)
        var most = uuid.mostSignificantBits
        var least = uuid.leastSignificantBits
        for (i in 7 downTo 0) {
            bytes[i] = (most and 0xFF).toByte()
            most = most shr 8
        }
        for (i in 15 downTo 8) {
            bytes[i] = (least and 0xFF).toByte()
            least = least shr 8
        }
        return bytes
    }
}

/**
 * ผลการอ่านรายการ region ที่เก็บไว้ — **แยก "ว่าง" ออกจาก "อ่านไม่สำเร็จ"**
 *
 * ผู้เรียกที่เขียนไฟล์หลักฐานต้องรายงานสองกรณีนี้ด้วยข้อความคนละแบบ ไม่ใช่ `[]`
 * เหมือนกันทั้งคู่ (ดู `BeaconRegionSpec.listFromJsonReporting`)
 *
 * @param readError `null` = อ่านค่าที่เก็บไว้ได้ครบ · ไม่ `null` = อ่านไม่สำเร็จ
 *   และ [regions] เป็นเพียงส่วนที่อ่านได้เท่านั้น **ห้ามอ่านว่าเป็นรายการที่ครบ**
 */
data class ParsedRegionList(
    val regions: List<BeaconRegionSpec>,
    val readError: String?,
)
