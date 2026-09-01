package com.beaconkit.example

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/**
 * ตัวเขียนไฟล์หลักฐานฝั่ง Android — **อยู่ใน example app เท่านั้น**
 *
 * เป็นคู่แฝดของ `ios/Runner/BackgroundEvidenceLog.swift` โดยตั้งใจ: รูปแบบบรรทัด
 * เหมือนกันเป๊ะ เพื่อให้ `tool/analyze_region_log.dart` ตัวเดียวอ่านผลของทั้งสอง
 * แพลตฟอร์มได้ — ถ้ารูปแบบต่างกัน การ "เทียบ Android กับ iOS" จะกลายเป็นการเทียบ
 * ตัวเลขที่คำนวณคนละวิธี ซึ่งไม่ใช่การเทียบ
 *
 * ## ทำไมต้องเป็นโค้ด native ล้วน ไม่ผ่าน Dart
 *
 * บทเรียนตรงจาก ADR-10 ฝั่ง iOS: เส้นทาง log เดิมวิ่งผ่าน Dart ทั้งหมด ซึ่งต้องมี
 * Flutter engine ทำงานอยู่ก่อน ตอน OS ปลุก process ขึ้นมาเบื้องหลังโดยไม่มี UI
 * เงื่อนไขนั้นไม่เป็นจริง **เครื่องมือวัดจึงตายพร้อมกับสิ่งที่มันควรวัด** และผลลัพธ์
 * คือ "ไม่มีบรรทัดใน log เลย" ซึ่งแยกไม่ออกระหว่าง "ไม่ถูกปลุก" กับ "ปลุกแล้วแต่
 * event หาย"
 *
 * บน Android เงื่อนไขนี้รุนแรงกว่าอีก เพราะ `BroadcastReceiver` ที่รับผลสแกนจาก
 * `PendingIntent` ถูกเรียกใน process ที่ **เพิ่งถูกสร้างขึ้นมาเพื่องานนี้โดยเฉพาะ**
 * ไม่มี `Activity` ไม่มี `FlutterEngine` และไม่มีอะไรเลยนอกจาก `Application`
 * ออบเจ็กต์นี้จึงพึ่งได้แค่ `android.*` ล้วน — ไม่ import Flutter สักบรรทัด
 *
 * ## ยังไม่ใช่หลักฐานว่าอะไรผ่าน
 *
 * การมีเครื่องมือวัดที่ทำงานได้ กับการเห็นแอปถูกปลุกจริงบนอุปกรณ์จริง เป็นคนละเรื่อง
 */
object BackgroundEvidenceLog {

    const val FILE_NAME = "region_events.log"

    /**
     * **ตัวระบุ process** — สุ่มใหม่ทุกครั้งที่ process เริ่ม เขียนลงทุกบรรทัด
     *
     * `object` ของ Kotlin ถูก initialize ครั้งเดียวต่อ ClassLoader ซึ่งอายุเท่ากับ
     * process — ค่านี้จึงคงที่ตลอด process และเปลี่ยนแน่นอนเมื่อ process ใหม่เกิด
     *
     * **ปัญหาที่ตัวนี้แก้:** ก่อนหน้านี้ (ทั้งสองแพลตฟอร์ม) การตอบว่า "บรรทัดนี้มา
     * จาก process ใหม่หรือ process เดิม" ทำได้ทางเดียวคือ **เดาจาก `uptime`** ซึ่ง
     * ผิดได้สองทาง: process เก่าที่ถูกปลุกอีกครั้งมี uptime สูงทั้งที่ไม่ใช่ของใหม่
     * และ process ใหม่ที่ส่ง event ช้าก็มี uptime สูงเช่นกัน
     *
     * ค่านี้ตอบได้แน่นอน: **สองบรรทัดที่ `processId` ต่างกัน มาจากคนละ process เสมอ**
     *
     * ⚠️ บน Android หนึ่งแอปมีได้หลาย process พร้อมกัน (ถ้าประกาศ
     * `android:process` ใน manifest) — ค่านี้แยกได้ถูกต้องเพราะเป็นค่าต่อ process
     * ไม่ใช่ต่อแอป ส่วน `pid` ของ Linux (`Process.myPid()`) ถูกนำกลับมาใช้ซ้ำได้
     * หลัง process ตาย จึงไม่เหมาะเป็นตัวระบุ แต่เก็บไว้ในสัญญาณดิบเพื่อเทียบกับ
     * `logcat`/`dumpsys` ตอนดีบัก
     */
    val processId: String = UUID.randomUUID().toString().take(8).lowercase()

