package com.bigc.beacon_kit_android

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * สถานะของ [ProximityGate] ทุก key ที่ต้องรอดข้าม process
 *
 * ## ทำไมต้องเขียนลงดิสก์ **ทุก sighting** ไม่ใช่เก็บใน memory
 *
 * `BeaconScanReceiver` มีชีวิตแค่ช่วง `onReceive()` และ OEM แบบ MIUI ฆ่า process
 * ทิ้งได้ทันทีที่เมธอดนั้นคืนค่า ถ้าเก็บหน้าต่าง/ตัวนับ dwell ไว้ใน memory อย่างเดียว
 * ทุกอย่างจะรีเซ็ตทุก sighting แล้ว `dwellSamples = 3` **จะไม่มีวันครบ** — gate เงียบ
 * ตลอดทั้งที่ผู้ใช้ยืนอยู่หน้าชั้นวาง (ADR-20 หัวข้อ 3)
 *
 * ## ทำไม `commit()` ไม่ใช่ `apply()`
 *
 * เหตุผลเดียวกับ `BackgroundRegionStore` เป๊ะ: `apply()` เขียนแบบไม่ซิงโครนัส ระบบ
 * อาจฆ่า process ทันทีที่ `onReceive()` คืนค่า แล้วสถานะที่เพิ่งนับได้หายไปเงียบ ๆ
 * — ซึ่งคืออาการเดียวกับที่คลาสนี้ทั้งคลาสมีไว้ป้องกัน
 *
 * ## ไฟล์ prefs แยกจาก `BackgroundRegionStore` โดยตั้งใจ
 *
 * ชั้น 1 (region enter/exit) คือฟีเจอร์ที่พิสูจน์แล้ว ส่วนชั้น 2 (proximity) ยังเป็น
 * POC — การเขียนลงคนละไฟล์ทำให้ (ก) ข้อมูลที่เสียหายของชั้น 2 ลาก state ของชั้น 1
 * ลงไปด้วยไม่ได้ และ (ข) ล้างสถานะ POC ทิ้งได้โดยไม่แตะสถานะ enter/exit
 *
 * ทุกเส้นทางอ่าน/เขียนถูกห่อด้วย `runCatching` — ค่าที่เสียหายต้องกลายเป็น "เริ่มนับ
 * ใหม่" ไม่ใช่ exception ที่ลอยขึ้นไปทำให้ชั้น 1 พัง (ADR-20 หัวข้อ 1)
 */
