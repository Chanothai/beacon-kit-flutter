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
 * ชั้น 1 (region enter/exit) มีหลักฐานจากอุปกรณ์จริงระดับ `observed` แล้ว (ADR-14)
 * ส่วนชั้น 2 (proximity) ยังไม่เคยรันจริงเลย และยังเป็น
 * POC — การเขียนลงคนละไฟล์ทำให้ (ก) ข้อมูลที่เสียหายของชั้น 2 ลาก state ของชั้น 1
 * ลงไปด้วยไม่ได้ และ (ข) ล้างสถานะ POC ทิ้งได้โดยไม่แตะสถานะ enter/exit
 *
 * ทุกเส้นทางอ่าน/เขียนถูกห่อด้วย `runCatching` — ค่าที่เสียหายต้องกลายเป็น "เริ่มนับ
 * ใหม่" ไม่ใช่ exception ที่ลอยขึ้นไปทำให้ชั้น 1 พัง (ADR-20 หัวข้อ 1)
 *
 * ## ความล้มเหลว **ถาวร** ต้องมีร่องรอย ไม่ใช่แค่ "เริ่มนับใหม่" เงียบ ๆ
 *
 * "เริ่มนับใหม่" เป็นคำตอบที่ถูกกับความเสียหาย**ชั่วคราว**เท่านั้น ถ้าดิสก์เขียนไม่ได้
 * ทุกครั้งจริง ๆ อาการที่ออกมาคือ dwell เริ่มนับหนึ่งใหม่ทุก sighting → `dwellSamples`
 * ไม่มีวันครบ → gate เงียบตลอด ซึ่ง **แยกไม่ออกจาก "ไม่มีบีคอนอยู่ใกล้" และ
 * "receiver ไม่เคยถูกปลุก"** เลยจากไฟล์หลักฐาน — ความล้มเหลวเงียบชนิดเดียวกับที่
 * ADR-17 ตั้งมาตรฐาน `<read-failed:...>` vs `[]` ขึ้นมาเพื่อกัน
 *
 * [lastError] จึงบันทึกเหตุผลของความล้มเหลวล่าสุดไว้ให้ผู้เรียกเอาไป log — เก็บเป็น
 * ข้อความแทนการเรียก `android.util.Log` ที่นี่โดยตั้งใจ เพราะคลาสนี้ต้องเรียกได้จาก
 * JVM unit test ที่ `android.util.Log` เป็นสตับซึ่งโยน "not mocked" เสมอ
 */