    /** `null` = การเขียนครั้งล่าสุดสำเร็จ */
    @Volatile
    var lastError: String? = null
        private set

    /**
     * `SimpleDateFormat` ไม่ thread-safe และ log ถูกเขียนได้จากหลาย thread
     * (BroadcastReceiver, main thread, alarm) — จึงต้องเป็น `ThreadLocal`
     *
     * `Locale.US` บังคับปฏิทินเกรกอเรียนและตัวเลขอารบิก ด้วยเหตุผลเดียวกับที่ฝั่ง
     * iOS ต้องตั้ง `en_US_POSIX`: เครื่องที่ตั้งปฏิทินพุทธ (พบทั่วไปในไทย และ MIUI
     * ตั้งง่ายมาก) จะได้ปี 2569 ใน log ทำให้เทียบเวลากับ log ฝั่ง iOS ไม่ได้เลย
     *
     * รูปแบบ `XXX` = offset แบบ `+07:00` ตรงกับ `XXXXX` ของ `DateFormatter` ฝั่ง
     * iOS (ทั้งคู่ให้ `+07:00` ไม่ใช่ `+0700`)
     */
    private val formatter = ThreadLocal.withInitial {
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US)
    }

    /**
     * ต้องตั้ง `timeZone` **ทุกครั้งก่อน format** ห้ามพึ่งค่าที่ติดมาตอนสร้าง
     *
     * **บั๊กจริงที่ CI จับได้ (1 ก.ย. 2026) — ไม่ใช่แค่เรื่องของเทสต์:**
     * `SimpleDateFormat` จับ default TimeZone ไว้ตั้งแต่ตอน **construct** และ
     * formatter ตัวนี้ถูก cache ไว้ใน `ThreadLocal` ตลอดอายุ process ผลคือ
     *
     * 1. แต่ละเธรด (BroadcastReceiver / main / นาฬิกาปลุก) สร้าง formatter ของ
     *    ตัวเองคนละเวลา — ถ้าเขตเวลาของเครื่องเปลี่ยนระหว่างนั้น **บรรทัดในไฟล์
     *    เดียวกันจะมี offset ไม่ตรงกัน**
     * 2. เธรดที่สร้าง formatter ไปแล้วจะใช้ offset เดิมตลอดไป แม้ผู้ใช้เปลี่ยน
     *    เขตเวลาของเครื่อง
     *
     * ทั้งสองข้อทำให้ไฟล์หลักฐานเชื่อถือไม่ได้แบบเงียบ ๆ ซึ่งร้ายแรงเป็นพิเศษกับ
     * เส้นทางนี้ เพราะ process ถูกออกแบบให้มีชีวิตข้ามคืนและจุดประสงค์ทั้งหมดของ
     * คอลัมน์เวลาคือให้ผู้ทดสอบเทียบกับนาฬิกาข้อมือได้
     *
     * **ไม่ได้เจอบนเครื่องพัฒนาเลย** เพราะเครื่องตั้งเป็น `Asia/Bangkok` อยู่แล้ว
     * ค่าที่ติดมาตอนสร้างจึงบังเอิญถูกเสมอ — เจอก็ต่อเมื่อรันบน runner ที่เป็น UTC
     */
    fun iso8601WithOffset(timestampMillis: Long): String {
        val formatter = formatter.get()!!
        formatter.timeZone = TimeZone.getDefault()
        return formatter.format(Date(timestampMillis))
    }

    /**
     * ประกอบหนึ่งบรรทัด — **pure function** จึงมี unit test คลุมได้จริงโดยไม่ต้อง
     * มีเครื่อง
     *
     * TAB คั่น 6 คอลัมน์ ต้องตรงกับฝั่ง iOS และกับ `EvidenceLogLine` ฝั่ง Dart:
     * ```
     * timestamp(ISO8601+offset) \t processId \t event \t regionIdentifier \t conclusion \t rawSignals
     * ```
     *
     * ห้ามให้ค่าใดมี TAB ปนเข้ามา ไม่งั้นคอลัมน์เลื่อน — ผู้เรียกทุกคนใน repo นี้
     * ส่งค่าที่ไม่มี TAB อยู่แล้ว จึงไม่ escape ให้เปลืองเวลาในเส้นทางที่ระบบให้
     * เวลามาน้อย แต่แทน TAB ด้วยช่องว่างกันไว้เพราะราคาถูกมาก
     */
    fun line(
        timestampMillis: Long,
        processId: String = BackgroundEvidenceLog.processId,
        event: String,
        regionIdentifier: String,
        conclusion: String,
        rawSignals: String,
    ): String = listOf(
        iso8601WithOffset(timestampMillis),
        processId,
        event,
        regionIdentifier,
        conclusion,
        rawSignals,
    ).joinToString("\t") { it.replace('\t', ' ') }

    /**
     * ไฟล์ log — อยู่ใน `filesDir` ของแอป (credential-encrypted storage)
     *
     * **ข้อจำกัดที่ต้องรู้ และตรงกับฝั่ง iOS พอดี:** `filesDir` อยู่ใน storage ที่
     * เข้าถึงไม่ได้จนกว่าผู้ใช้จะปลดล็อกเครื่องครั้งแรกหลังรีบูต ซึ่งเป็นข้อจำกัด
     * เดียวกับ `FileProtectionType.completeUntilFirstUserAuthentication` ที่ฝั่ง iOS
     * เลือกไว้ — **จงใจให้ตรงกัน** เพื่อให้ผลการทดสอบเคส "รีบูตแล้วยังไม่ปลดล็อก"
     * เทียบกันได้ ไม่ใช่ต่างกันเพราะเลือกที่เก็บไฟล์คนละแบบ
     *
     * ทางเลือกที่**ไม่**เลือก: `createDeviceProtectedStorageContext()` ซึ่งเขียนได้
     * ก่อนปลดล็อก — ไม่เลือกเพราะ (ก) component ที่จะรันก่อนปลดล็อกต้องประกาศ
     * `directBootAware` ซึ่งเรายังไม่ได้ทำและยังไม่รู้ว่าต้องทำไหม และ (ข) ไฟล์นี้
     * บันทึกว่าผู้ใช้อยู่ที่ไหนเวลาใด การย้ายไป storage ที่ไม่ผูกกับรหัสผ่านผู้ใช้
     * เป็นการลดระดับการปกป้องข้อมูล ซึ่งต้องมีเหตุผลมากกว่า "สะดวกตอนทดสอบ"
     */
    fun logFile(context: Context): File = File(context.filesDir, FILE_NAME)

    /**
     * ต่อท้ายหนึ่งบรรทัดแบบ **synchronous + fsync**
     *
     * `fd.sync()` จำเป็นด้วยเหตุผลเดียวกับ `synchronize()` ฝั่ง iOS: ระบบอาจฆ่า
     * process ทันทีที่ `onReceive()` คืนค่า ถ้าข้อมูลยังค้างใน page cache จะหาย
     * ทั้งบรรทัด = เสียหลักฐานที่รอมาทั้งรอบทดสอบ
     *
     * `synchronized` เพราะผลสแกนจาก `PendingIntent` มาถึงพร้อมกันได้หลายก้อน
     * ถ้าสองเธรดเขียนพร้อมกันบรรทัดจะปนกันจนอ่านไม่ออก
     *
     * **ห้าม throw** — ผู้เรียกทั้งหมดอยู่ในเส้นทางที่ถ้า crash แล้วจะไม่มีใครรู้
     * ว่าเกิดอะไรขึ้น เก็บ error ไว้ใน [lastError] ให้ฝั่ง Dart ดึงไปแสดงทีหลังแทน
     * (เส้นทางเดียวกับ `getLogWriteError` ฝั่ง iOS)
     */
    @Synchronized
    fun append(context: Context, line: String) {
        try {
            val file = logFile(context)
            file.parentFile?.mkdirs()
            FileOutputStream(file, /* append = */ true).use { out ->
                out.write((line + "\n").toByteArray(Charsets.UTF_8))
                out.flush()
                out.fd.sync()
            }
            lastError = null
        } catch (error: Throwable) {
            lastError = "${error.javaClass.simpleName}: ${error.message}"
        }
    }

    /**
     * สัญญาณดิบชุดมาตรฐานของฝั่ง Android — เก็บ**สิ่งที่ระบบบอก** ไม่ใช่ข้อสรุปของเรา
     *
     * ถ้าวันหนึ่งพบว่าสูตรที่ใช้สรุป [ProcessState.conclusion] ผิด ข้อมูลดิบใน log
     * ยังตรวจย้อนกลับได้โดยไม่ต้องทดสอบใหม่ทั้งรอบ — เหตุผลเดียวกับฝั่ง iOS
     *
     * ความหมายของแต่ละค่า:
     * - `uptime` — อายุของ process นี้ **ใช้ key เดียวกับ iOS โดยตั้งใจ** เพื่อให้
     *   `tool/analyze_region_log.dart` ดึงค่าได้ด้วยโค้ดชุดเดียว
     * - `pid` — pid ของ Linux ไว้เทียบกับ `logcat` ตอนดีบัก (ถูกใช้ซ้ำได้ จึงไม่ใช่
     *   ตัวระบุ process — ตัวระบุจริงอยู่คอลัมน์ที่ 2)
     * - `importance` — ค่าที่ **ระบบ** จัดให้ process นี้ ไม่ใช่ค่าที่เราคำนวณเอง
     * - `doze` — เครื่องอยู่ใน Doze หรือไม่ ณ ตอนเขียนบรรทัด
     * - `battOpt` — แอปถูกยกเว้น battery optimization อยู่หรือไม่
     */
    fun rawSignals(context: Context, state: ProcessState): String {
        val uptimeSeconds =
            (SystemClock.elapsedRealtime() - state.processStartedElapsedMillis) / 1000.0
        return buildString {
            append("everForeground=${state.hasEverBeenForeground}")
            append(" activities=${state.startedActivityCount}")
            append(" state=${state.rawLifecycleState}")
            append(" importance=${importanceName(context)}")
            append(" doze=${isDeviceIdle(context)}")
            append(" battOpt=${batteryOptimizationState(context)}")
            append(" pid=${Process.myPid()}")
            append(" uptime=${String.format(Locale.US, "%.1f", uptimeSeconds)}s")
        }
    }

    /**
     * ความสำคัญของ process ตามที่ **ระบบจัดให้** — สัญญาณอิสระที่ไม่ได้มาจากการ
     * นับ activity ของเราเอง
     *
     * มีค่าเพราะมันแยก `FOREGROUND_SERVICE` ออกจาก `FOREGROUND` และ `BACKGROUND`
     * ได้ ซึ่งเป็นความต่างที่ ADR-14 ต้องรายงานให้ตรง: process ที่รันด้วย
     * foreground service **ไม่ใช่** process ที่อยู่เบื้องหลังจริง ๆ ในสายตาระบบ
     */
    private fun importanceName(context: Context): String {
        val info = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(info)
        return when (info.importance) {
            ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND -> "foreground"
            ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE ->
                "foregroundService"
            ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE -> "visible"
            ActivityManager.RunningAppProcessInfo.IMPORTANCE_PERCEPTIBLE -> "perceptible"
            ActivityManager.RunningAppProcessInfo.IMPORTANCE_SERVICE -> "service"
            ActivityManager.RunningAppProcessInfo.IMPORTANCE_CACHED -> "cached"
            ActivityManager.RunningAppProcessInfo.IMPORTANCE_GONE -> "gone"
            else -> "other(${info.importance})"
        }
    }

    private fun isDeviceIdle(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return power.isDeviceIdleMode
    }

    /**
     * `ignoring` = ผู้ใช้ปลด battery optimization ให้แอปแล้ว
     *
     * บันทึกไว้ทุกบรรทัดเพราะเป็นตัวแปรที่**เปลี่ยนผลการทดสอบได้ทั้งรอบ** — รายงาน
     * ผลที่ไม่ระบุค่านี้ตรวจสอบย้อนกลับไม่ได้ เหมือนกับที่รายงานผลโดยไม่ระบุรุ่น
     * เครื่องตรวจสอบไม่ได้
     */
    private fun batteryOptimizationState(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return "n/a"
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return "unknown"
        return if (power.isIgnoringBatteryOptimizations(context.packageName)) {
            "ignoring"
        } else {
            "optimized"
        }
    }
}