class ProximityGateStore(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * อ่านสถานะทุก key ที่เก็บไว้ — **คืน map ว่างเมื่ออ่านไม่สำเร็จ** (เท่ากับ
     * "เริ่มนับใหม่") ต่างจาก `BackgroundRegionStore.readRegions()` ที่ต้องแยก
     * "ว่าง" ออกจาก "อ่านไม่ออก" เพราะค่านั้นถูกเขียนลงไฟล์หลักฐาน ส่วนค่านี้เป็น
     * สถานะชั่วคราวของหน้าต่าง RSSI ที่หายแล้วสร้างใหม่ได้เองในไม่กี่วินาที
     */
    fun load(): Map<String, ProximityKeyState> {
        val raw = prefs.getString(KEY_STATES, null) ?: return emptyMap()
        return statesFromJson(raw)
    }

    /** เขียนทับสถานะทั้งหมดใน `commit()` เดียว — ดู kdoc ของคลาสเรื่อง `commit()` */
    fun save(states: Map<String, ProximityKeyState>) {
        runCatching {
            prefs.edit().putString(KEY_STATES, statesToJson(states)).commit()
        }
    }

    /** ล้างทุกอย่าง — สำหรับเส้นทางที่หยุดเฝ้า region หรือเวลาไล่บั๊กในสนาม */
    fun clear() {
        runCatching { prefs.edit().clear().commit() }
    }

    companion object {
        private const val PREFS_NAME = "beacon_kit_android.proximity"

        /** ทั้ง map อยู่ในคีย์เดียว — เขียนครั้งเดียวจบ ไม่มีสถานะเหลือครึ่ง ๆ */
        private const val KEY_STATES = "states"

        private const val FIELD_CONFIRMED = "confirmedBucket"
        private const val FIELD_PENDING_BUCKET = "pendingCloserBucket"
        private const val FIELD_PENDING_COUNT = "pendingCloserCount"
        private const val FIELD_DROPPED = "droppedNoTxPowerCount"
        private const val FIELD_WINDOW = "window"
        private const val FIELD_LAST_SAMPLE_AT = "lastSampleAt"

        /**
         * แปลงสถานะเป็น JSON — **pure function จึงมี unit test คลุมได้จริง** โดยไม่
         * ต้องมี `Context` (เหตุผลเดียวกับที่ `BeaconRegionSpec.scanFilterDataAndMask()`
         * ถูกแยกออกจาก `toScanFilter()`)
         *
         * bucket ถูกเขียนด้วย [ProximityBucket.wireName] ไม่ใช่ `name` หรือ `ordinal`
         * — `ordinal` จะเปลี่ยนความหมายเงียบ ๆ ถ้ามีใครเพิ่ม/สลับค่าใน enum วันหลัง
         * แล้วสถานะที่ค้างอยู่บนเครื่องผู้ใช้จะถูกอ่านผิดโดยไม่มีอะไรฟ้อง
         */
        internal fun statesToJson(states: Map<String, ProximityKeyState>): String {
            val root = JSONObject()
            for ((key, state) in states) {
                val window = JSONArray()
                // เขียนตามลำดับเดิมของหน้าต่าง — ลำดับคือข้อมูล ไม่ใช่แค่ที่เก็บ
                // (ตัวใหม่สุดต้องอยู่ท้ายเสมอ ไม่งั้นการตัดหัวรอบหน้าจะตัดผิดตัว)
                for (value in state.window) {
                    window.put(value)
                }
                val obj = JSONObject()
                    .put(FIELD_CONFIRMED, state.confirmedBucket?.wireName)
                    .put(FIELD_PENDING_BUCKET, state.pendingCloserBucket?.wireName)
                    .put(FIELD_PENDING_COUNT, state.pendingCloserCount)
                    .put(FIELD_DROPPED, state.droppedNoTxPowerCount)
                    .put(FIELD_WINDOW, window)
                // `put(String, null)` ของ org.json = ลบคีย์ทิ้ง — ค่า null ของ
                // lastSampleAt จึงกลายเป็น "ไม่มีคีย์" ตอนอ่านกลับ ซึ่งตรงกับ
                // ความหมายที่ต้องการพอดี (ยังไม่เคยมี sample ที่ใช้ตัดสินได้เลย)
                state.lastSampleAt?.let { obj.put(FIELD_LAST_SAMPLE_AT, it) }
                root.put(key, obj)
            }
            return root.toString()
        }

        /**
         * ถอด JSON กลับเป็นสถานะ — **key ที่ถอดไม่ออกถูกข้ามไปเงียบ ๆ ไม่ throw**
         * ผลที่แย่ที่สุดคือ key นั้นเริ่มนับ dwell ใหม่ ซึ่งยอมรับได้กว่าการทำให้
         * ทั้ง batch (รวมชั้น 1 ที่พิสูจน์แล้ว) ล้มเพราะสถานะ POC เสียหายตัวเดียว
         */
        internal fun statesFromJson(raw: String): Map<String, ProximityKeyState> {
            val root = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyMap()
            val out = LinkedHashMap<String, ProximityKeyState>()
            for (key in root.keys()) {
                val obj = root.optJSONObject(key) ?: continue
                val windowJson = obj.optJSONArray(FIELD_WINDOW) ?: JSONArray()
                val window = ArrayList<Double>(windowJson.length())
                for (i in 0 until windowJson.length()) {
                    window.add(windowJson.optDouble(i))
                }
                out[key] = ProximityKeyState(
                    confirmedBucket = ProximityBucket.fromWireName(
                        obj.optString(FIELD_CONFIRMED, "").ifEmpty { null },
                    ),
                    pendingCloserBucket = ProximityBucket.fromWireName(
                        obj.optString(FIELD_PENDING_BUCKET, "").ifEmpty { null },
                    ),
                    pendingCloserCount = obj.optInt(FIELD_PENDING_COUNT, 0),
                    droppedNoTxPowerCount = obj.optInt(FIELD_DROPPED, 0),
                    window = window,
                    lastSampleAt = if (obj.has(FIELD_LAST_SAMPLE_AT) &&
                        !obj.isNull(FIELD_LAST_SAMPLE_AT)
                    ) {
                        obj.optLong(FIELD_LAST_SAMPLE_AT)
                    } else {
                        null
                    },
                )
            }
            return out
        }
    }
}
