package com.beaconkit.example

import android.content.Context
import android.os.SystemClock
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
     * คูลดาวน์ **ที่สอง** ต่อ key ซ้อนอยู่**เหนือ** [NOTIFICATION_COOLDOWN_MILLIS]
     * เดิม (ไม่ได้แทนที่) เก็บลง store คนละไฟล์กับทุก store ที่เส้นทางล้าง state
     * (`ProximityGateStore`, `BackgroundRegionStore`) แก้ไขอยู่โดยตั้งใจ — ตอบปัญหา
     * ของ §12.6.1: state ที่ถูกล้างทำให้ transition แรกดูเหมือนเดินข้ามขอบใหม่
     * (ADR-25 §2)
     *
     * **ค่าเริ่มต้นของสินค้า (product default) — 24 ชั่วโมง** (ADR-25 §8.1, ยืนยันจาก
     * เจ้าของสินค้า 17 ก.ย. 2026, §6 ข้อ 2) — ⚠️ ค่านี้เป็น **ค่าเริ่มต้นของพารามิเตอร์
     * `install()` เท่านั้น** ไม่ใช่ SDK default เพราะ SDK (`packages/beacon_kit_android/`)
     * ไม่มีแนวคิดคูลดาวน์นี้เลย — คูลดาวน์ยังเป็นนโยบายของ example/host app ล้วน ๆ
     * ตาม ADR-20 หัวข้อ 6
     */
    internal const val DEFAULT_LONG_COOLDOWN_MILLIS = 24 * 60 * 60 * 1_000L // 86,400,000

    /** ค่าที่ใช้งานจริง ณ runtime — ตั้งครั้งเดียวใน [install] ไม่มี setter อื่น (ADR-25 §8.3) */
    private var longCooldownMillis: Long = DEFAULT_LONG_COOLDOWN_MILLIS

    /** ไฟล์ prefs ใหม่ แยกจากทุก store เดิม (ADR-25 §3) */
    private const val LONG_COOLDOWN_PREFS = "notification_cooldown_v1"

    /**
     * ตั้งผู้สังเกตการณ์ — ต้องเรียกจาก `Application.onCreate()` เท่านั้น (จุดเดียว
     * ที่ทำงานเสมอไม่ว่า process จะเกิดด้วยเหตุใด — ดู kdoc ของ `ExampleApplication`)
     *
     * @param longCooldownMillis ค่าคูลดาวน์ 30 นาทีที่สอง (ADR-25 §2/§3.1) — default
     *   เป็นค่าสินค้า [DEFAULT_LONG_COOLDOWN_MILLIS] (24 ชม., ADR-25 §8.1) example app
     *   override เป็นค่าทดสอบสั้นกว่าอย่างชัดเจนที่จุดเรียก (`ExampleApplication.kt`)
     */
    fun install(
        context: Context,
        longCooldownMillis: Long = DEFAULT_LONG_COOLDOWN_MILLIS,
    ) {
        this.longCooldownMillis = longCooldownMillis
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

        // 3.5) คูลดาวน์ 30 นาทีที่สอง (ADR-25 §2/§3/§3.1) — เช็ค**ก่อน**คูลดาวน์
        // เดิม 60 วินาทีเพราะนี่คือตัวที่ตอบปัญหาของ §12.6 จริง ๆ (คูลดาวน์เดิม
        // มักหมดอายุไปแล้วก่อนรอบล้าง-นับใหม่ถัดไปเสมอ) — `nowElapsed` อ่านครั้ง
        // เดียวตอนต้นแล้วใช้ซ้ำตอนจด เพราะทั้งฟังก์ชันเป็น synchronous call เดียว
        val longKey = longCooldownKeyFor(event)
        val nowElapsed = SystemClock.elapsedRealtime()
        val blockedSince = longCooldownSinceLastPostedOrNull(context, longKey, nowElapsed)
        if (blockedSince != null) {
            ExampleNotifications.recordSuppressed(
                context = context,
                regionIdentifier = event.regionIdentifier,
                beacon = beaconField(event),
                mac = event.beaconTag ?: ExampleNotifications.BEACON_NOT_APPLICABLE,
                layer = ExampleNotifications.LAYER_PROXIMITY,
                reason = "cooldown",
                extra = "sinceLastPostedMs=$blockedSince",
            )
            return
        }

        // 4) แล้วค่อย notification (ถ้าไม่ติด cooldown เดิม 60 วินาที)
        val key = cooldownKeyFor(event)
        if (!consumeCooldown(context, key, event.timestampMillis)) return

        val bucket = to.wireName
        val posted = ExampleNotifications.post(
            context = context,
            title = "ใกล้ ${event.regionIdentifier} · จุด ${beaconField(event)} ($bucket)",
            body = "reason=${event.reason.wireName} " +
                "medianM=${formatMeters(event.medianMeters)} · " +
                "beacon=${beaconField(event)} · " +
                "mac=${event.beaconTag ?: ExampleNotifications.BEACON_NOT_APPLICABLE} · " +
                "procUuid=${BackgroundEvidenceLog.processId}",
            // **ค่าสามตัวนี้คือสิ่งที่ทำให้บรรทัดหลักฐานตอบคำถาม "cooldown ทำงานไหม"
            // ได้จากไฟล์ตรง ๆ** โดยไม่ต้องไล่จับคู่กับบรรทัดข้างเคียง (ดู kdoc ของ
            // `ExampleNotifications.post`) — `beaconTag` เป็นตัวเดียวกับที่ใช้เป็น
            // key ของ cooldown จริง จึงเทียบกันได้ตรง ๆ
            regionIdentifier = event.regionIdentifier,
            beacon = beaconField(event),
            mac = event.beaconTag ?: ExampleNotifications.BEACON_NOT_APPLICABLE,
            layer = ExampleNotifications.LAYER_PROXIMITY,
        )
        // จดเวลาคูลดาวน์ 30 นาทีก็ต่อเมื่อ `post()` ยืนยันว่าโพสต์สำเร็จจริง
        // (`reason == granted`) เท่านั้น (ADR-25 §3.1) — ถ้า `false` (ติด
        // permissionDenied/blockedByUser/channelBlocked) ไม่จด ครั้งถัดไปจะเช็ค
        // ใหม่ทุกครั้ง ไม่ใช่ค้างเงียบ 30 นาทีจากการ "โพสต์" ที่ไม่มีใบไหนถึงผู้ใช้จริง
        if (posted) {
            recordLongCooldownPosted(context, longKey, nowElapsed)
        }
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
        // **สองฟิลด์นี้ตอบคนละคำถาม ห้ามรวมเป็นตัวเดียว** (เปลี่ยนรูปแบบ 11 ก.ย. 2026)
        //
        // `beacon=<major>/<minor>` — **ตัวระบุเชิงตรรกะ ตรงกับฝั่ง iOS** ใช้จับคู่
        // บรรทัดของสองแพลตฟอร์มเข้าหากันและเทียบกับ `docs/beacon-inventory.md` ได้
        //
        // `mac=<2 ไบต์ท้าย>` — **ตัวแยกเชิงกายภาพ** ดึงจาก `ScanResult.device?.address`
        // ตรง ๆ ต่อ sample ที่มี `ScanResult` จริง (ไม่ได้อยู่ใน gate key อีกต่อไป
        // ตั้งแต่ ADR-20 หัวข้อ 3 แก้ 11 ก.ย. 2026) ยังมีประโยชน์แยกบีคอนคนละตัวใน
        // region เดียวกันได้จริง ถ้าไม่มี `stale` หลายบรรทัดติดกันจะอ่านเหมือนบั๊ก
        // ยิงซ้ำ (เกิดจริง 9 ก.ย. 2026 ช่วง 16:45-16:48) · เก็บแค่สองไบต์ท้ายเพราะ
        // พอแยกได้โดยไม่ต้องเขียนที่อยู่เต็มลงไฟล์ที่ถูก commit เข้า repo
        //
        // ⚠️ **`mac=n/a` เสมอบนบรรทัด `stale`** เพราะ transition จาก
        // `ProximityGate.sweepStale()` ไม่มี `ScanResult` คู่มาด้วย (เป็นการตรวจ
        // ความเงียบ ไม่ใช่ sample ใหม่) — เป็นผลที่ ADR-20 หัวข้อ 3 ระบุไว้ล่วงหน้า
        // แล้ว ไม่ใช่ regression
        //
        // `beacon=<major>/<minor>` ตอนนี้ถอดจาก**เฟรมจริง**แล้ว (ADR-20 หัวข้อ 1
        // แก้ 11 ก.ย. 2026 — เดิมมาจาก region spec ที่ลงทะเบียนด้วย UUID อย่างเดียว
        // จึงเป็น `n/a` ทุกบรรทัด ดูหัวข้อ 8) จึงควรมีค่าจริงแทบทุกครั้งที่บรรทัดนี้
        // ถูกเขียน **`n/a` ยังเหลืออยู่เป็นทางออกสำรองเท่านั้น** สำหรับกรณีที่ไม่
        // ควรเกิดในทางปฏิบัติ (ถอด key ของ transition กลับไม่ได้ — ดู
        // `proximityKeyPartsOrNull` ใน SDK) ไม่ใช่เส้นทางปกติอีกต่อไป
        append(" beacon=${beaconField(event)}")
        append(" mac=${event.beaconTag ?: "n/a"}")
        // `ok` ไม่ใช่ค่าว่าง — ต้องอ่านออกได้ว่า "ถามแล้วและไม่มี error" ต่างจาก
        // "ไม่มีคอลัมน์นี้เพราะเป็น log รุ่นเก่า" · ค่าอาจเป็น `migrated_dropped=<n>`
        // ตอนบิลด์แรกหลังเปลี่ยนรูปร่าง key ของ ADR-20 หัวข้อ 3 — ไม่ใช่ error จริง
        append(" store=${event.storeError?.replace(' ', '_') ?: "ok"}")
        // ตัวนับระดับ batch ของ sample ที่ถอด identity จากเฟรมไม่ได้และถูกทิ้งไป
        // ทั้งอัน (ADR-20 หัวข้อ 3) — พิมพ์เสมอแบบเดียวกับ `store=` ไม่ใช่แค่ตอน
        // มากกว่า 0 เพื่อให้อ่านออกว่า "ถามแล้วไม่มีอะไรถูกทิ้ง" ต่างจาก "ไม่มี
        // คอลัมน์นี้เพราะเป็น log รุ่นเก่า"
        append(" droppedNoIdentity=${event.droppedNoIdentityCount}")
        // มีค่าเฉพาะบรรทัด `reason=stale` (ADR-25 §5) — `n/a` เสมอสำหรับ transition
        // อื่นตามธรรมเนียมเดิมของไฟล์นี้ที่พิมพ์ `n/a` แทนการปล่อยว่าง
        append(" sinceLastSeenMs=${event.sinceLastSeenMs ?: "n/a"}")
    }

    /**
     * ทศนิยม 1 ตำแหน่งด้วย [Locale.US] เสมอ — **ไม่ใช่ locale ของเครื่อง**
     * เพราะบางภาษาใช้ `,` เป็นจุดทศนิยม ซึ่งจะทำให้ตัวเลขในไฟล์หลักฐานถอดกลับเป็น
     * `Double` ไม่ได้บนเครื่องที่ตั้งภาษาต่างกัน (ความแม่นยำระดับ 0.1 ม. ก็เกินพอ
     * อยู่แล้วสำหรับค่าที่ ADR-19 เตือนว่าห้ามอ่านเป็นตำแหน่งที่แม่นยำ)
     */
    /**
     * `"<major>/<minor>"` หรือ `"n/a"` — **pure function มี unit test ล็อกไว้**
     *
     * ## `"n/a"` ยังเป็นทางออกที่ถูกอยู่ แต่ตอนนี้ควรเห็นแทบไม่ได้เลย
     *
     * ก่อน ADR-20 หัวข้อ 1 แก้ 11 ก.ย. 2026 นี่คือ**เส้นทางปกติ** เพราะ
     * `ProximityChangedEvent.major/minor` มาจาก region spec ที่ `main.dart`
     * ลงทะเบียนด้วย UUID อย่างเดียว จึงเป็น `null` เสมอ (ดูหัวข้อ 8) — ตอนนี้
     * SDK ถอด major/minor จากเฟรมจริงแล้ว และ sample ที่ถอดไม่ได้จะถูกทิ้งไป
     * **ก่อนที่จะสร้าง event เลย** (ADR-20 หัวข้อ 3: ห้ามเรียก `gate.push()` และ
     * ห้าม fallback เมื่อถอด identity ไม่ได้) ดังนั้น event ที่ไปถึงฟังก์ชันนี้
     * ควรมี major/minor จริงแทบทุกครั้ง `"n/a"` จึงเหลือแค่ทางออกสำรองสำหรับ
     * เคสที่ไม่ควรเกิดในทางปฏิบัติ (เช่น ถอด key ของ transition กลับไม่ได้ — ดู
     * `proximityKeyPartsOrNull` ใน SDK) — ยัง**ต้อง**คงไว้เพราะห้ามเดาค่าแทนเวลา
     * ตอบไม่ได้จริง ๆ แต่ไม่ใช่เส้นทางที่คาดว่าจะเจอบ่อยอีกต่อไป
     *
     * ต้องได้ `n/a` เมื่อ**ค่าใดค่าหนึ่งหาย** ไม่ใช่เฉพาะตอนหายทั้งคู่: `"9902/null"`
     * เป็นสตริงที่อ่านแล้วเข้าใจผิดว่ารู้ major แต่ไม่รู้ minor ทั้งที่ในทางปฏิบัติ
     * ทั้งคู่มาจากแหล่งเดียวกัน (การถอด key เดียวกัน) และหายพร้อมกันเสมอ
     */
    fun beaconField(event: ProximityChangedEvent): String {
        val major = event.major
        val minor = event.minor
        if (major == null || minor == null) return "n/a"
        return "$major/$minor"
    }

    private fun formatMeters(meters: Double?): String =
        if (meters == null) "n/a" else String.format(Locale.US, "%.1f", meters)

    /**
     * key ของ cooldown — **รายบีคอน** (`regionIdentifier`, major, minor) ไม่มี
     * uuid — คนละ key กับ `ProximityGate` โดยตั้งใจ (ADR-20 หัวข้อ 8)
     *
     * ## ทำไมเปลี่ยนจาก "ตั้งใจไม่ตรงกับ key ของ gate" (ข้อสรุปเดิมผิดที่ต้นเหตุ)
     *
     * เดิมคูลดาวน์คุมแค่ระดับ `regionIdentifier` เพราะข้อความแจ้งเตือนตอนนั้นคือ
     * "ใกล้ &lt;regionIdentifier&gt;" ล้วน ๆ ไม่มีอะไรระบุบีคอนตัวไหน — คูลดาวน์
     * รายบีคอนตอนนั้นไม่มีประโยชน์เชิง UX เพราะผู้ใช้อ่านสองข้อความจากบีคอนคนละตัว
     * ในภูมิภาคเดียวกันแล้วเห็นเหมือนกันเป๊ะอยู่ดี **เหตุผลนั้นถูกแก้ที่ต้นเหตุแล้ว
     * ไม่ใช่ถูกหักล้าง**: ข้อความตอนนี้มี major/minor ต่อท้าย (เช่น "จุด 9902/2")
     * เพราะ `ProximityChangedEvent.major/minor` ถอดจากเฟรมจริงแล้ว (ADR-20 หัวข้อ
     * 1 แก้ 11 ก.ย. 2026) คูลดาวน์รายบีคอนจึงมีความหมายเชิง UX จริง — "จุด 9902/2"
     * แล้ว "จุด 9903/3" เป็นสองเหตุการณ์ที่ต่างกันจริงสำหรับผู้ใช้ ไม่ใช่สแปมข้อความ
     * ซ้ำ (ADR-20 หัวข้อ 8)
     *
     * **ไม่มี uuid ในคีย์นี้ ต่างจาก gate key โดยตั้งใจ**: คูลดาวน์ไม่จำเป็นต้อง
     * แยกข้ามคนละ UUID ในทางปฏิบัติของตัวอย่างนี้ — แค่แยกรายจุดในสคีมของ BigC
     * เดียวกันก็พอ (การยุบหลายบีคอนเป็นความหมายเดียวสำหรับผู้ใช้ปลายทาง เช่น
     * "ชั้นวางเครื่องดื่ม" ที่มีบีคอนสองตัวคาบเกี่ยว เป็นหน้าที่ของตาราง mapping
     * ในฝั่ง host app ไม่ใช่หน้าที่ของ example app หรือ SDK)
     *
     * ⚠️ ความถี่ของ notification จะเพิ่มขึ้นเมื่อยืนใกล้บีคอนหลายตัวในภูมิภาค
     * เดียวกัน เทียบกับบิลด์ก่อนหน้าที่คูลดาวน์ยุบทุกบีคอนเข้าด้วยกัน — เป็นผลที่
     * ตั้งใจจากคำตัดสินนี้ ไม่ใช่ regression (ADR-20 หัวข้อ 8)
     */
    private fun cooldownKeyFor(event: ProximityChangedEvent): String =
        listOf(
            event.regionIdentifier,
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

    /**
     * key ของคูลดาวน์ 30 นาที — **ต้องตรงกับ key ที่ `ProximityGateStore`/
     * `ProximityGate` ใช้จริง** (`region|uuid|major|minor`, ดู `proximityKeyFor()`
     * ใน `BeaconScanReceiver.kt`) เพราะนี่คือหัวใจของ ADR-25 §2: ถ้าคูลดาวน์ตัวนี้
     * ใช้ key คนละแบบกับ gate จะกันสแปมจากการล้าง state ไม่ได้ตรงจุด
     *
     * ประกอบแบบทนทานต่อ null ตามลาย [cooldownKeyFor] ข้างบน (ไม่เรียก
     * `proximityKeyFor()` ตรง ๆ เพราะฟังก์ชันนั้นรับ non-null ล้วน) — `uuid`
     * เป็น `lowercase()` ให้ตรงกับที่ gate ใช้เทียบ
     */
    internal fun longCooldownKeyFor(event: ProximityChangedEvent): String =
        listOf(
            event.regionIdentifier,
            event.uuid?.lowercase() ?: "-",
            event.major?.toString() ?: "-",
            event.minor?.toString() ?: "-",
        ).joinToString("|")

    /**
     * **pure function ล้วน ไม่รับ `Context` เลย** — ตรรกะตัดสินใจของคูลดาวน์
     * 30 นาทีแยกออกจาก I/O ของ `SharedPreferences` ตามแพทเทิร์นเดียวกับที่
     * `ProximityGate` แยกออกจาก `ProximityGateStore` (แก้ตามรอบรีวิว 16 ก.ย.
     * 2026, ADR-25 §3.1): โมดูล `app` มี `testImplementation` แค่ `kotlin-test`
     * ตัวเดียว ไม่มี mockito/Robolectric ให้ mock `Context`/`SharedPreferences`
     * ได้เลย ถ้าตรรกะเทียบเวลายังปนอยู่กับการเรียก `getSharedPreferences()`
     * ตรง ๆ จะเขียน unit test คลุมไม่ได้เลยโดยไม่เพิ่ม dependency ในไฟล์ build
     * (ซึ่งงานนี้ห้ามแตะ) — แยกเป็นฟังก์ชันนี้แล้วเทสต์เรียกตรง ๆ ได้ทันที
     *
     * `null` เมื่อไม่ติดคูลดาวน์ 30 นาที (ยิงได้) · ค่าที่ไม่ใช่ `null` คือจำนวน
     * มิลลิวินาทีตั้งแต่โพสต์สำเร็จครั้งล่าสุด (ใช้ต่อท้ายบรรทัดหลักฐาน
     * `sinceLastPostedMs=`) — **อ่านอย่างเดียว ไม่จด** แยกจาก [recordLongCooldownPosted]
     * ตามที่ ADR-25 §3.1 บังคับ (ตรวจกับจดต้องเป็นคนละฟังก์ชัน)
     *
     * ใช้ [SystemClock.elapsedRealtime] ไม่ใช่ wall clock (ADR-25 §3): ไม่กระโดด
     * ตามการซิงก์เวลาเครือข่าย/ผู้ใช้ปรับนาฬิกาเอง **ข้อแลก:** รีเซ็ตทุกครั้งที่
     * เครื่อง reboot — ถ้าค่าที่เก็บไว้มากกว่าค่าปัจจุบัน (reboot ระหว่างนั้น) ถือว่า
     * ไม่อยู่ใน cooldown
     *
     * @param lastPostedElapsedMillisOrZero เวลา ([SystemClock.elapsedRealtime])
     *   ที่โพสต์คีย์นี้สำเร็จครั้งล่าสุด · `0L` = ไม่เคยโพสต์คีย์นี้สำเร็จมาก่อน
     *   (ค่าเดียวกับ default ของ `SharedPreferences.getLong(key, 0L)` ตรง ๆ
     *   จึงไม่ต้องมี sentinel แยกต่างหาก)
     * @param nowElapsedMillis เวลาปัจจุบัน ([SystemClock.elapsedRealtime])
     * @param cooldownMillis ความยาวหน้าต่างคูลดาวน์ — ⚠️ **ไม่มีค่า default โดยตั้งใจ**
     *   (ADR-25 §8.4.1) เพื่อบังคับให้ทุกจุดเรียก (ทั้ง I/O wrapper และเทส) ระบุ
     *   หน้าต่างที่ตั้งใจทดสอบอย่างชัดเจน ป้องกันเทสเขียวผิดหน้าต่างเงียบ ๆ ถ้ามี
     *   ค่า default แอบเปลี่ยนความหมายในอนาคต
     */
    internal fun longCooldownSinceLastPostedMillisOrNull(
        lastPostedElapsedMillisOrZero: Long,
        nowElapsedMillis: Long,
        cooldownMillis: Long,
    ): Long? {
        if (lastPostedElapsedMillisOrZero == 0L) return null // ไม่เคยโพสต์คีย์นี้สำเร็จมาก่อน
        if (lastPostedElapsedMillisOrZero > nowElapsedMillis) return null // reboot แล้ว (elapsedRealtime รีเซ็ต)
        val since = nowElapsedMillis - lastPostedElapsedMillisOrZero
        return if (since < cooldownMillis) since else null
    }

    /**
     * ชั้น I/O ที่บางที่สุด — แค่ **"อ่านค่าของ key"** จาก `SharedPreferences` แล้ว
     * ส่งต่อให้ [longCooldownSinceLastPostedMillisOrNull] (pure) ตัดสินใจทั้งหมด
     * (ADR-25 §3.1) ไม่มีตรรกะเทียบเวลาอยู่ในฟังก์ชันนี้เลยแม้แต่บรรทัดเดียว
     */
    private fun longCooldownSinceLastPostedOrNull(
        context: Context,
        key: String,
        nowElapsed: Long,
    ): Long? {
        val prefs = context.getSharedPreferences(LONG_COOLDOWN_PREFS, Context.MODE_PRIVATE)
        return longCooldownSinceLastPostedMillisOrNull(
            lastPostedElapsedMillisOrZero = prefs.getLong(key, 0L),
            nowElapsedMillis = nowElapsed,
            cooldownMillis = longCooldownMillis,
        )
    }

    /**
     * เรียก**หลังรู้ผลว่า `ExampleNotifications.post()` คืน `true` แล้วเท่านั้น**
     * — ไม่ใช่ตอนผ่านประตู 30 นาที (ADR-25 §3.1) `commit()` ไม่ใช่ `apply()` ด้วย
     * เหตุผลเดียวกับ [consumeCooldown]: ต้องรอด process ที่ถูกฆ่าทันทีหลัง
     * `onReceive()` คืนค่า
     */
    private fun recordLongCooldownPosted(context: Context, key: String, nowElapsed: Long) {
        val prefs = context.getSharedPreferences(LONG_COOLDOWN_PREFS, Context.MODE_PRIVATE)
        prefs.edit().putLong(key, nowElapsed).commit()
    }
}
