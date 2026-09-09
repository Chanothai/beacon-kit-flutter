package com.beaconkit.example

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * ยิง notification จาก **โค้ด native ล้วน** — ของ example app เท่านั้น
 *
 * คู่ขนานกับ `AppDelegate.postNotification` ฝั่ง iOS มีไว้เพื่อให้ผู้ทดสอบเห็นด้วย
 * ตาว่ามี event เกิดขึ้นตอนไหน โดยไม่ต้องเปิดแอปมาดู log
 *
 * **ยิงหลังเขียน log เสมอ** ตามลำดับเดียวกับฝั่ง iOS — log คือหลักฐานที่ต้องรอด
 * ส่วน notification เป็นแค่สัญญาณให้คนเห็น ถ้าระบบฆ่า process ก่อน อย่างน้อย
 * หลักฐานต้องลงดิสก์แล้ว
 */
object ExampleNotifications {

    /**
     * **`_v2` โดยตั้งใจ ห้ามกลับไปใช้ id เดิม**
     *
     * `NotificationChannel` ที่ถูกสร้างไปแล้วบนเครื่อง **เปลี่ยน importance จากโค้ด
     * ไม่ได้อีกเลย** — `createNotificationChannel()` ที่เรียกซ้ำด้วย id เดิมจะอัปเดต
     * ได้แค่ชื่อกับคำอธิบาย ส่วน importance ระบบถือว่าเป็นของผู้ใช้ตั้งแต่วินาทีที่
     * สร้างครั้งแรก การจะยกระดับจาก `DEFAULT` เป็น `HIGH` (ให้เด้งเป็น heads-up
     * ตอนทดสอบเดินจริง) จึงมีทางเดียวคือ **สร้าง channel ใหม่ที่ id ไม่ซ้ำของเดิม**
     *
     * ผลข้างเคียงที่ยอมรับ: เครื่องที่เคยติดตั้งรุ่นก่อนจะมี channel เก่าค้างอยู่ใน
     * หน้าตั้งค่าจนกว่าจะถอนแอป — ยอมรับได้ในระดับ example app ของ POC
     */
    private const val CHANNEL_ID = "beacon_kit_example.region_events_v2"

    /**
     * ID ที่ **ต่างกันทุกครั้ง** เพื่อให้ notification ซ้อนกันได้ ไม่ใช่ทับกัน
     *
     * ถ้าใช้ ID เดิม การเห็น "1 notification" จะแยกไม่ออกระหว่าง "เกิด 1 ครั้ง" กับ
     * "เกิด 50 ครั้งแล้วทับกันหมด" ซึ่งคือความต่างที่รอบทดสอบ region flapping
     * (ADR-11) ต้องการวัดพอดี
     */
    private var nextId = 1

