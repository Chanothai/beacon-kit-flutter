package com.bigc.beacon_kit_android

import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * รับผลสแกนที่ระบบส่งมาผ่าน `PendingIntent`
 *
 * **นี่คือจุดที่ process อาจถูกสร้างขึ้นมาใหม่ทั้งตัวเพื่อ callback นี้ตัวเดียว** —
 * `BluetoothLeScanner.java:175-177` ระบุจุดประสงค์ของ API นี้ไว้ว่า "Use this method
 * of scanning if your process is not always running and it should be started when
 * scan results are available."
 *
 * ข้อจำกัดที่ตามมาและเป็นเหตุผลของทุกการตัดสินใจในไฟล์นี้:
 * - **ไม่มี Flutter engine** อย่าเรียกอะไรที่พึ่ง engine
 * - **ไม่มี Activity** อย่าเรียกอะไรที่ต้องการ Activity context
 * - **`onReceive` ต้องจบเร็ว และงานทุกอย่างต้องเสร็จก่อนคืนค่า** ระบบถือว่า process
 *   ทิ้งได้ทันทีที่เมธอดนี้คืน — ห้ามโยนงานไป thread อื่นแล้วหวังว่ามันจะได้รัน
 */
class BeaconScanReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val regionIdentifier =
            intent.getStringExtra(BackgroundRegionMonitor.EXTRA_REGION_IDENTIFIER)
                ?: return

        // ถ้า extras ของผลสแกนไม่มาด้วย แปลว่า PendingIntent ถูกสร้างเป็น
        // FLAG_IMMUTABLE ซึ่งทำให้ระบบ "ส่ง broadcast ได้ แต่ผลสแกนหายไปทั้งก้อน"
        // (PendingIntent.java:917-919) — เป็นความล้มเหลวแบบเงียบที่ ADR-14 บันทึกไว้
        // ตรวจให้เห็นชัดตรงนี้ แทนที่จะปล่อยให้อาการออกมาเป็น "ไม่มี event เลย"
        val errorCode = intent.getIntExtra(BluetoothLeScanner.EXTRA_ERROR_CODE, -1)
        if (errorCode != -1) {
            // ระบบแจ้งว่าสแกนล้มเหลว — ไม่ใช่การพบ beacon จึงไม่นับเป็นการเห็น
            // ยังไม่มีช่องทางรายงาน error ของเส้นทางเบื้องหลังไปถึงผู้ใช้ SDK
            // (บันทึกเป็นหนี้ใน ADR-14) แต่ต้อง **ไม่** ตีความว่าเป็น sighting
            return
        }

        val results = scanResultsFrom(intent)
        if (results.isEmpty()) return

        // ADR-17 หัวข้อ 3: ต้องมาก่อนตรรกะเดิมทั้งหมดของ onSighting — ถ้า
        // reconcile() พบว่า region นี้ (หรือ region อื่นที่กำลังเฝ้าอยู่พร้อมกัน)
        // ค้างสถานะ inside ทั้งที่เงียบไปนานผิดปกติ มันจะพลิก isInside เป็น
        // false ให้ก่อน แล้ว onSighting เดิม (ซึ่งไม่ต้องแก้อะไรเลยแม้แต่บรรทัด
        // เดียว) จะอ่านเจอ wasInside=false เองโดยธรรมชาติ และยิง enter ให้เอง
        // ตามตรรกะที่มีอยู่แล้ว — ผลคือผู้ใช้ SDK ได้ exit(stale) ตามด้วย enter
        // เรียงกัน แทนที่จะถูก onSighting กลืนเงียบเพราะเช็คแค่ wasInside บูลีน
        // ตัวเดียวโดยไม่รู้ว่าความเงียบก่อนหน้านั้นนานแค่ไหน
        BackgroundRegionMonitor.reconcile(context)

        // ใช้เวลาของเครื่องตอนรับ ไม่ใช่ `ScanResult.getTimestampNanos()` ซึ่งเป็น
        // เวลาแบบ elapsed-since-boot ที่แปลงเป็นเวลานาฬิกาได้ไม่ตรงเมื่อ event ถูก
        // คิวไว้นาน — และ log ต้องเทียบกับนาฬิกาข้อมือของผู้ทดสอบได้
        BackgroundRegionMonitor.onSighting(
            context,
            regionIdentifier,
            System.currentTimeMillis(),
        )
    }

    /**
     * ดึงรายการ `ScanResult` ออกจาก Intent
     *
     * `getParcelableArrayListExtra(String)` ถูก deprecate ตั้งแต่ API 33 และแทนที่
     * ด้วยเวอร์ชันที่รับ `Class` — แยกสองทางตาม API level แทนการกด `@Suppress`
     * ทิ้งไว้ทั้งเมธอด เพราะเครื่องที่ target สูงขึ้นในอนาคตต้องเดินทางที่ถูก
     */
    private fun scanResultsFrom(intent: Intent): List<ScanResult> {
        val key = BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(key, ScanResult::class.java) ?: emptyList()
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<ScanResult>(key) ?: emptyList()
        }
    }
}
