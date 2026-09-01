package com.beaconkit.example

import android.app.Application
import com.bigc.beacon_kit_android.BackgroundRegionMonitor

/**
 * `Application` ของ **example app เท่านั้น** — โค้ดในไฟล์นี้จงใจไม่อยู่ใน
 * `beacon_kit_android` เพราะ SDK ไม่ควรบังคับให้ผู้ใช้ต้องมี `Application`
 * subclass หรือใช้รูปแบบการเก็บ log แบบใดแบบหนึ่ง
 *
 * ## ทำไมต้องเป็น `Application` ไม่ใช่ `Activity` หรือ plugin
 *
 * นี่เป็นข้อสรุปเดียวกับ ADR-10 ฝั่ง iOS แค่คนละชื่อคลาส: `AppDelegate` ฝั่งนั้น
 * ต้องเริ่ม CoreLocation ใน `didFinishLaunchingWithOptions` เพราะเส้นทางเดิมผูกกับ
 * `FlutterViewController` ซึ่งไม่มีตอนถูกปลุกเบื้องหลัง
 *
 * ฝั่งนี้เหตุผลตรงกันเป๊ะ: เมื่อระบบส่งผลสแกนมาที่ `BeaconScanReceiver` ในขณะที่
 * แอปถูกปิดไปแล้ว ระบบจะสร้าง process ใหม่ขึ้นมาและเรียก
 * **`Application.onCreate()` ก่อน `onReceive()` เสมอ** — ไม่มี `Activity` ไม่มี
 * `FlutterEngine` และไม่มีอะไรอื่นถูกสร้าง จุดนี้จึงเป็น**จุดเดียว**ที่รับประกัน
 * ได้ว่าจะทำงานทุกครั้งที่ process เกิด ไม่ว่าจะเกิดด้วยเหตุใด
 *
 * ถ้าตั้ง observer ที่ `MainActivity` แทน เครื่องมือวัดจะทำงานเฉพาะตอนที่มี UI
 * ซึ่งคือเคสที่**ไม่ต้องพิสูจน์อะไร** — ความผิดพลาดแบบเดียวกับที่ทำให้ B5 รอบ
 * 30 ส.ค. 2026 ไม่มีบรรทัด log เลยแม้แต่บรรทัดเดียว
 */
class ExampleApplication : Application() {

    /**
     * `companion object` เพื่อให้ `MainActivity` เข้าถึงได้โดยไม่ต้องส่งต่อผ่าน
     * intent — และเพื่อให้เห็นชัดว่ามี **ตัวเดียวต่อ process** ไม่ใช่ตัวใหม่ทุก
     * ครั้งที่มีคนถาม (ถ้าสร้างใหม่ `processStartedElapsedMillis` จะรีเซ็ต แล้ว
     * `uptime` ใน log จะกลายเป็น 0 ตลอด ซึ่งกลบสิ่งที่มันควรวัดพอดี)
     */
    companion object {
        @Volatile
        lateinit var processState: ProcessState
            private set
    }

    override fun onCreate() {
        super.onCreate()

        processState = ProcessState()
        registerActivityLifecycleCallbacks(processState)

        // ตั้งผู้สังเกตการณ์ **ก่อน** อย่างอื่นทั้งหมด เพราะ `onReceive()` ของ
        // receiver อาจถูกเรียกทันทีหลังเมธอดนี้จบ ถ้าตั้งช้ากว่านั้น event แรกของ
        // รอบ process จะหายไปเงียบ ๆ — ซึ่งคือ event ที่สำคัญที่สุดพอดี เพราะมัน
        // คือ event ที่ทำให้ process นี้ถูกสร้างขึ้นมาตั้งแต่แรก
        BackgroundRegionMonitor.setRegionStateObserver { event ->
            BackgroundEvidenceLog.append(
                this,
                BackgroundEvidenceLog.line(
                    timestampMillis = event.timestampMillis,
                    event = event.state,
                    regionIdentifier = event.regionIdentifier,
                    conclusion = processState.conclusion,
                    rawSignals = BackgroundEvidenceLog.rawSignals(this, processState),
                ),
            )
            ExampleNotifications.post(
                context = this,
                title = "Region ${event.state}: ${event.regionIdentifier}",
                body = "สถานะแอป: ${processState.conclusion} · pid=${BackgroundEvidenceLog.processId}",
            )
        }

        logLaunch()
    }

    /**
     * เขียนบรรทัด `launch` **ทุกครั้งที่ process เริ่ม** ไม่ว่ารอบนั้นจะมี event
     * ตามมาหรือไม่
     *
     * นี่คือจุดที่แยก "ระบบไม่ได้ปลุกแอปเลย" (ไม่มีบรรทัด launch ใหม่) ออกจาก
     * "ปลุกแล้วแต่ event ไม่ถึงคนเขียน log" (มีบรรทัด launch แต่ไม่มี enter/exit
     * ตามมา) — ความต่างที่รอบทดสอบก่อนหน้าแยกไม่ออกเลยเพราะไม่มีบรรทัดอะไรให้ดู
     *
     * ## `restoredRegions` ต่างจาก `monitoredRegions` ของ iOS อย่างไร
     *
     * ฝั่ง iOS ค่านั้นมาจาก `CLLocationManager.monitoredRegions` = **ระบบบอกว่า
     * กำลังเฝ้าอะไรอยู่จริง** ส่วนค่านี้มาจากไฟล์ของเราเอง = **เราเคยสั่งให้เฝ้า
     * อะไรไว้** ตั้งชื่อคนละคำโดยตั้งใจ (ADR-14) เพื่อไม่ให้ใครอ่าน log แล้ว
     * เข้าใจว่าสองแพลตฟอร์มได้ค่านี้มาจากแหล่งเดียวกัน
     */
    private fun logLaunch() {
        val restored = runCatching {
            BackgroundRegionMonitor.restoredRegionIdentifiers(this)
        }.getOrDefault(emptyList())

        BackgroundEvidenceLog.append(
            this,
            BackgroundEvidenceLog.line(
                timestampMillis = System.currentTimeMillis(),
                event = "launch",
                regionIdentifier = "-",
                conclusion = processState.conclusion,
                rawSignals = BackgroundEvidenceLog.rawSignals(this, processState) +
                    " restoredRegions=[${restored.joinToString(",")}]",
            ),
        )
    }
}
