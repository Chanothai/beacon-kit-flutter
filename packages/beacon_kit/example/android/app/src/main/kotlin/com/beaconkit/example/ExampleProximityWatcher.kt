package com.beaconkit.example

import android.content.Context
import com.bigc.beacon_kit_android.BackgroundProximityMonitor
import com.bigc.beacon_kit_android.ProximityBucket
import com.bigc.beacon_kit_android.ProximityChangedEvent
import java.util.Locale

/**
 * ผู้สังเกตการณ์ชั้น proximity (ADR-20 ชั้นที่ 2) ของ **example app เท่านั้น**
 *
 * อยู่นอก SDK ด้วยเหตุผลเดียวกับที่ `ExampleApplication` อยู่นอก SDK: การยิง
 * notification และนโยบาย cooldown เป็น**นโยบายของแอป ไม่ใช่ความสามารถของแพลตฟอร์ม**
 * (ADR-20 หัวข้อ 6 บันทึกไว้ตรง ๆ ว่า cooldown อยู่แค่ example app ในรอบนี้ แนวเดียว
 * กับ ADR-11 เรื่องตำแหน่งของ debounce)
 *
 * ## ลำดับที่ห้ามสลับ: log ก่อน notification เสมอ
 *
 * ไฟล์หลักฐานคือสิ่งเดียวที่รอดจากรอบทดสอบข้ามคืนที่ไม่มีใครดูหน้าจอ ส่วน
 * notification เป็นแค่ความสะดวกตอน demo — ถ้าระบบฆ่า process คั่นกลาง สิ่งที่ต้อง
 * ลงดิสก์ไปแล้วคือบรรทัด log (หลักการเดียวกับ `BackgroundRegionMonitor.emit()` และ
 * กับฝั่ง iOS ที่เขียน log ก่อนยิง notification เสมอ)
 *
 * **cooldown มีผลกับ notification เท่านั้น — บรรทัด log เขียนทุกครั้ง** ไม่งั้น
 * หลักฐานจะหายไปพร้อมกับการกันสแปม ซึ่งกลับหัวกลับหางกับเหตุผลข้างบน
 */
object ExampleProximityWatcher {

    /**
     * เว้นช่วง notification ต่อหนึ่ง key อย่างน้อย 60 วินาที
     *
     * เป็นค่าสำหรับ demo ล้วน ๆ ไม่ใช่ค่าที่ calibrate อะไร: ตอนยืนอยู่หน้าชั้นวาง
     * bucket แกว่งไป-กลับระหว่าง near/immediate ได้เรื่อย ๆ ทุก sighting ถ้าไม่กัน
     * ผู้ทดสอบจะได้ notification รัวจนอ่านไม่ทันและกลบ event ที่กำลังจะพิสูจน์
     */
    private const val NOTIFICATION_COOLDOWN_MILLIS = 60_000L

    private const val COOLDOWN_PREFS = "example.proximity_notification_cooldown"

    /**
     * ตั้งผู้สังเกตการณ์ — ต้องเรียกจาก `Application.onCreate()` เท่านั้น (จุดเดียว
     * ที่ทำงานเสมอไม่ว่า process จะเกิดด้วยเหตุใด — ดู kdoc ของ `ExampleApplication`)
     */
    fun install(context: Context) {
        val appContext = context.applicationContext
        BackgroundProximityMonitor.setProximityObserver { event ->
            onProximityChanged(appContext, event)
        }
    }

