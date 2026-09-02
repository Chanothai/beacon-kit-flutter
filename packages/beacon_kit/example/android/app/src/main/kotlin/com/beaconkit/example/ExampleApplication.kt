package com.beaconkit.example

import android.app.Application
import com.bigc.beacon_kit_android.BackgroundRegionMonitor
import com.bigc.beacon_kit_android.BackgroundRegionStateEvent

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
                    // receiverEntry = true เป็น **ข้อเท็จจริงของเส้นทางเรียก ไม่ใช่
                    // การเดา**: `BackgroundRegionMonitor.emit()` (จุดเดียวที่เรียก
                    // observer ตัวนี้) ถูกเรียกจาก `onSighting`/`onExitAlarm`
                    // เท่านั้น และสองเมธอดนั้นมีผู้เรียกแค่ `BeaconScanReceiver`
                    // กับ `RegionExitAlarmReceiver` — ทั้งคู่คือ `onReceive`
                    //
                    // ถ้าวันหนึ่งมีเส้นทางที่ยิง event จากที่อื่น (เช่นตอน
                    // foreground โดยตรง) **ต้องแยกค่าตรงนี้** ไม่ใช่ปล่อยให้
                    // บรรทัดนั้นอ้างว่ามาจาก receiver
                    rawSignals = BackgroundEvidenceLog.rawSignals(
                        context = this,
                        state = processState,
                        receiverEntry = true,
                    ) + exitTimingSuffix(event),
                ),
            )
            ExampleNotifications.post(
                context = this,
                title = "Region ${event.state}: ${event.regionIdentifier}",
                // `procUuid=` ไม่ใช่ `pid=` — ค่านี้คือ [BackgroundEvidenceLog.processId]
                // ไม่ใช่ pid ของ Linux การติดป้ายผิดทำให้คนที่เอาไปเทียบกับ `logcat`
                // หาไม่เจอแล้วสรุปว่า process ไม่ตรงกัน
                body = "สถานะแอป: ${processState.conclusion} · " +
                    "procUuid=${BackgroundEvidenceLog.processId}",
            )
        }

        logLaunch()
    }

    /**
     * ต่อท้ายสัญญาณดิบด้วยเวลาของนาฬิกาปลุก **เฉพาะบรรทัด `exit`**
     *
     * บรรทัด `enter` ไม่มีนาฬิกาปลุกให้พูดถึง การใส่ `n/a` สามช่องทุกบรรทัดจะ
     * ทำให้คอลัมน์สัญญาณดิบยาวขึ้นโดยไม่ได้ข้อมูลเพิ่ม และทำให้ `n/a` เสีย
     * ความหมาย — ค่านั้นถูกใช้แยกสาขา `bootMismatch` ของ exit อยู่
     */
    private fun exitTimingSuffix(event: BackgroundRegionStateEvent): String {
        if (event.state != "exit") return ""
        return " " + BackgroundEvidenceLog.exitTimingField(
            sinceLastSeenMillis = event.exitSinceLastSeenMillis,
            scheduledAtElapsedMillis = event.exitScheduledAtElapsedMillis,
            firedAtElapsedMillis = event.exitFiredAtElapsedMillis,
        )
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
     *
     * ## `[]` กับ `<read-failed:…>` ไม่ใช่สิ่งเดียวกัน
     *
     * `[]` = อ่านไฟล์สถานะได้ และไม่มี region อยู่ในนั้นจริง ๆ
     * `<read-failed:เหตุผล>` = **อ่านไม่สำเร็จ** จึงตอบไม่ได้ว่ามีหรือไม่มี
     *
     * เดิมทั้งสองกรณีเขียนออกมาเป็น `[]` เหมือนกัน ซึ่งเป็นความล้มเหลวเงียบ:
     * ตารางแปลผลใน runbook ชี้ไปที่ "มีโค้ดล้างสถานะทิ้ง" ทางเดียว ทั้งที่อาจเป็น
     * ค่าที่เก็บไว้เสียหายหรือเปิดไฟล์ไม่ได้ ซึ่งแก้คนละทางโดยสิ้นเชิง
     */
    private fun logLaunch() {
        val restoredField = runCatching {
            val parsed = BackgroundRegionMonitor.restoredRegions(this)
            BackgroundEvidenceLog.restoredRegionsField(
                identifiers = parsed.regions.map { it.identifier },
                readError = parsed.readError,
            )
        }.getOrElse { error ->
            // ข้อยกเว้นตรงนี้เดิมกลายเป็น `[]` เงียบ ๆ — บรรทัดที่ตามมาจะดูเหมือน
            // "ไฟล์สถานะว่าง" ทั้งที่ยังไม่เคยอ่านสำเร็จเลยสักครั้ง
            BackgroundEvidenceLog.restoredRegionsField(
                identifiers = emptyList(),
                readError = "${error.javaClass.simpleName}: ${error.message}",
            )
        }

        BackgroundEvidenceLog.append(
            this,
            BackgroundEvidenceLog.line(
                timestampMillis = System.currentTimeMillis(),
                event = "launch",
                regionIdentifier = "-",
                conclusion = processState.conclusion,
                // receiverEntry = false เสมอ **แม้ process นี้จะเกิดขึ้นเพราะ
                // broadcast ก็ตาม** — ระบบเรียก `Application.onCreate()` ให้จบ
                // ก่อนแล้วจึงเรียก `onReceive()` บรรทัดนี้จึงถูกเขียนนอก
                // `onReceive` จริง ๆ
                //
                // ⚠️ `conclusion` ของบรรทัด `launch` **ไม่ใช่หลักฐาน** — เมธอดนี้
                // ถูกเรียกจาก `Application.onCreate()` ซึ่งเกิดก่อน `Activity` ตัว
                // แรกเสมอ ณ จุดนั้น `resumedActivityCount == 0` และ
                // `hasEverBeenForeground == false` ทุกครั้ง ค่าจึงเป็น
                // `relaunchedFromTerminated` **เสมอ** แม้ผู้ใช้จะกดไอคอนเปิดแอปเอง
                //
                // สิ่งที่พิสูจน์ว่า process นี้เป็นตัวใหม่คือ **`procUuid` ที่ไม่
                // เคยปรากฏในไฟล์มาก่อน** เท่านั้น ส่วนบริบทว่าแอปถูกปลุกโดยไม่มี UI
                // จริงหรือไม่ ต้องอ่านจากบรรทัด `enter`/`exit` ที่มี
                // `receiverEntry=true` และ `procUuid` เดียวกัน ซึ่งคำนวณ
                // `conclusion` ตอนที่ `ProcessState` มีข้อมูลจริงแล้ว
                rawSignals = BackgroundEvidenceLog.rawSignals(
                    context = this,
                    state = processState,
                    receiverEntry = false,
                ) + " " + restoredField,
            ),
        )
    }
}
