package com.beaconkit.example

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

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

    private const val CHANNEL_ID = "beacon_kit_example.region_events"

    /**
     * ID ที่ **ต่างกันทุกครั้ง** เพื่อให้ notification ซ้อนกันได้ ไม่ใช่ทับกัน
     *
     * ถ้าใช้ ID เดิม การเห็น "1 notification" จะแยกไม่ออกระหว่าง "เกิด 1 ครั้ง" กับ
     * "เกิด 50 ครั้งแล้วทับกันหมด" ซึ่งคือความต่างที่รอบทดสอบ region flapping
     * (ADR-11) ต้องการวัดพอดี
     */
    private var nextId = 1

    fun post(context: Context, title: String, body: String) {
        runCatching {
            ensureChannel(context)
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .build()

            // `notify` ต้องการ POST_NOTIFICATIONS ตั้งแต่ Android 13 — เครื่องทดสอบ
            // เป็น Android 12 จึงยังไม่ต้องขอ แต่ห่อ runCatching ไว้เพราะถ้าวันหนึ่ง
            // รันบนเครื่องใหม่กว่าแล้วยังไม่ได้สิทธิ์ **notification หายไปเฉย ๆ ได้
            // แต่ log ต้องไม่พัง** — log คือหลักฐาน notification ไม่ใช่
            NotificationManagerCompat.from(context)
                .notify(synchronized(this) { nextId++ }, notification)
        }
    }

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
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "หลักฐานว่ามี region event เกิดขึ้นตอนแอปไม่ได้เปิดอยู่"
            },
        )
    }
}
