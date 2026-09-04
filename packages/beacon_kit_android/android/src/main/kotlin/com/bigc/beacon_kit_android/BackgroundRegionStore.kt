package com.bigc.beacon_kit_android

import android.content.Context
import android.content.SharedPreferences
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject

/**
 * สถานะทั้งหมดของการเฝ้า region เบื้องหลัง ที่ต้องรอดข้าม process
 *
 * ## ทำไมต้องเก็บลงดิสก์เอง — ต่างจาก iOS โดยพื้นฐาน
 *
 * ฝั่ง iOS ไม่มีคลาสแบบนี้เลย เพราะ **ระบบเก็บ region ให้** —
 * `CLLocationManager.monitoredRegions` ระบุไว้ว่า region ที่ลงทะเบียนไว้ "during
 * this or previous launches of your application" จะยังอยู่ในเซ็ตนี้ แอปจึงแค่ถาม
 * ระบบก็รู้ว่าเฝ้าอะไรอยู่
 *
 * **Android ไม่มีอะไรเทียบเท่านั้น** ไม่มี API ให้ถามว่า "ตอนนี้ฉันลงทะเบียนสแกน
 * อะไรไว้บ้าง" และไม่มีสถานะ enter/exit ที่ระบบคำนวณให้ ทั้งรายการ region และ
 * สถานะเข้า/ออกจึงเป็น **ของเราเอง** ที่ต้องเก็บและกู้คืนเอง — ดู ADR-14
 *
 * ## ทำไม `commit()` ไม่ใช่ `apply()`
 *
 * `apply()` เขียนแบบไม่ซิงค์ ระบบอาจฆ่า process ทันทีที่ `onReceive()` คืนค่า
 * ซึ่งแปลว่าสถานะที่เพิ่งเปลี่ยนหายไปเงียบ ๆ แล้วรอบถัดไปจะรายงาน enter ซ้ำ
 * ทั้งที่ไม่เคยออก — เหตุผลเดียวกับที่ฝั่ง iOS ต้อง `fsync` ไฟล์ log
 */
