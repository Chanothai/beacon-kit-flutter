package com.bigc.beacon_kit_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * รับนาฬิกาปลุกที่ตั้งไว้เพื่อประกาศ "ออกจาก region"
 *
 * ## ทำไมต้องมีตัวนี้เลย — จุดที่ต่างจาก iOS โดยพื้นฐานที่สุด
 *
 * ฝั่ง iOS ไม่มีอะไรเทียบเท่าไฟล์นี้ เพราะ CoreLocation ยิง `didExitRegion` ให้เอง
 * ฝั่ง Android **ระบบไม่เคยบอกว่าเราออกจากโซนแล้ว** มันบอกได้อย่างเดียวว่า "เจอ
 * advertisement" การไม่เจอไม่ใช่ event — มันคือความเงียบ และไม่มีใครส่ง broadcast
 * มาบอกว่า "ตอนนี้เงียบนะ"
 *
 * นาฬิกาปลุกจึงเป็นวิธีเดียวที่จะ **แปลงความเงียบให้เป็น event ได้** โดยไม่ต้องมี
 * process รันค้างไว้คอยนับเวลา (ซึ่งเป็นสิ่งที่ระบบพยายามกำจัดอยู่แล้ว)
 *
 * ดู [BackgroundRegionMonitor.onExitAlarm] สำหรับเหตุผลที่ต้องตรวจซ้ำก่อนประกาศ
 */
class RegionExitAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val regionIdentifier =
            intent.getStringExtra(BackgroundRegionMonitor.EXTRA_REGION_IDENTIFIER)
                ?: return
        // ADR-17 หัวข้อ 3: ตรวจ**ทุก** region ไม่ใช่แค่ตัวที่ทำให้นาฬิกาปลุกดัง
        // — ใช้จังหวะที่ process ถูกปลุกอยู่แล้ว (แม้จะปลุกเพื่อ region อื่น)
        // ตรวจ region ที่เหลือไปด้วยในคราวเดียว สำคัญเพราะถ้าเฝ้าสอง region
        // พร้อมกันและนาฬิกาปลุกของอันหนึ่งยังทำงานปกติแต่ของอีกอันถูกระงับ
        // (Doze/App Standby) อันที่ถูกระงับจะไม่มีทาง reconcile ได้เลยถ้าไม่
        // อาศัยจังหวะที่อีกอันปลุก process ขึ้นมา
        BackgroundRegionMonitor.reconcile(context)
        BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)
    }
}