    private fun onProximityChanged(context: Context, event: ProximityChangedEvent) {
        // 1) หลักฐานก่อน — schema 6 คอลัมน์เดิมทุกประการ ไม่เพิ่ม/ลด/สลับคอลัมน์
        //    ข้อมูลใหม่ทั้งหมดของ ADR-20 ต่อท้ายอยู่ใน**คอลัมน์สัญญาณดิบ**เท่านั้น
        //    (ตัวอ่านที่มีอยู่ทั้ง runbook และฝั่ง Dart จึงไม่พัง)
        BackgroundEvidenceLog.append(
            context,
            BackgroundEvidenceLog.line(
                timestampMillis = event.timestampMillis,
                event = "proximity",
                regionIdentifier = event.regionIdentifier,
                conclusion = ExampleApplication.processState.conclusion,
                // receiverEntry = true เป็นข้อเท็จจริงของเส้นทางเรียก ไม่ใช่การเดา:
                // `BackgroundProximityMonitor.emit()` ถูกเรียกจาก
                // `BeaconScanReceiver.onReceive()` ที่เดียวเท่านั้น
                rawSignals = BackgroundEvidenceLog.rawSignals(
                    context = context,
                    state = ExampleApplication.processState,
                    receiverEntry = true,
                ) + rawSignalsSuffix(event),
            ),
        )

        // 2) notification เฉพาะ transition ที่ยืนยันว่า "ใกล้" — **ตัวกรองอยู่ที่
        //    แอป ไม่ใช่ที่ SDK** (ADR-20 หัวข้อ 6 แนวเดียวกับตำแหน่งของ cooldown)
        //    บรรทัดหลักฐานข้างบนเขียนครบทุก transition รวม `farther`/`stale` ด้วย
        //    เพราะสองอย่างนั้นคือสิ่งเดียวที่ตอบได้ว่า `exitMeters`/`staleAfter`
        //    ใช้ได้จริงหรือไม่ในรอบทดสอบเครื่องจริง — แต่ผู้ทดสอบไม่ควรได้
        //    notification ตอนเดินออกจากชั้นวาง เพราะจะกลบสัญญาณที่กำลังจะพิสูจน์
        val to = event.to
        if (to != ProximityBucket.NEAR && to != ProximityBucket.IMMEDIATE) return

        // 3) **ยิงเฉพาะตอน "เข้าสู่ความใกล้" เท่านั้น ไม่ใช่ทุกการขยับภายในความใกล้**
        //
        // ## ทำไมต้องมีเงื่อนไขนี้ — ข้อมูลจากรอบทดสอบ 9 ก.ย. 2026 รอบที่ 2
        //
        // `ProximityGate.classify()` มี dead zone เฉพาะขอบ far ↔ close
        // (`enterMeters` 3.0 / `exitMeters` 5.0) ส่วนขอบ `immediate`/`near` เป็น
        // เกณฑ์เดี่ยว ๆ `median <= immediateMeters (1.0)` **ไม่มีอะไรคั่น** ผู้ทดสอบ
        // ที่ยืนนิ่งอยู่ราว 1 เมตรจึงทำให้ median ข้าม 1.0 ไป-กลับทุก batch แล้ว
        // **ทั้งสองทิศผ่านตัวกรองข้างบนได้หมด** (`to` เป็น near หรือ immediate
        // เหมือนกัน) — วัดได้จริง 16 จาก 36 event ของรอบที่ 2
        // (`docs/test-data/2026-09-09_android_proximity_background.log`)
        //
        // นี่คือ**ช่องว่างของการออกแบบใน ADR-19 หัวข้อ 6(ข) เอง** ซึ่งพูดถึง
        // hysteresis เฉพาะขอบ far/close — `proximity_gate.dart` มีพฤติกรรมเดียวกัน
        // เป๊ะ **จึงห้ามแก้ที่ `ProximityGate` ฝั่ง Kotlin เด็ดขาด** เพราะจะ drift
        // จาก reference impl ซึ่ง ADR-20 หัวข้อ 2 ห้ามไว้ การเติม hysteresis ที่ขอบ
        // `immediate` ต้องเป็น ADR รอบใหม่ที่แก้ทั้งสองภาษาพร้อมกัน
        //
        // รอบนี้จึงกันที่ชั้นนโยบายของแอปแทน ตาม ADR-20 หัวข้อ 6 —
        // **บรรทัดหลักฐานยังเขียนครบทุก flap** (ข้อ 1 ข้างบน) ข้อมูลที่ต้องใช้
        // calibrate ขอบ `immediate` จึงไม่หายไปไหน หายแค่การรบกวนผู้ใช้
        val from = event.from
        if (from != null && from != ProximityBucket.FAR) return

        // 4) แล้วค่อย notification (ถ้าไม่ติด cooldown)
        val key = cooldownKeyFor(event)
        if (!consumeCooldown(context, key, event.timestampMillis)) return

        val bucket = to.wireName
        ExampleNotifications.post(
            context = context,
            title = "ใกล้ ${event.regionIdentifier} ($bucket)",
            body = "reason=${event.reason.wireName} " +
                "medianM=${formatMeters(event.medianMeters)} · " +
                "procUuid=${BackgroundEvidenceLog.processId}",
        )
    }

    /**
     * ส่วนต่อท้ายของคอลัมน์สัญญาณดิบสำหรับบรรทัด `proximity` — **pure function**
     * จึงมี unit test คลุมได้จริงโดยไม่ต้องมีเครื่อง (เหตุผลเดียวกับ
     * `BackgroundEvidenceLog.line`)
     *
     * ```
     *  bucket=near from=none reason=closer medianM=2.4 rssi=-72 txPower=-59
     * ```
     *
     * รูปแบบเดียวกับ `ExampleApplication.rawSignalsSuffix()`: ขึ้นต้นด้วยช่องว่าง
     * และทุกค่าที่ไม่มีเขียนเป็น `n/a` **ห้ามปล่อยว่างและห้ามมีช่องว่างในค่า**
     * เพราะคอลัมน์สัญญาณดิบคั่นค่าด้วยช่องว่าง ถ้าค่าใดว่างหรือมีช่องว่างปน ตัวอ่าน
     * จะเห็นเป็นคนละ key โดยไม่มีอะไรฟ้อง
     *
     * `from=none` (ไม่ใช่ `n/a`) เมื่อไม่เคยมี bucket ที่ยืนยันมาก่อน — สองอย่างนี้
     * คนละความหมาย: `none` = "ยืนยัน bucket แรกของบีคอนตัวนี้" ซึ่งเป็นข้อเท็จจริง
     * ที่รู้แน่ ส่วน `n/a` = "ตอบไม่ได้"
     */
    fun rawSignalsSuffix(event: ProximityChangedEvent): String = buildString {
        append(" bucket=${event.to?.wireName ?: "n/a"}")
        append(" from=${event.from?.wireName ?: "none"}")
        append(" reason=${event.reason.wireName}")
        append(" medianM=${formatMeters(event.medianMeters)}")
        append(" rssi=${event.rssi ?: "n/a"}")
        append(" txPower=${event.txPower ?: "n/a"}")
    }

