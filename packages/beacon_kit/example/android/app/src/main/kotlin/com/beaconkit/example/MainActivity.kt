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
}
