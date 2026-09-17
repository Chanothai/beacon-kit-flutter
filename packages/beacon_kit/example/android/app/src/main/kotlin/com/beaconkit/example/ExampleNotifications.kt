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
    /**
     * บีคอนที่จุดชนวน notification ใบนี้ — `"n/a"` เมื่อบรรทัดนี้ไม่ได้พูดถึงบีคอน
     * ตัวใดตัวหนึ่ง (เช่น notification ของชั้นที่ 1 ที่พูดถึงทั้ง region)
     *
     * **`"n/a"` ไม่ใช่ค่าว่าง** — ต้องอ่านออกได้ว่า "ถามแล้วและไม่มีคำตอบ" ต่างจาก
     * "ไม่มีคอลัมน์นี้เพราะเป็น log รุ่นเก่า" (หลักการเดียวกับ `store=ok` ฝั่ง iOS)
     */
    const val BEACON_NOT_APPLICABLE = "n/a"

    /** ชั้นที่เป็นเจ้าของ notification ใบนี้ — ดู kdoc ของ [post] */
    const val LAYER_REGION = "1"
    const val LAYER_PROXIMITY = "2"

    /**
     * เขียนเฉพาะบรรทัดหลักฐาน — **ไม่เรียก [deliveryReason]/`notify()` เด็ดขาด**
     * (ดู ADR-25 §3) เพราะ `cooldown` เป็นคนละแกนคำถามกับสี่เหตุผลที่ [deliveryReason]
     * ตอบ: ที่นี่คือ "แอปตัดสินใจไม่ลองยิงเองเพราะนโยบายคูลดาวน์" ไม่ใช่ "ระบบบล็อก"
     */
    fun recordSuppressed(
        context: Context,
        regionIdentifier: String,
        beacon: String = BEACON_NOT_APPLICABLE,
        mac: String = BEACON_NOT_APPLICABLE,
        layer: String = BEACON_NOT_APPLICABLE,
        reason: String,
        extra: String,
    ) {
        BackgroundEvidenceLog.append(
            context,
            BackgroundEvidenceLog.line(
                timestampMillis = System.currentTimeMillis(),
                event = "notification",
                regionIdentifier = regionIdentifier,
                conclusion = ExampleApplication.processState.conclusion,
                rawSignals = BackgroundEvidenceLog.rawSignals(
                    context = context, state = ExampleApplication.processState, receiverEntry = false,
                    // `trimEnd()` — ผู้เรียกที่ไม่มีอะไรต่อท้ายส่ง `extra = ""` ได้
                    // (เช่นเส้นทาง `reason=disabled` ของ ADR-25 §9) โดยบรรทัดไม่ลงท้าย
                    // ด้วยช่องว่างลอย ซึ่งจะทำให้ไฟล์หลักฐานมีสองรูปแบบปนกัน
                ) + " beacon=$beacon mac=$mac layer=$layer posted=false reason=$reason $extra".trimEnd(),
            ),
        )
    }

    /**
     * ยิง notification พร้อมเขียนบรรทัดหลักฐานที่ **แยกที่มาได้จากบรรทัดเดียว**
     *
     * ## ทำไมต้องมี `beacon=` และ `layer=` (เพิ่ม 11 ก.ย. 2026)
     *
     * ก่อนหน้านี้บรรทัด `event=notification` ฝั่ง Android เขียน `regionIdentifier`
     * เป็น `-` และไม่มี `beacon=` เลย ผลคือ **notification ทุกใบพิมพ์ออกมาเหมือนกันหมด**
     * — รอบตรวจ log 11 ก.ย. 2026 ต้องไล่จับคู่ 114 ใบกับบรรทัดที่อยู่ก่อนหน้าเองทีละใบ
     * เพื่อจะตอบแค่ว่า "ใบไหนมาจากชั้น 1 ใบไหนมาจากชั้น 2" (ได้ผล: ชั้น 1 = 104 ·
     * ชั้น 2 = 9 · ตอบไม่ได้ 1) และ **คำถาม "cooldown 60 วินาทีต่อบีคอนทำงานจริงไหม"
     * ตอบจากไฟล์ตรง ๆ ไม่ได้เลย** ต้องเดาบีคอนจากบรรทัดข้างเคียง
     *
     * นี่คือ**ช่องว่างเดียวกับที่ ADR-21 หัวข้อ 7 ข้อ 1 บังคับให้ฝั่ง iOS แก้ตั้งแต่
     * คอมมิตแรก** ("บรรทัดหลักฐานต้องแยกบีคอนออกจากกันได้") — ฝั่ง Android ทำชั้น
     * `proximity` ไปแล้วแต่ลืมบรรทัด `notification`
     *
     * ## ลำดับคอลัมน์
     *
     * ฟิลด์ใหม่ถูกวาง **ก่อน** `posted=`/`reason=`/`id=` ที่มีอยู่เดิม — คอลัมน์
     * สัญญาณดิบอ่านแบบ key=value ลำดับจึงไม่ใช่สัญญา แต่จัดให้ "ใครยิง" มาก่อน
     * "ยิงขึ้นไหม" เพราะเป็นลำดับที่คนอ่านไล่จริง
     *
     * @param regionIdentifier region ที่ผูกกับ notification ใบนี้ — ส่ง `"-"` เมื่อ
     *   ไม่มีจริง ๆ (ปุ่มทดสอบบน UI) **ห้ามเดาจากข้อความ `title`**
     * @param beacon `"<major>/<minor>"` หรือ [BEACON_NOT_APPLICABLE] — **ตัวระบุ
     *   เชิงตรรกะ ตรงกับฝั่ง iOS** ใช้จับคู่บรรทัดข้ามแพลตฟอร์มและเทียบกับ
     *   `docs/beacon-inventory.md`
     * @param mac สองไบต์ท้ายของ MAC หรือ [BEACON_NOT_APPLICABLE] — **ตัวแยกเชิง
     *   กายภาพ** เป็นค่าเดียวกับที่อยู่ใน gate key จึงเป็นตัวเดียวที่แยกบีคอนคนละตัว
     *   ใน region เดียวกันได้จริง · **ห้ามรวมกับ [beacon] เป็นฟิลด์เดียว**
     * @param layer [LAYER_REGION] (enter/exit) หรือ [LAYER_PROXIMITY] (ความใกล้)
     */
    fun post(
        context: Context,
        title: String,
        body: String,
        regionIdentifier: String = "-",
        beacon: String = BEACON_NOT_APPLICABLE,
        mac: String = BEACON_NOT_APPLICABLE,
        layer: String = BEACON_NOT_APPLICABLE,
    ): Boolean {
        return runCatching {
            ensureChannel(context)
            val id = synchronized(this) { nextId++ }
            val reason = deliveryReason(context)

            BackgroundEvidenceLog.append(
                context,
                BackgroundEvidenceLog.line(
                    timestampMillis = System.currentTimeMillis(),
                    event = "notification",
                    // **ผู้เรียกส่งมาตามจริงตั้งแต่ 11 ก.ย. 2026** — เดิมบรรทัดนี้
                    // ฮาร์ดโค้ด `-` เสมอเพราะ `post()` ไม่เคยรู้จัก region
                    // ตอนนี้รู้แล้ว จึงเขียนตามจริง · ยังเป็น `-` ได้เมื่อไม่มี
                    // region ผูกจริง ๆ (ปุ่มทดสอบบน UI) **ห้ามเดาจากข้อความ title**
                    regionIdentifier = regionIdentifier,
                    conclusion = ExampleApplication.processState.conclusion,
                    rawSignals = BackgroundEvidenceLog.rawSignals(
                        context = context,
                        state = ExampleApplication.processState,
                        // ยิงได้จากทั้ง observer ในเส้นทาง receiver และจากปุ่มบน UI
                        // — ไม่อ้างว่ามาจาก receiver เพราะพิสูจน์จากตรงนี้ไม่ได้
                        receiverEntry = false,
                    ) + " beacon=$beacon mac=$mac layer=$layer" +
                        " posted=${reason == REASON_GRANTED} reason=$reason id=$id",
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

            // ค่าสุดท้ายของบล็อก — ไม่กระทบพฤติกรรมเดิมข้างบนแม้แต่บรรทัดเดียว
            // (ADR-25 §3.1): ผู้เรียกเดิมสองจุด (`MainActivity.kt`,
            // `ExampleApplication.kt`) เรียกแบบ statement เดี่ยว ไม่ใช้ค่าที่คืนกลับ
            reason == REASON_GRANTED
        }.getOrDefault(false)
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
