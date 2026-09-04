package com.bigc.beacon_kit_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * ลงทะเบียนการสแกนใหม่หลังเครื่องรีบูต
 *
 * ## ทำไมต้องมี — และทำไมมันไม่ได้ทำให้ Android เท่ากับ iOS
 *
 * ฝั่ง iOS ไม่ต้องมีอะไรแบบนี้: `CLLocationManager.monitoredRegions` เก็บ region
 * ไว้ที่ระดับระบบและอยู่ข้าม launch เอง (ADR-9) แอปแค่มี delegate ให้ทันในรอบ
 * launch ก็พอ
 *
 * ฝั่งนี้การลงทะเบียน `startScan(..., PendingIntent)` อยู่ในหน่วยความจำของ
 * Bluetooth stack ซึ่งหายไปกับการรีบูต **เราจึงต้องลงทะเบียนใหม่เอง** และเราทำได้
 * ก็ต่อเมื่อได้รับ `BOOT_COMPLETED` ซึ่งมีเงื่อนไขของมันเอง:
 *
 * > "This broadcast is sent at boot by all devices... Upon receipt of this broadcast,
 * > the user is unlocked and both device-protected and credential-protected storage
 * > can accessed safely."
 * > — `Intent.java:2818-2821` (`ACTION_BOOT_COMPLETED`)
 *
 * แปลว่า **ระหว่างที่เครื่องบูตแล้วแต่ผู้ใช้ยังไม่ปลดล็อก เราไม่ได้เฝ้าอะไรเลย**
 * ซึ่งเป็นช่องว่างที่โค้ดปิดไม่ได้ ต้องรายงานตรง ๆ ไม่ใช่ปกปิด
 *
 * และแอปที่ถูก **force-stop** จะไม่ได้รับ broadcast นี้ด้วยซ้ำ:
 *
 * > "Stopped applications will not receive implicit broadcasts unless the sender
 * > specifies FLAG_INCLUDE_STOPPED_PACKAGES... An app can also return to the
 * > stopped state by a 'force stop'."
 * > — `ApplicationInfo.java:420-426` (`FLAG_STOPPED`)
 *
 * ## ทำไมไม่เริ่ม foreground service ตรงนี้
 *
 * เริ่มได้ (`BOOT_COMPLETED` อยู่ในรายการข้อยกเว้นของข้อจำกัด "ห้ามเริ่ม FGS จาก
 * เบื้องหลัง" ของ Android 12 และ `connectedDevice` ไม่อยู่ในรายการชนิดที่ Android
 * 15 ห้ามเริ่มจาก `BOOT_COMPLETED`) — **แต่ตั้งใจไม่ทำ** เพราะจะแปลว่าผู้ใช้เห็น
 * notification ค้างตั้งแต่เปิดเครื่องโดยไม่ได้ขอ ดูเหตุผลเต็มใน ADR-14 หัวข้อ 2
 */
class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // ผลลัพธ์ (สำเร็จ/ล้มเหลวราย region) ถูกบันทึกโดยผู้สังเกตการณ์ของ host app
        // ผ่าน BackgroundRegionMonitor — ตรงนี้ไม่มีใครให้รายงานถึง
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_LOCKED_BOOT_COMPLETED ->
                BackgroundRegionMonitor.restoreAfterBoot(context)

            // ADR-17 หัวข้อ 3 — บั๊กแฝงที่พบระหว่างออกแบบ แยกจากบั๊กหลักแต่
            // เกี่ยวเนื่องกันโดยตรง: MY_PACKAGE_REPLACED **ไม่ใช่การรีบูต**
            // `SystemClock.elapsedRealtime()` ไม่รีเซ็ตตอนแอปอัปเดต (boot
            // token ยังตรงกันได้ตามปกติ) เส้นทางเดิมที่เรียก restoreAfterBoot()
            // ตรงๆ (เหมือนสองบรรทัดข้างบน) จะเรียก clearRegionStates() แบบไม่มี
            // เงื่อนไข ซึ่งทิ้งสถานะ inside=true ที่ยังถูกต้องอยู่จริงไปเงียบๆ
            // โดยไม่มีการรายงาน exit เลย — ต้องแยกเป็นเส้นทางของตัวเองที่
            // "ลงทะเบียนสแกนใหม่" (จำเป็นเพราะ Bluetooth stack ทำ registration
            // หายไปกับแอปเวอร์ชันเก่า) โดย**ไม่**ล้างสถานะเข้า/ออกทิ้ง
            Intent.ACTION_MY_PACKAGE_REPLACED ->
                BackgroundRegionMonitor.restoreAfterPackageReplaced(context)

            else -> return
        }
    }
}