class BackgroundRegionStore(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    companion object {
        private const val PREFS_NAME = "beacon_kit_android.background"

        private const val KEY_REGIONS = "regions"
        private const val KEY_ACTIVE = "active"
        private const val KEY_EXIT_TIMEOUT_SECONDS = "exitTimeoutSeconds"
        private const val KEY_BOOT_TOKEN = "bootToken"
        private const val KEY_PENDING_EVENTS = "pendingEvents"

        private const val PREFIX_INSIDE = "inside."
        private const val PREFIX_LAST_SEEN_ELAPSED = "lastSeenElapsed."
        private const val PREFIX_LAST_SEEN_WALL = "lastSeenWall."
        private const val PREFIX_ALARM_AT_ELAPSED = "alarmAtElapsed."

        /**
         * ตัวนับผลสแกนที่ระบบส่งมาถึงเราจริง — **ต่อ region ต่อรอบการเฝ้าหนึ่งรอบ**
         *
         * มีไว้ตอบคำถามที่ไฟล์ log ตอบไม่ได้: **ระบบส่งผลสแกนมาถี่แค่ไหน** ไฟล์
         * หลักฐานบันทึกเฉพาะตอน "สถานะเปลี่ยน" (enter/exit) ผลสแกนที่เข้ามา
         * ระหว่างที่ยังอยู่ในโซนไม่ทิ้งร่องรอยอะไรเลย — ซึ่งเป็นข้อมูลที่จำเป็นต่อ
         * การตีความว่า exit ที่มาช้าเกิดจาก "ระบบเลื่อนนาฬิกาปลุก" หรือ
         * "มีผลสแกนเข้ามาเลื่อนหน้าต่างออกไป"
         *
         * วิธีใช้: dump prefs สองครั้งห่างกันตามเวลาที่รู้แน่ แล้วหารส่วนต่าง
         * ```bash
         * adb exec-out run-as com.beaconkit.example \
         *   cat shared_prefs/beacon_kit_android.background.xml | grep sightingCount
         * ```
         *
         * ⚠️ **ไม่ใช่จำนวน advertisement ที่ beacon ส่งออกมา** — เป็นจำนวนครั้งที่
         * **ระบบเลือกจะส่งผลมาถึงเรา** หลังผ่าน batching/duty cycle ของ BT stack
         * แล้ว ห้ามอ่านเป็นอัตราการ advertise ของ K9P
         */
        private const val PREFIX_SIGHTING_COUNT = "sightingCount."

        /**
         * ค่าเริ่มต้นของ "ไม่เห็นกี่วินาทีถึงถือว่าออกจาก region"
         *
         * **ไม่ใช่ค่าที่ยืนยันจากสเปกของแพลตฟอร์ม และห้ามอ้างว่าเป็น** — ตั้งไว้ที่
         * 30 วินาทีเพราะเป็นค่าที่**วัดได้เองจากพฤติกรรมของ iOS** ในการทดสอบข้ามคืน
         * 30-31 ส.ค. 2026 (ADR-11 หัวข้อ 2: 43.5% ของช่วงตกอยู่ในหน้าต่าง 29.5-30.5
         * วินาที) การเริ่มด้วยค่าเดียวกันทำให้ผลของสองแพลตฟอร์ม**เทียบกันได้ตรง ๆ**
         * ในรอบทดสอบแรก แทนที่จะต่างกันเพราะเลือกค่าคนละแบบ
         *
         * ⚠️ **บน Android ค่านี้เป็นของเรา ไม่ใช่ของระบบ** — นี่คือความต่างที่
         * ADR-14 บันทึกไว้เป็นข้อดีที่ตั้งใจใช้: ฝั่ง iOS เราปรับไม่ได้เลย
         * (ADR-11 ค้นแล้วไม่พบเอกสาร Apple ที่ระบุหรือให้ปรับ) ส่วนฝั่งนี้ปรับได้
         * ผ่าน `exitTimeoutSeconds` และควรจูนจากข้อมูลสาขาจริงตาม ADR-11 หัวข้อ 8
         */
        const val DEFAULT_EXIT_TIMEOUT_SECONDS = 30

        /**
         * จำนวน event สูงสุดที่คิวไว้รอ Dart มารับ
         *
         * ต้องมีเพดาน เพราะถ้าผู้ใช้ไม่เปิดแอปเป็นสัปดาห์ คิวจะโตไม่หยุดใน
         * SharedPreferences ซึ่งถูกโหลดทั้งไฟล์เข้าหน่วยความจำทุกครั้งที่เปิด
         * **ทิ้งตัวเก่าสุดก่อน** เพราะ event ล่าสุดมีค่ากับผู้ใช้มากกว่า —
         * และการทิ้งถูกบันทึกเป็น `droppedEvents` ไม่ใช่หายเงียบ
         */
        const val MAX_PENDING_EVENTS = 200
    }

    // ---- รายการ region ที่เฝ้าอยู่ ----

    /**
     * `true` เมื่อแอปสั่งให้เฝ้า region อยู่ และยังไม่ได้สั่งหยุด
     *
     * แยกจาก "รายการ region ว่างหรือไม่" โดยตั้งใจ — ต้องแยก "ผู้ใช้สั่งหยุดแล้ว"
     * ออกจาก "ยังสั่งอยู่แต่ระบบล้างการลงทะเบียนไปเอง (เช่นหลังรีบูต)" ให้ได้
     * ไม่งั้นตัวรับ `BOOT_COMPLETED` จะไม่รู้ว่าควรลงทะเบียนใหม่หรือไม่
     */
    var isActive: Boolean
        get() = prefs.getBoolean(KEY_ACTIVE, false)
        set(value) {
            prefs.edit().putBoolean(KEY_ACTIVE, value).commit()
        }

    var regions: List<BeaconRegionSpec>
        get() = BeaconRegionSpec.listFromJson(prefs.getString(KEY_REGIONS, "[]") ?: "[]")
        set(value) {
            prefs.edit()
                .putString(KEY_REGIONS, BeaconRegionSpec.listToJson(value))
                .commit()
        }

    fun regionFor(identifier: String): BeaconRegionSpec? =
        regions.firstOrNull { it.identifier == identifier }

    /**
     * รายการ region พร้อม **เหตุผลถ้าอ่านค่าที่เก็บไว้ไม่สำเร็จ**
     *
     * [regions] คืน list ว่างในทุกกรณีที่ผิดพลาด ทั้ง "ไม่เคยเขียน / ถูกล้างไปแล้ว"
     * และ "มีค่าอยู่แต่ถอดไม่ออก" — สองอย่างนี้แยกไม่ออกจากอาการภายนอกเลย ทั้งที่
     * แก้คนละทาง ตัวนี้จึงมีไว้ให้เส้นทางที่ **เขียนหลักฐาน** ใช้ ไม่ใช่เส้นทาง
     * ตัดสินใจปกติ (ตรรกะ enter/exit ยังใช้ [regions] ตามเดิม)
     *
     * ไม่มีคีย์ `regions` ในไฟล์เลย = **ว่างจริง** ไม่ใช่อ่านไม่สำเร็จ (เกิดจาก
     * ยังไม่เคยสั่งเฝ้า หรือ [clearAll] ล้างไปแล้ว)
     */
    fun readRegions(): ParsedRegionList {
        val raw = prefs.getString(KEY_REGIONS, null)
            ?: return ParsedRegionList(emptyList(), null)
        return BeaconRegionSpec.listFromJsonReporting(raw)
    }

    var exitTimeoutSeconds: Int
        get() = prefs.getInt(KEY_EXIT_TIMEOUT_SECONDS, DEFAULT_EXIT_TIMEOUT_SECONDS)
        set(value) {
            prefs.edit().putInt(KEY_EXIT_TIMEOUT_SECONDS, value).commit()
        }

    // ---- สถานะเข้า/ออกของแต่ละ region ----

    /**
     * "โทเคนของรอบบูตนี้" — ใช้ตรวจว่าเวลาที่เก็บไว้ยังใช้เทียบได้หรือไม่
     *
     * [SystemClock.elapsedRealtime] นับจาก**ตอนบูต** ค่าที่เก็บไว้ก่อนรีบูตจึงเทียบ
     * กับค่าหลังรีบูตไม่ได้เลย และถ้าเผลอเทียบจะได้ผลว่า "เพิ่งเห็นเมื่อกี้" ทั้งที่
     * ผ่านมาหลายวัน แล้วรายงาน enter/exit ผิดทั้งชุด
     *
     * โทเคนคือเวลาบูตโดยประมาณ (`wallClock - elapsedRealtime`) ซึ่งคงที่ภายในรอบบูต
     * เดียวกัน (ขยับเล็กน้อยตามการปรับนาฬิกา จึงเทียบด้วยความคลาดเคลื่อนที่ยอมได้)
     */
    private fun currentBootToken(): Long =
        System.currentTimeMillis() - SystemClock.elapsedRealtime()

    /** ต่างกันเกินค่านี้ = คนละรอบบูต (เผื่อการปรับนาฬิกาปกติ) */
    private val bootTokenToleranceMillis = 10_000L

    /**
     * `true` ถ้าเวลาแบบ elapsed ที่เก็บไว้มาจากรอบบูตเดียวกับตอนนี้
     *
     * ถ้า `false` ผู้เรียก **ต้องไม่** ใช้ค่า `lastSeenElapsed` ที่เก็บไว้
     */
    fun storedElapsedTimesAreFromThisBoot(): Boolean {
        if (!prefs.contains(KEY_BOOT_TOKEN)) return false
        val stored = prefs.getLong(KEY_BOOT_TOKEN, 0)
        return kotlin.math.abs(stored - currentBootToken()) <= bootTokenToleranceMillis
    }

    fun stampBootToken() {
        prefs.edit().putLong(KEY_BOOT_TOKEN, currentBootToken()).commit()
    }

    fun isInside(identifier: String): Boolean =
        prefs.getBoolean(PREFIX_INSIDE + identifier, false)

    fun lastSeenElapsedMillis(identifier: String): Long =
        prefs.getLong(PREFIX_LAST_SEEN_ELAPSED + identifier, 0L)

    fun lastSeenWallMillis(identifier: String): Long =
        prefs.getLong(PREFIX_LAST_SEEN_WALL + identifier, 0L)

    fun scheduledExitAlarmElapsedMillis(identifier: String): Long =
        prefs.getLong(PREFIX_ALARM_AT_ELAPSED + identifier, 0L)

    /** จำนวนผลสแกนที่ระบบส่งมาถึง region นี้ในรอบการเฝ้าปัจจุบัน — ดู [PREFIX_SIGHTING_COUNT] */
    fun sightingCount(identifier: String): Int =
        prefs.getInt(PREFIX_SIGHTING_COUNT + identifier, 0)

    /**
     * บันทึกทุกอย่างของหนึ่ง region ใน `commit()` เดียว
     *
     * ต้องเป็นการเขียนครั้งเดียว ไม่ใช่หลายครั้งต่อกัน — ระบบฆ่า process ได้ทุกเมื่อ
     * ระหว่างนั้น แล้วสถานะจะเหลือครึ่ง ๆ (เช่น `inside=true` แต่ `lastSeen` ยังเป็น
     * ของเก่า) ซึ่งทำให้ตรรกะ exit คำนวณผิดโดยไม่มีใครรู้
     */
    fun recordSighting(identifier: String, alarmAtElapsedMillis: Long) {
        prefs.edit()
            .putBoolean(PREFIX_INSIDE + identifier, true)
            .putLong(PREFIX_LAST_SEEN_ELAPSED + identifier, SystemClock.elapsedRealtime())
            .putLong(PREFIX_LAST_SEEN_WALL + identifier, System.currentTimeMillis())
            .putLong(PREFIX_ALARM_AT_ELAPSED + identifier, alarmAtElapsedMillis)
            .putLong(KEY_BOOT_TOKEN, currentBootToken())
            // อ่านแล้วบวกหนึ่งใน `edit()` ก้อนเดียวกับที่เหลือ — ต้องอยู่ใน commit
            // เดียวกันด้วยเหตุผลเดียวกับที่ระบุข้างบน ถ้าแยกเป็นอีก commit แล้ว
            // ระบบฆ่า process คั่นกลาง ตัวนับจะไม่ตรงกับสถานะที่มันควรอธิบาย
            //
            // ⚠️ read-modify-write ตัวนี้ **ไม่ atomic ข้าม process** —
            // `SharedPreferences` แบบ `MODE_PRIVATE` ไม่รับประกันเรื่องนั้น
            // (`MODE_MULTI_PROCESS` ถูก deprecate ไปแล้ว) แอปนี้มี process เดียว
            // จึงยอมรับได้ แต่ถ้าวันหนึ่งประกาศ `android:process` แยก ตัวนับนี้
            // จะนับตกได้เงียบ ๆ — เป็นตัวเลขวินิจฉัย ไม่ใช่ค่าที่ตรรกะใดพึ่งพา
            .putInt(
                PREFIX_SIGHTING_COUNT + identifier,
                prefs.getInt(PREFIX_SIGHTING_COUNT + identifier, 0) + 1,
            )
            .commit()
    }

    fun recordExitAlarmScheduled(identifier: String, alarmAtElapsedMillis: Long) {
        prefs.edit()
            .putLong(PREFIX_ALARM_AT_ELAPSED + identifier, alarmAtElapsedMillis)
            .commit()
    }

    fun markOutside(identifier: String) {
        prefs.edit()
            .putBoolean(PREFIX_INSIDE + identifier, false)
            .remove(PREFIX_ALARM_AT_ELAPSED + identifier)
            .commit()
    }

    /**
     * พลิกสถานะเป็น outside **พร้อมกับ** enqueue event ที่จะส่งให้ Dart ใน
     * `commit()` เดียวกัน — ห้ามแยกเป็นสองคอมมิตต่อกัน (ADR-17 หัวข้อ 3.1 ข้อ 3)
     *
     * เส้นทางเดิม (ก่อน ADR-17) เรียก [markOutside] แยกจาก [enqueueEvent] คนละ
     * `commit()` — ถ้าระบบฆ่า process คั่นกลางพอดี สถานะจะพลิกเป็น outside
     * สำเร็จ **แต่ event ไม่เคยถูกบันทึกลงคิวเลย** และเพราะ `isInside` อ่านได้
     * `false` ไปแล้วตั้งแต่คอมมิตแรก ไม่มีทางรู้ย้อนหลังได้อีกว่าเคยมี exit ที่
     * ควรรายงานแต่หายไป — ความเสี่ยงชนิดเดียวกับบั๊กหลักที่ ADR-17 ทั้งฉบับแก้
     * เพียงแต่มาจากคนละสาเหตุ (process ตายกลางคัน ไม่ใช่นาฬิกาปลุกไม่มา)
     *
     * ผู้เรียก: `BackgroundRegionMonitor.emitExitAndMarkOutside` เท่านั้น —
     * ดูคอมเมนต์ของฟังก์ชันนั้นสำหรับลำดับเทียบกับการเขียนไฟล์หลักฐาน
     */
    fun markOutsideAndEnqueueEvent(identifier: String, event: BackgroundRegionStateEvent) {
        prefs.edit()
            .putBoolean(PREFIX_INSIDE + identifier, false)
            .remove(PREFIX_ALARM_AT_ELAPSED + identifier)
            .putString(KEY_PENDING_EVENTS, trimmedPendingEventsJson(event))
            .commit()
    }

    /**
     * ล้างสถานะเข้า/ออกทั้งหมด แต่ **ไม่ล้างคิว event ที่ Dart ยังไม่ได้รับ**
     *
     * ใช้ตอนรีบูต: การลงทะเบียนสแกนหายไปกับการรีบูตแน่นอน (ADR-14 หัวข้อการทดสอบ)
     * สถานะ "อยู่ในโซน" ที่ค้างอยู่จึงไม่มีความหมายอีกต่อไป — ถ้าไม่ล้าง แอปจะคิดว่า
     * ยังอยู่ในโซนตลอดไปและไม่มีวันรายงาน enter อีกเลย ซึ่งเป็นอาการเงียบที่แย่ที่สุด
     */
    fun clearRegionStates() {
        val editor = prefs.edit()
        for (key in prefs.all.keys) {
            if (key.startsWith(PREFIX_INSIDE) ||
                key.startsWith(PREFIX_LAST_SEEN_ELAPSED) ||
                key.startsWith(PREFIX_LAST_SEEN_WALL) ||
                key.startsWith(PREFIX_ALARM_AT_ELAPSED) ||
                // ล้างตัวนับด้วย เพราะมันมีความหมายคู่กับเวลาแบบ elapsed ที่กำลัง
                // ถูกล้างพอดี — ตัวนับที่ข้ามรอบบูตมาจะทำให้คนที่หารหาอัตราได้
                // ตัวเลขที่ผสมสองรอบเข้าด้วยกันโดยไม่รู้ตัว
                key.startsWith(PREFIX_SIGHTING_COUNT)
            ) {
                editor.remove(key)
            }
        }
        editor.commit()
    }

    // ---- คิว event ที่รอส่งให้ Dart ----

    /**
     * event ที่เกิดตอนไม่มี Flutter engine ต้องถูกเก็บไว้ ไม่ใช่ทิ้ง
     *
     * นี่คือความต่างที่ทำให้เส้นทางเบื้องหลังของ Android ยากกว่าฝั่ง iOS: บน iOS
     * host app เริ่ม CoreLocation ได้ตั้งแต่ `didFinishLaunchingWithOptions`
     * (ADR-10) แล้ว event ที่ระบบคิวไว้จะไหลเข้ามาเอง ส่วนฝั่งนี้ระบบไม่ได้คิวอะไร
     * ให้เลย — **เราคิวเอง** ไม่งั้น event ที่เกิดตอนแอปปิดจะหายทั้งหมดและผู้ใช้ SDK
     * จะไม่มีทางรู้ว่าเคยมี
     */
    fun enqueueEvent(event: BackgroundRegionStateEvent) {
        prefs.edit().putString(KEY_PENDING_EVENTS, trimmedPendingEventsJson(event)).commit()
    }

    /**
     * อ่านคิวเดิม + ต่อท้ายด้วย [event] + ตัดหัวทิ้งถ้าเกินเพดาน — **คืนสตริง
     * เฉยๆ ไม่คอมมิต** เพื่อให้ผู้เรียกเอาไปใส่ใน `Editor` ก้อนเดียวกับการเขียน
     * อย่างอื่นได้ (ดู [markOutsideAndEnqueueEvent]) แยกออกมาเป็นฟังก์ชันเดียว
     * เพื่อไม่ให้ตรรกะการตัดหัวคิว (ตัวเก่าสุดออกก่อน) มีสองชุดที่อาจเพี้ยนไป
     * คนละทาง
     */
    private fun trimmedPendingEventsJson(event: BackgroundRegionStateEvent): String {
        val array = runCatching {
            JSONArray(prefs.getString(KEY_PENDING_EVENTS, "[]") ?: "[]")
        }.getOrElse { JSONArray() }

        array.put(event.toJson())

        // ตัดหัวทิ้งเมื่อเกินเพดาน — ตัวเก่าสุดออกก่อน
        val trimmed = if (array.length() > MAX_PENDING_EVENTS) {
            JSONArray().also { out ->
                for (i in (array.length() - MAX_PENDING_EVENTS) until array.length()) {
                    out.put(array.get(i))
                }
            }
        } else {
            array
        }

        return trimmed.toString()
    }

    /** อ่านคิวแล้วล้างทิ้งใน `commit()` เดียว — ผู้เรียกต้องส่งต่อให้ครบ */
    fun drainPendingEvents(): List<BackgroundRegionStateEvent> {
        val raw = prefs.getString(KEY_PENDING_EVENTS, "[]") ?: "[]"
        prefs.edit().remove(KEY_PENDING_EVENTS).commit()
        val array = runCatching { JSONArray(raw) }.getOrElse { return emptyList() }
        return (0 until array.length()).mapNotNull { index ->
            array.optJSONObject(index)?.let(BackgroundRegionStateEvent::fromJson)
        }
    }

    fun pendingEventCount(): Int {
        val raw = prefs.getString(KEY_PENDING_EVENTS, "[]") ?: "[]"
        return runCatching { JSONArray(raw).length() }.getOrDefault(0)
    }

    /** ล้างทุกอย่าง — ใช้ตอนแอปสั่ง `stopBackgroundRegionMonitoring` */
    fun clearAll() {
        prefs.edit().clear().commit()
    }
}

