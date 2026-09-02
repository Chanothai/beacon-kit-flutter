package com.beaconkit.example

import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Activity ของ **example app เท่านั้น**
 *
 * ให้บริการ method channel `beacon_kit_example/diagnostics` ชุดเดียวกับที่ฝั่ง iOS
 * ให้จาก `AppDelegate` — **ชื่อเมธอดและรูปร่างคำตอบตรงกันโดยตั้งใจ** เพื่อให้หน้าจอ
 * และตัววิเคราะห์ฝั่ง Dart ใช้โค้ดชุดเดียวกันได้ทั้งสองแพลตฟอร์ม
 *
 * ⚠️ **ทุกอย่างที่ต้องทำงานตอนไม่มี UI อยู่ใน [ExampleApplication] ไม่ใช่ที่นี่** —
 * ไฟล์นี้ถูกสร้างเมื่อมีหน้าจอเท่านั้น การวางเครื่องมือวัดไว้ที่นี่จะทำให้มันทำงาน
 * เฉพาะในเคสที่ไม่ต้องพิสูจน์อะไร ซึ่งเป็นความผิดพลาดเดียวกับที่ ADR-10 แก้ฝั่ง iOS
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "beacon_kit_example/diagnostics",
        ).setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val state = ExampleApplication.processState
        when (call.method) {
            "getLaunchDiagnostics" -> {
                // คืน**สัญญาณดิบทั้งหมด** ไม่ตัดสินใจแทนฝั่ง Dart — เหตุผลเดียวกับ
                // ฝั่ง iOS: ถ้าภายหลังพบว่าวิธีสรุปของเราผิด ข้อมูลดิบยังตรวจ
                // ย้อนกลับได้โดยไม่ต้องทดสอบใหม่ทั้งรอบ
                result.success(
                    mapOf(
                        // ไม่มีอะไรเทียบเท่า UIApplication.LaunchOptionsKey.location
                        // บน Android — ระบบไม่บอกเหตุผลที่สร้าง process ขึ้นมา
                        // ส่งค่าคงที่ false แทนการแกล้งเดา เพื่อไม่ให้ฝั่ง Dart
                        // เอาไปใช้เป็นหลักฐานสนับสนุนทั้งที่ไม่มีข้อมูลจริง
                        "launchedByLocationKey" to false,
                        "hasEverBecomeActive" to state.hasEverBeenForeground,
                        "applicationState" to
                            if (state.rawLifecycleState == "resumed") "active" else "background",
                        "processUptimeSeconds" to
                            (SystemClock.elapsedRealtime() - state.processStartedElapsedMillis) /
                            1000.0,
                        "processId" to BackgroundEvidenceLog.processId,
                    ),
                )
            }

            "prepareLogFile" -> {
                // ฝั่ง Android ไม่มี Data Protection class ให้ตั้ง — `filesDir` ถูก
                // เข้ารหัสด้วย credential-encrypted storage ของระบบอยู่แล้ว และ
                // เข้าถึงไม่ได้จนกว่าผู้ใช้จะปลดล็อกหลังรีบูต ซึ่งตรงกับระดับที่ฝั่ง
                // iOS เลือกไว้พอดี (completeUntilFirstUserAuthentication)
                val file = BackgroundEvidenceLog.logFile(applicationContext)
                runCatching { file.parentFile?.mkdirs() }
                result.success(file.absolutePath)
            }

            "getLogFileProtection" -> {
                // ฝั่ง iOS อ่านค่าจริงจากไฟล์กลับมาได้ ฝั่งนี้ไม่มี API เทียบเท่า
                // จึงคืน**คำอธิบายของสิ่งที่เป็นจริง** ไม่ใช่ค่าปลอมที่ดูเหมือน iOS
                result.success("credentialEncrypted(filesDir) — ไม่มี API ให้อ่านค่ากลับมายืนยัน")
            }

            "getLogWriteError" -> result.success(BackgroundEvidenceLog.lastError)

            "runEvidenceLogSelfTest" -> result.success(evidenceLogSelfTest())

            "requestNotificationAuthorization" -> {
                // Android 12 (เครื่องทดสอบ) ยังไม่มี POST_NOTIFICATIONS ให้ขอ —
                // notification ใช้ได้เลย คืน true ตรงตามความจริงบนเวอร์ชันนี้
                // ⚠️ ต้องแก้เมื่อรันบน Android 13+ ซึ่งต้องขอสิทธิ์จริง
                result.success(android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU)
            }

            "postNotification" -> {
                val title = call.argument<String>("title")
                val body = call.argument<String>("body")
                if (title == null || body == null) {
                    result.error("INVALID_ARGUMENT", "ต้องมี title และ body เป็น String", null)
                } else {
                    ExampleNotifications.post(applicationContext, title, body)
                    result.success(null)
                }
            }

            else -> result.notImplemented()
        }
    }

    /**
     * **พิสูจน์ว่าเครื่องมือวัดทำงานได้ โดยไม่ต้องพึ่ง beacon เลย**
     *
     * เขียนหนึ่งบรรทัดผ่าน [BackgroundEvidenceLog.append] ตัวเดียวกับที่เส้นทาง
     * เบื้องหลังใช้ แล้ว**อ่านไฟล์กลับขึ้นมาจริง ๆ** เทียบว่าบรรทัดนั้นลงดิสก์แล้ว
     *
     * ## ทำไมต้องมี
     *
     * `append()` **ห้าม throw** (ผู้เรียกอยู่ในเส้นทางที่ crash แล้วไม่มีใครรู้)
     * มันจึงเก็บ error ไว้ใน `lastError` เงียบ ๆ ผลคือ "เขียนไฟล์ไม่ได้" กับ
     * "ระบบไม่เคยส่ง event มา" **จบที่อาการเดียวกันเป๊ะ: ไฟล์ log ว่าง** ปุ่มนี้
     * แยกสองกรณีนั้นออกจากกันได้ก่อนเริ่มทดสอบ แทนที่จะไปรู้ตอนเก็บข้อมูลทั้งคืน
     * เสร็จแล้ว ซึ่งเก็บซ้ำไม่ได้
     *
     * ## ทำไมต้องอ่าน `lastError` ก่อนเขียน
     *
     * `append()` ที่สำเร็จจะ **ตั้ง `lastError` กลับเป็น `null`** — ถ้าอ่านหลังเขียน
     * อย่างเดียว error ที่สะสมมาจากรอบเบื้องหลังจะถูกลบทิ้งพร้อมกับหลักฐานว่ามัน
     * เคยเกิด จึงคืนทั้งค่าก่อนและหลังเขียน แล้วให้หน้าจอแสดงทั้งคู่
     *
     * ## ทำไมเขียน `event=selftest` ลงไฟล์จริง ไม่ใช่ไฟล์ชั่วคราว
     *
     * ถ้าเขียนลงไฟล์อื่น มันจะพิสูจน์แค่ว่า "เขียนไฟล์บางไฟล์ได้" ซึ่งไม่ใช่คำถาม
     * — คำถามคือไฟล์ **นี้** path **นี้** เขียนได้ไหม · `selftest` ไม่กวน
     * `tool/analyze_region_log.dart` เพราะตัววิเคราะห์ลำดับข้ามทุก event ที่ไม่ใช่
     * `enter`/`exit` และบรรทัดนี้ยังเป็นหลักฐานมีประโยชน์ด้วยว่า "ตอน HH:MM
     * เครื่องมือวัดยังเขียนได้อยู่"
     */
    private fun evidenceLogSelfTest(): Map<String, Any?> {
        val context = applicationContext
        val state = ExampleApplication.processState

        // ต้องอ่าน**ก่อน** append เสมอ — ดูเหตุผลใน KDoc ข้างบน
        val errorBeforeWrite = BackgroundEvidenceLog.lastError

        val line = BackgroundEvidenceLog.line(
            timestampMillis = System.currentTimeMillis(),
            event = "selftest",
            regionIdentifier = "-",
            conclusion = state.conclusion,
            // receiverEntry = false — บรรทัดนี้เขียนจากปุ่มบน UI ไม่ใช่จาก
            // `onReceive` การใส่ true จะเป็นการโกหกในไฟล์หลักฐาน
            rawSignals = BackgroundEvidenceLog.rawSignals(
                context = context,
                state = state,
                receiverEntry = false,
            ),
        )
        BackgroundEvidenceLog.append(context, line)
        val errorAfterWrite = BackgroundEvidenceLog.lastError

        val file = BackgroundEvidenceLog.logFile(context)
        var readBackLine: String? = null
        var lineCount = 0
        var readError: String? = null
        try {
            if (file.exists()) {
                val lines = file.readLines().filter { it.isNotBlank() }
                lineCount = lines.size
                readBackLine = lines.lastOrNull()
            }
        } catch (error: Throwable) {
            // อ่านไม่ได้เป็นคนละความล้มเหลวกับเขียนไม่ได้ — ต้องรายงานแยกกัน
            readError = "${error.javaClass.simpleName}: ${error.message}"
        }

        return mapOf(
            "path" to file.absolutePath,
            "errorBeforeWrite" to errorBeforeWrite,
            "writtenLine" to line,
            "errorAfterWrite" to errorAfterWrite,
            "fileExists" to file.exists(),
            "fileSizeBytes" to file.length(),
            "lineCount" to lineCount,
            "readBackLine" to readBackLine,
            "readBackMatches" to (readBackLine == line),
            "readError" to readError,
        )
    }
}
