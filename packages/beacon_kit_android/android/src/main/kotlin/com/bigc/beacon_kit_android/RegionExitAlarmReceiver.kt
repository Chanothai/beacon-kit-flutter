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
        BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)
    }
}