    /**
     * ยิง notification แล้ว **เขียนบรรทัดหลักฐานว่ายิงขึ้นจริงหรือไม่ทุกครั้ง**
     *
     * ## ทำไมต้องเขียน log ว่ายิงไม่ขึ้น
     *
     * เดิมเมธอดนี้ห่อ `runCatching` แล้วกลืนทุกอย่างเงียบ ๆ ซึ่งทำให้
     * "ระบบบล็อก notification" กับ "ไม่มี event เกิดขึ้นเลย" **จบที่อาการเดียวกัน
     * เป๊ะ: ไม่มีอะไรเด้ง** — เสียเวลาไปทั้งรอบทดสอบ 9 ก.ย. 2026 กว่าจะรู้ว่าเครื่อง
     * ปิด notification ไว้ (ต้องไปอ่าน `dumpsys notification` ถึงเห็น `numBlocked`)
     * บรรทัด `event=notification` ตอบคำถามนี้ได้จากไฟล์หลักฐานโดยตรง
     *
     * `reason` แยกสามสาเหตุที่**แก้คนละทางกันโดยสิ้นเชิง**:
     * - `permissionDenied` — Android 13+ ยังไม่ได้ runtime permission → แอปต้องขอเอง
     * - `blockedByUser` — ผู้ใช้/ผู้ผลิตปิดสวิตช์หลักของแอป → ต้องไปเปิดในหน้าตั้งค่า
     * - `channelBlocked` — สวิตช์หลักเปิด แต่ channel นี้ถูกปิดแยก → เปิดที่ channel
     *
     * **เขียน log ก่อน `notify()` เสมอ** ตามหลักการเดียวกับที่เหลือของไฟล์หลักฐาน:
     * log คือสิ่งที่ต้องรอด notification เป็นแค่สัญญาณให้คนเห็น
     */
    fun post(context: Context, title: String, body: String) {
        runCatching {
            ensureChannel(context)
            val id = synchronized(this) { nextId++ }
            val reason = deliveryReason(context)

            BackgroundEvidenceLog.append(
                context,
                BackgroundEvidenceLog.line(
                    timestampMillis = System.currentTimeMillis(),
                    event = "notification",
                    // ไม่มี region ผูกกับบรรทัดนี้ — ใช้ `-` แบบเดียวกับบรรทัด
                    // `launch`/`selftest` ห้ามเดาชื่อ region จากข้อความ title
                    regionIdentifier = "-",
                    conclusion = ExampleApplication.processState.conclusion,
                    rawSignals = BackgroundEvidenceLog.rawSignals(
                        context = context,
                        state = ExampleApplication.processState,
                        // ยิงได้จากทั้ง observer ในเส้นทาง receiver และจากปุ่มบน UI
                        // — ไม่อ้างว่ามาจาก receiver เพราะพิสูจน์จากตรงนี้ไม่ได้
                        receiverEntry = false,
                    ) + " posted=${reason == REASON_GRANTED} reason=$reason id=$id",
                ),
            )

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                // ต้อง HIGH ให้ตรงกับ importance ของ channel ไม่งั้นบนเครื่องที่
                // API < 26 (ไม่มี channel) จะได้พฤติกรรมคนละอย่างกับเครื่องใหม่
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()

            NotificationManagerCompat.from(context).notify(id, notification)
        }
    }

    /**
     * ตรวจว่า notification จะขึ้นจริงหรือไม่ **ก่อน** เรียก `notify()`
     *
     * `notify()` ไม่เคย throw และไม่คืนค่าอะไรเลยเมื่อถูกบล็อก — ต้องถามระบบเอง
     * ทีละชั้น และ **ลำดับสำคัญ**: บน API 33+ `areNotificationsEnabled()` คืน
     * `false` ทั้งกรณีไม่ได้ permission และกรณีผู้ใช้ปิดสวิตช์ ถ้าไม่เช็ค
     * permission ก่อน สองสาเหตุนี้จะถูกรายงานปนกันเป็น `blockedByUser` ทั้งคู่
     * ทั้งที่แก้คนละทาง
     */
    private fun deliveryReason(context: Context): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) return "permissionDenied"
        }

        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            return "blockedByUser"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            val channel = manager?.getNotificationChannel(CHANNEL_ID)
            if (channel != null && channel.importance == NotificationManager.IMPORTANCE_NONE) {
                return "channelBlocked"
            }
        }

        return REASON_GRANTED
    }

    private const val REASON_GRANTED = "granted"

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Region enter/exit",
                // HIGH ไม่ใช่ DEFAULT — ผู้ทดสอบต้องเห็น heads-up ขณะเดินถือมือถือ
                // อยู่ในมือ ไม่ใช่ต้องดึงแถบแจ้งเตือนลงมาดูเอง (ค่านี้ล็อกได้เฉพาะ
                // ตอนสร้าง channel ครั้งแรก — ดูเหตุผลของ `_v2` ที่ CHANNEL_ID)
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "หลักฐานว่ามี region event เกิดขึ้นตอนแอปไม่ได้เปิดอยู่"
            },
        )
    }
}