    /**
     * ทศนิยม 1 ตำแหน่งด้วย [Locale.US] เสมอ — **ไม่ใช่ locale ของเครื่อง**
     * เพราะบางภาษาใช้ `,` เป็นจุดทศนิยม ซึ่งจะทำให้ตัวเลขในไฟล์หลักฐานถอดกลับเป็น
     * `Double` ไม่ได้บนเครื่องที่ตั้งภาษาต่างกัน (ความแม่นยำระดับ 0.1 ม. ก็เกินพอ
     * อยู่แล้วสำหรับค่าที่ ADR-19 เตือนว่าห้ามอ่านเป็นตำแหน่งที่แม่นยำ)
     */
    private fun formatMeters(meters: Double?): String =
        if (meters == null) "n/a" else String.format(Locale.US, "%.1f", meters)

    /**
     * key ของ cooldown — ระดับ **การแจ้งเตือนหนึ่งใบ** ไม่ใช่ระดับบีคอนหนึ่งตัว
     *
     * ⚠️ **ตั้งใจไม่ตรงกับ key ของ `ProximityGate`** (ซึ่งมี MAC ของบีคอนอยู่ด้วย):
     * ข้อความที่ผู้ใช้เห็นคือ "ใกล้ <regionIdentifier>" ถ้าใช้ MAC เป็นส่วนหนึ่งของ
     * cooldown แล้ว region กว้าง ๆ ที่มีบีคอนหลายตัว (ADR-8) จะยิงข้อความ**ที่อ่าน
     * แล้วเหมือนกันเป๊ะ**หลายใบซ้อนกัน ซึ่งคือสิ่งที่ cooldown มีไว้กันตั้งแต่แรก
     * — และ `ProximityChangedEvent` ก็ไม่มี MAC ให้ใช้อยู่แล้วโดยตั้งใจ (ADR-20
     * หัวข้อ 5 ไม่ได้นิยามฟิลด์นั้นไว้ในสัญญา)
     */
    private fun cooldownKeyFor(event: ProximityChangedEvent): String =
        listOf(
            event.regionIdentifier,
            event.uuid ?: "-",
            event.major?.toString() ?: "-",
            event.minor?.toString() ?: "-",
        ).joinToString("|")

    /**
     * `true` เมื่อยิง notification ได้ (และจดเวลาไว้แล้ว) · `false` เมื่อยังติด
     * cooldown อยู่
     *
     * **เก็บลง `SharedPreferences` ด้วย `commit()` ไม่ใช่ตัวแปรใน memory** เพราะ
     * process ตายได้ทุก sighting (ADR-20 หัวข้อ 3) — cooldown ที่อยู่ใน memory
     * อย่างเดียวจะรีเซ็ตทุกครั้งที่ระบบสร้าง process ใหม่ ซึ่งแปลว่ามันจะไม่ทำงาน
     * เลยในเคสที่มันถูกสร้างมาเพื่อแก้ (`apply()` ก็ไม่พอด้วยเหตุผลเดียวกับที่
     * `BackgroundRegionStore` ใช้ `commit()`)
     *
     * นาฬิกาที่เทียบคือเวลาแบบ wall clock ที่ติดมากับ event เอง ไม่ใช่
     * `elapsedRealtime` — ยอมแลกความเสี่ยงเรื่องผู้ใช้ปรับนาฬิกาเครื่อง (ซึ่งทำให้
     * เกิด/หายไปได้แค่ notification ใบเดียวตอน demo) กับการไม่ต้องจัดการโทเคนรอบบูต
     * แบบที่ `BackgroundRegionStore` ต้องทำ เพราะที่นั่นค่าผิดแปลว่า enter/exit ผิด
     */
    private fun consumeCooldown(context: Context, key: String, nowMillis: Long): Boolean {
        val prefs = context.getSharedPreferences(COOLDOWN_PREFS, Context.MODE_PRIVATE)
        val lastMillis = prefs.getLong(key, 0L)
        if (lastMillis != 0L && nowMillis - lastMillis < NOTIFICATION_COOLDOWN_MILLIS) {
            return false
        }
        prefs.edit().putLong(key, nowMillis).commit()
        return true
    }
}