class ProximityGateStore(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * อ่านสถานะทุก key ที่เก็บไว้ — **คืน map ว่างเมื่ออ่านไม่สำเร็จ** (เท่ากับ
     * "เริ่มนับใหม่") ต่างจาก `BackgroundRegionStore.readRegions()` ที่ต้องแยก
     * "ว่าง" ออกจาก "อ่านไม่ออก" เพราะค่านั้นถูกเขียนลงไฟล์หลักฐาน ส่วนค่านี้เป็น
     * สถานะชั่วคราวของหน้าต่าง RSSI ที่หายแล้วสร้างใหม่ได้เองในไม่กี่วินาที
     *
     * ## Migration ของรูปร่าง key (ADR-20 หัวข้อ 3 "Migration ของ state บนดิสก์")
     *
     * รูปร่าง key เปลี่ยนจาก `region|MAC` (2 ส่วน) เป็น `region|uuid|major|minor`
     * (4 ส่วน) เมื่อ 11 ก.ย. 2026 — เครื่องที่รันบิลด์เก่าค้างอยู่จะมี entry รูปแบบ
     * เก่าอยู่ใน `SharedPreferences` ทั้งใต้คีย์ `"states"` เดิม (ก่อนเปลี่ยนชื่อคีย์
     * เป็น [KEY_STATES]) และในทางทฤษฎีปนอยู่ใต้คีย์ใหม่ได้ถ้ามีบั๊กอื่นเขียนทับ —
     * `load()` จึงทำสองอย่างเสมอทุกครั้งที่เรียก:
     * 1. ถ้าเจอคีย์เก่า [LEGACY_KEY_STATES] ให้ลบทิ้งจาก `SharedPreferences` ด้วย
     *    `commit()` **ไม่แปลงค่าเดา** (ห้ามพยายาม "เดา" ว่า MAC ส่วนหลัง `|` เดิม
     *    คือบีคอนตัวไหนแล้วแปลงเป็น key ใหม่เอง — ไม่มีข้อมูลพอจะแปลงถูกต้อง) —
     *    **ต้องเช็คผลของ `commit()` ก่อนนับว่า migrate สำเร็จ** (รอบแก้ 11 ก.ย.
     *    2026): `commit()` คืน `false` เมื่อเขียนไม่สำเร็จโดยไม่โยน exception เลย
     *    ถ้าเจอ `false` หรือ exception ถือว่าลบไม่สำเร็จทั้งคู่ — **ไม่นับ**เข้า
     *    [lastMigrationDroppedCount] ของรอบนี้ ตั้ง [lastError] แทน แล้วปล่อยให้
     *    รอบถัดไปพยายามลบใหม่เอง (ไม่มี flag ค้างว่า "เคยล้มเหลว") มิฉะนั้นคีย์เก่า
     *    จะค้างบนดิสก์ตลอดไป → `contains()` เป็น `true` ทุกรอบ → รายงาน
     *    `store=migrated_dropped=<n>` ซ้ำไม่รู้จบ ขัดกฎข้อ 3 ด้านล่าง
     * 2. filter ทุก entry ใต้ [KEY_STATES] ที่รูปร่าง key ไม่ผ่าน [isValidKeyShape]
     *    ทิ้งไปด้วย (ดู [statesFromJson] ที่ใช้ตัวเดียวกัน)
     *
     * จำนวนที่ทิ้งจริงของทั้งสองแบบ (ลบคีย์เก่าสำเร็จ + shape ไม่ผ่านใต้คีย์ใหม่)
     * ถูกนับรวมไว้ที่ [lastMigrationDroppedCount] — **ต้องแยกออกจาก [lastError]
     * ได้เสมอ** เพราะ migration สำเร็จ ≠ ดิสก์พัง ผู้เรียก (`BeaconScanReceiver`)
     * เป็นคนรวมสองค่านี้เป็นข้อความเดียวที่แยกส่วนได้ด้วยเนื้อข้อความสำหรับคอลัมน์
     * `store=` ของไฟล์หลักฐาน
     */
    fun load(): Map<String, ProximityKeyState> {
        var migrationDropped: Int? = null

        if (prefs.contains(LEGACY_KEY_STATES)) {
            val legacyCount = runCatching { prefs.getString(LEGACY_KEY_STATES, null) }
                .getOrNull()
                ?.let(::countTopLevelKeys)
                ?: 0
            // ต้องเช็คผลของ commit() แบบเดียวกับ [save] (~บรรทัด 149-155) —
            // commit() คืน false เมื่อเขียนไม่สำเร็จ **โดยไม่โยน exception**
            // runCatching เพียงอย่างเดียวจับสาขานี้ไม่ได้ ถ้าปล่อยผ่านคีย์เก่าจะ
            // ค้างบนดิสก์ → prefs.contains(LEGACY_KEY_STATES) เป็น true ตลอด →
            // load() "migrate" ซ้ำทุก onReceive → รายงาน store=migrated_dropped=<n>
            // ไม่รู้จบ ขัด "รายงานครั้งเดียวตอนพบ" ที่กฎข้อ 3 ด้านล่างสั่งไว้เอง
            // (รอบแก้ 11 ก.ย. 2026) — commit() คืน false หรือโยน exception ถือว่า
            // ลบไม่สำเร็จเหมือนกันทั้งคู่: **ไม่นับ** ว่า migrate สำเร็จ (ห้ามบวก
            // เข้า migrationDropped ของคีย์เก่ารอบนี้) ตั้ง lastError แทน แล้วปล่อย
            // ให้รอบถัดไปพยายามลบใหม่ — ไม่มี flag ค้างว่า "เคยล้มเหลว"
            runCatching { prefs.edit().remove(LEGACY_KEY_STATES).commit() }
                .fold(
                    onSuccess = { committed ->
                        if (committed) {
                            migrationDropped = (migrationDropped ?: 0) + legacyCount
                        } else {
                            lastError = "load:legacy-remove-commit-returned-false"
                        }
                    },
                    onFailure = { error ->
                        lastError = "load:legacy-remove-${error.javaClass.simpleName}"
                    },
                )
        }

        val raw = runCatching { prefs.getString(KEY_STATES, null) }
            .getOrElse { error ->
                lastError = "load:${error.javaClass.simpleName}"
                lastMigrationDroppedCount = migrationDropped
                return emptyMap()
            }
        if (raw == null) {
            lastMigrationDroppedCount = migrationDropped
            return emptyMap()
        }

        val shapeDropped = countShapeInvalidKeys(raw)
        if (shapeDropped > 0) {
            migrationDropped = (migrationDropped ?: 0) + shapeDropped
        }
        lastMigrationDroppedCount = migrationDropped

        val states = statesFromJson(raw)
        // ค่าที่เขียนไว้จริงแต่ถอดกลับมาไม่ได้เลยสักตัว = ข้อมูลบนดิสก์เสียหาย
        // (ต่างจาก `"{}"` ซึ่งคือ "ว่างจริง ๆ" — ความต่างเดียวกับ `[]` vs
        // `<read-failed:...>` ของ ADR-17)
        if (states.isEmpty() && raw != EMPTY_JSON) {
            lastError = "load:unparsable(${raw.length}B)"
        }
        return states
    }

    /**
     * เหตุผลของความล้มเหลวล่าสุดของ [load]/[save] — `null` แปลว่ายังไม่เคยล้ม
     *
     * ผู้เรียก (`BeaconScanReceiver`) เป็นคน log ค่านี้ ดู kdoc ของคลาสว่าทำไมถึงไม่
     * เรียก `android.util.Log` ที่นี่เอง
     */
    var lastError: String? = null
        private set

    /**
     * จำนวน entry ที่ถูกทิ้งเพราะ migration ของรูปร่าง key ใน [load] ล่าสุด — `null`
     * แปลว่า**ไม่มี migration เกิดขึ้นในรอบนี้เลย** (ต่างจาก `0` ซึ่งแปลว่า **เจอ
     * เงื่อนไข migration แต่ไม่มีอะไรให้ทิ้งจริง** เช่น เจอคีย์เก่าแต่เนื้อหาว่าง)
     *
     * ตั้งใจแยกเป็นฟิลด์ของตัวเอง **ไม่ปนกับ [lastError]** เพราะ migration สำเร็จ
     * (ลบขยะเก่าทิ้งได้ถูกต้อง) กับดิสก์พังจริงเป็นคนละเรื่องกัน — ถ้ายัดรวมช่อง
     * เดียวกันจนแยกไม่ออก ผู้ทดสอบที่เห็นข้อความจะเข้าใจผิดว่ามีอะไรพังอยู่ ทั้งที่
     * เป็นพฤติกรรมที่ตั้งใจของบิลด์ที่เปลี่ยนรูปร่าง key (ADR-20 หัวข้อ 3)
     */
    var lastMigrationDroppedCount: Int? = null
        private set

    /** เขียนทับสถานะทั้งหมดใน `commit()` เดียว — ดู kdoc ของคลาสเรื่อง `commit()` */
    fun save(states: Map<String, ProximityKeyState>) {
        runCatching {
            val committed =
                prefs.edit().putString(KEY_STATES, statesToJson(states)).commit()
            // `commit()` คืน false เมื่อเขียนไม่สำเร็จ **โดยไม่โยน exception** —
            // สาขานี้คือความล้มเหลวเงียบที่ `runCatching` เพียงอย่างเดียวจับไม่ได้
            if (!committed) lastError = "save:commit-returned-false"
        }.onFailure { error ->
            lastError = "save:${error.javaClass.simpleName}"
        }
    }

    /** ล้างทุกอย่าง — สำหรับเส้นทางที่หยุดเฝ้า region หรือเวลาไล่บั๊กในสนาม */
    fun clear() {
        runCatching { prefs.edit().clear().commit() }
    }

    companion object {
        private const val PREFS_NAME = "beacon_kit_android.proximity"

        /**
         * ทั้ง map อยู่ในคีย์เดียว — เขียนครั้งเดียวจบ ไม่มีสถานะเหลือครึ่ง ๆ
         *
         * **`"states_v2"` ไม่ใช่ `"states"`** — bump เมื่อ 11 ก.ย. 2026 พร้อมกับที่
         * รูปร่างของ key เปลี่ยนจาก `region|MAC` เป็น `region|uuid|major|minor`
         * (ADR-20 หัวข้อ 3 "Migration ของ state บนดิสก์") **กติกาทั่วไปสำหรับ
         * อนาคต: รูปร่างของ key หรือ state เปลี่ยนเมื่อไร ต้อง bump ชื่อคีย์นี้และ
         * ทำ drop-with-log เสมอ ห้าม migrate แบบแปลงค่าเดา**
         */
        private const val KEY_STATES = "states_v2"

        /**
         * ชื่อคีย์เดิมก่อน 11 ก.ย. 2026 — เก็บไว้เพียงเพื่อให้ [load] รู้จักและลบทิ้ง
         * ครั้งเดียวตอนเจอ ไม่ปล่อยค้างเป็นขยะถาวรบน `SharedPreferences` ของเครื่อง
         * ที่เคยรันบิลด์เก่า
         */
        private const val LEGACY_KEY_STATES = "states"

        /** JSON ของ "ไม่มี key เลยจริง ๆ" — ต่างจาก "อ่านแล้วถอดไม่ออก" (ดู [load]) */
        private const val EMPTY_JSON = "{}"

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
         * รูปร่างของ key ที่ถือว่าใช้ได้กับโค้ดเวอร์ชันปัจจุบัน — เรียก
         * [proximityKeyPartsOrNull] (`BeaconScanReceiver.kt`) ตรง ๆ แล้วเช็คว่าไม่
         * เป็น `null` **ไม่เขียนตรรกะถอดรูปร่าง key ซ้ำเป็นตัวที่สอง** (รอบแก้
         * 11 ก.ย. 2026 — ก่อนหน้านี้ไฟล์นี้เคยเช็คด้วย `key.split('|').size == 4`
         * ตรง ๆ ของตัวเอง ต่างจาก [proximityKeyPartsOrNull] ที่ตัดจากท้ายแบบ
         * `>= 4` เพื่อให้ตรงกับ Swift — สองจุดตีความรูปร่าง key ต่างกันจน
         * `regionIdentifier` ที่มี `|` ปนอยู่ถูกไฟล์นี้ตัดทิ้งทุกรอบ `load()` โดยไม่
         * มีอะไรฟ้อง) ใช้ร่วมกันทั้งใน [statesFromJson] (ตอน filter) และ
         * [countShapeInvalidKeys] (ตอนนับ) — และตอนนี้ยังใช้ตรรกะเดียวกับที่
         * `BeaconScanReceiver` ใช้ถอด key ของ transition ด้วย มีจุดเดียวทั้งโมดูล
         */
        private fun isValidKeyShape(key: String): Boolean = proximityKeyPartsOrNull(key) != null

        /** จำนวน key ระดับบนสุดของ JSON — ใช้รายงานจำนวน entry ที่ถูกทิ้งตอน migration */
        private fun countTopLevelKeys(raw: String): Int =
            runCatching { JSONObject(raw).length() }.getOrDefault(0)

        /** จำนวน key ที่รูปร่างไม่ผ่าน [isValidKeyShape] — ดู [ProximityGateStore.load] */
        private fun countShapeInvalidKeys(raw: String): Int {
            val root = runCatching { JSONObject(raw) }.getOrNull() ?: return 0
            var count = 0
            for (key in root.keys()) {
                if (!isValidKeyShape(key)) count++
            }
            return count
        }

        /**
         * ถอด JSON กลับเป็นสถานะ — **key ที่ถอดไม่ออกหรือรูปร่างไม่ตรง
         * [isValidKeyShape] ถูกข้ามไปเงียบ ๆ ไม่ throw** ผลที่แย่ที่สุดคือ key นั้น
         * เริ่มนับ dwell ใหม่ ซึ่งยอมรับได้กว่าการทำให้ทั้ง batch (รวมชั้น 1 ที่มี
         * หลักฐานระดับ `observed` แล้ว) ล้มเพราะสถานะ POC เสียหายตัวเดียว —
         * จำนวนที่ถูกทิ้งเพราะรูปร่างไม่ตรงถูกนับแยกไว้ที่ [ProximityGateStore.load]
         * ผ่าน [countShapeInvalidKeys] เพื่อให้ฟังก์ชันนี้ยังคงเป็น pure function
         */
        internal fun statesFromJson(raw: String): Map<String, ProximityKeyState> {
            val root = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyMap()
            val out = LinkedHashMap<String, ProximityKeyState>()
            for (key in root.keys()) {
                if (!isValidKeyShape(key)) continue
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