/**
 * event เข้า/ออก region ที่คำนวณได้ฝั่ง Android
 *
 * ⚠️ **ไม่ใช่ `IBeaconRegionStateEvent` ของ iOS และห้ามทำให้ดูเหมือนเป็นตัวเดียวกัน**
 * ฝั่ง iOS ค่านี้มาจาก CoreLocation ที่ระบบคำนวณให้ ส่วนฝั่งนี้ **เราคำนวณเอง**
 * จากการเห็น/ไม่เห็นผลสแกน ความเชื่อถือได้จึงคนละระดับ — ADR-14 หัวข้อ 3
 */
data class BackgroundRegionStateEvent(
    val regionIdentifier: String,
    /** `enter` หรือ `exit` — ไม่มี `unknown` เพราะเราไม่มี "determine state" ให้ถาม */
    val state: String,
    val timestampMillis: Long,
    /**
     * `true` เมื่อ event นี้เกิดตอนที่ process ยังไม่เคยมี UI เลย
     *
     * เก็บไว้กับตัว event เพราะถ้ารอไปสรุปตอน Dart มารับ จะสายเกินไป — ตอนนั้น
     * ผู้ใช้เปิดแอปแล้วและบริบทเปลี่ยนไปแล้ว
     */
    val fromBackgroundProcess: Boolean,

    /**
     * ที่มาของ exit นี้ — มีความหมายเฉพาะ `state == "exit"` (ADR-17 หัวข้อ 4)
     *
     * ค่าที่เป็นไปได้:
     * - `alarm` — `onExitAlarm` ตัดสินตามปกติ (นาฬิกาปลุกดัง เช็คซ้ำแล้วครบเวลาจริง)
     * - `staleReconcile` — `BackgroundRegionMonitor.reconcile()` พบว่าเงียบนาน
     *   เกิน K เท่าของ `exitTimeoutSeconds` ทั้งที่นาฬิกาปลุกยังไม่ดัง (เช่น
     *   ถูก Doze/App Standby bucket ระงับไว้)
     * - `staleBootMismatch` — เทียบเวลาข้ามรอบบูตไม่ได้ (`elapsedRealtime`
     *   ที่เก็บไว้มาจากคนละรอบบูต) — เกิดได้ทั้งจาก `onExitAlarm` เองหรือจาก
     *   `reconcile()` เพราะทั้งสองเส้นทางเจอเงื่อนไขเดียวกันเป๊ะ
     *
     * ค่าเริ่มต้น `"alarm"` **ไม่ใช่ปล่อยว่างหรือ nullable** เพื่อให้บรรทัดเก่า
     * (ก่อน ADR-17 ที่ยังไม่มีคีย์ `exitReason=` ในไฟล์เลย) แยกออกจากบรรทัดใหม่
     * ได้ด้วยการเช็ค "มีคีย์นี้หรือไม่" ล้วนๆ โดยไม่ต้องเดา — ตรงกับรูปแบบ `n/a`
     * ที่ [exitSinceLastSeenMillis] ใช้อยู่แล้วสำหรับสาขา boot-mismatch เดิม
     * ค่านี้ไม่ถูกเขียนออกไฟล์หลักฐานสำหรับ event ที่ `state` ไม่ใช่ `"exit"`
     * (ดู `ExampleApplication.exitTimingSuffix` ฝั่ง example app)
     */
    val exitReason: String = "alarm",

    /**
     * `now - lastSeenElapsed` **ณ วินาทีที่ตัดสินใจประกาศ exit** — มีเฉพาะ
     * `state == "exit"` · `null` = ตอบไม่ได้
     *
     * ## ทำไมต้องเก็บ ทั้งที่รู้ `exitTimeoutSeconds` อยู่แล้ว
     *
     * รอบทดสอบ 1 ก.ย. 2026 เจอ exit หน่วง 22 วินาที กับ 3 นาที 15 วินาที
     * **ด้วย `exitTimeoutSeconds=30` เท่ากันทั้งคู่** ซึ่งแยกไม่ออกเลยจากไฟล์ log
     * ว่าเป็นเพราะ (ก) ระบบเลื่อนนาฬิกาปลุกออกไป หรือ (ข) มีผลสแกนเข้ามาเลื่อน
     * หน้าต่างออกไป — สองสาเหตุนี้แก้คนละทางโดยสิ้นเชิง
     *
     * ค่านี้ตอบข้อ (ข) ได้ทันทีจากบรรทัดเดียว: มันคือ **หน้าต่างที่ได้จริง**
     * ถ้ามันโตกว่า `exitTimeoutSeconds` มาก แปลว่าเวลาที่นาฬิกาปลุกได้ดังจริง
     * ห่างจาก `lastSeen` ไปไกลแล้ว
     *
     * `null` เมื่อเทียบเวลาข้ามรอบบูตไม่ได้ — **ห้ามเติม 0 หรือ -1 แทน** เพราะ
     * ตัวเลขปลอมในไฟล์หลักฐานอันตรายกว่าช่องว่าง
     */
    val exitSinceLastSeenMillis: Long? = null,

    /**
     * เวลาที่**เราขอ**ให้นาฬิกาปลุกดัง (`SystemClock.elapsedRealtime`) — มีเฉพาะ exit
     *
     * คู่กับ [exitFiredAtElapsedMillis] · **ผลต่างของสองค่านี้คือระยะที่ระบบเลื่อน
     * นาฬิกาปลุกออกไป วัดตรง ๆ ไม่ต้องอนุมาน** ซึ่งจำเป็นเพราะ
     * `setAndAllowWhileIdle` ระบุไว้เองว่าเวลาที่ส่งเข้าไปเป็นค่า **inexact**
     * (ดู `docs/sources/android_background_ble.md` หัวข้อ 8)
     *
     * เก็บ**ค่าดิบทั้งสองตัว ไม่เก็บผลต่าง** ตามหลักเดียวกับคอลัมน์สัญญาณดิบ:
     * ถ้าวันหนึ่งพบว่าวิธีคิดผลต่างของเราผิด ค่าดิบยังตรวจย้อนกลับได้
     */
    val exitScheduledAtElapsedMillis: Long? = null,

    /** เวลาที่นาฬิกาปลุก **ดังจริง** — คู่กับ [exitScheduledAtElapsedMillis] */
    val exitFiredAtElapsedMillis: Long? = null,

    /**
     * เหตุผลที่ `onExitAlarm` เลื่อนนาฬิกาปลุกแทนการประกาศ exit (หรือ return
     * เฉยๆ โดยไม่ทำอะไรเลย) — มีความหมายเฉพาะ `state == "exitAlarmDeferred"`
     * เท่านั้น (ADR-17 หัวข้อ 6) ค่าที่เป็นไปได้: `stillSeen` (เห็นอีกครั้งก่อน
     * ครบเวลาจริง) · `notInside` (region นี้ไม่ได้อยู่ในสถานะ inside อยู่แล้ว)
     * · `notActive` (การเฝ้าเบื้องหลังถูกสั่งหยุดไปแล้ว)
     *
     * ต่างจาก [exitReason] ตรงที่ **ไม่มีค่าเริ่มต้น** เพราะ event ชนิดนี้ไม่
     * เคยไหลผ่านคิว/JSON เลย (ดู `BackgroundRegionMonitor.emitExitAlarmDeferred`
     * — ตั้งใจไม่ enqueue) จึงไม่มีปัญหาบรรทัดเก่าที่ไม่มีคีย์นี้ต้องเผื่อ
     */
    val deferReason: String? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("regionIdentifier", regionIdentifier)
        put("state", state)
        put("timestampMillis", timestampMillis)
        put("fromBackgroundProcess", fromBackgroundProcess)
        put("exitReason", exitReason)
        // `JSONObject.put(String, Any?)` เก็บ null เป็น "ไม่มีคีย์" ให้เอง จึงไม่
        // ต้องแยกสาขา และฝั่งอ่านใช้ `has()` แยก "ไม่มีค่า" ออกจาก "ค่าเป็น 0" ได้
        put("exitSinceLastSeenMillis", exitSinceLastSeenMillis)
        put("exitScheduledAtElapsedMillis", exitScheduledAtElapsedMillis)
        put("exitFiredAtElapsedMillis", exitFiredAtElapsedMillis)
        put("deferReason", deferReason)
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "regionIdentifier" to regionIdentifier,
        "state" to state,
        "timestampMillis" to timestampMillis,
        "fromBackgroundProcess" to fromBackgroundProcess,
        "exitReason" to exitReason,
        "exitSinceLastSeenMillis" to exitSinceLastSeenMillis,
        "exitScheduledAtElapsedMillis" to exitScheduledAtElapsedMillis,
        "exitFiredAtElapsedMillis" to exitFiredAtElapsedMillis,
        "deferReason" to deferReason,
    )

    companion object {
        fun fromJson(json: JSONObject): BackgroundRegionStateEvent? {
            val identifier = json.optString("regionIdentifier")
            val state = json.optString("state")
            if (identifier.isEmpty() || state.isEmpty()) return null
            return BackgroundRegionStateEvent(
                regionIdentifier = identifier,
                state = state,
                timestampMillis = json.optLong("timestampMillis"),
                fromBackgroundProcess = json.optBoolean("fromBackgroundProcess"),
                // ไม่มีคีย์นี้ (event ที่คิวไว้ก่อนมี ADR-17) = ค่าเริ่มต้นเดียวกับ
                // ที่ constructor ตั้งไว้อยู่แล้ว `optString(key, default)` ทำสิ่ง
                // นี้ให้ตรงๆ โดยไม่ต้องแยกสาขา
                exitReason = json.optString("exitReason", "alarm"),
                // `optLong` คืน 0 เมื่อไม่มีคีย์ ซึ่งแยกจาก "ค่าเป็น 0 จริง" ไม่ได้
                // — event ที่คิวไว้ตอนแอปปิดต้องกลับมาเป็นค่าเดิมเป๊ะ ไม่ใช่ 0 ปลอม
                exitSinceLastSeenMillis = json.optLongOrNull("exitSinceLastSeenMillis"),
                exitScheduledAtElapsedMillis =
                    json.optLongOrNull("exitScheduledAtElapsedMillis"),
                exitFiredAtElapsedMillis = json.optLongOrNull("exitFiredAtElapsedMillis"),
                deferReason = json.optStringOrNull("deferReason"),
            )
        }

        private fun JSONObject.optLongOrNull(key: String): Long? =
            if (has(key) && !isNull(key)) optLong(key) else null

        private fun JSONObject.optStringOrNull(key: String): String? =
            if (has(key) && !isNull(key)) optString(key) else null
    }
}
