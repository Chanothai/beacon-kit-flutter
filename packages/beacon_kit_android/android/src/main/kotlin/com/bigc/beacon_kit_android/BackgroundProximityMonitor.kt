package com.bigc.beacon_kit_android

/**
 * event "ความใกล้เปลี่ยน" ที่คำนวณได้ฝั่ง Android ตอนไม่มี Flutter engine
 *
 * ฟิลด์ 9 ตัวแรกคือ **สัญญาที่ ADR-20 หัวข้อ 5 นิยามไว้** (`proximityChanged`:
 * `{regionIdentifier, uuid, major, minor, from, to, reason, medianMeters?,
 * timestampMillis}`) — นิยามวันนี้เพื่อให้ iOS ทำตามได้โดยไม่ต้องต่อรองสัญญาใหม่
 * **แต่วันนี้ยังไม่ส่งขึ้น Dart: ไม่มี MethodChannel ไม่มี EventChannel ไม่มี
 * stream** ตั้งใจไม่ล็อก public API ก่อนพิสูจน์กลไกจริงบนเครื่อง
 *
 * ⚠️ **[rssi]/[txPower] ไม่ใช่ส่วนหนึ่งของสัญญา wire** — มีไว้ให้ไฟล์หลักฐานของ
 * host app เขียนลง log เท่านั้น (ตอบคำถาม "median ที่ได้มาจากสัญญาณแรงแค่ไหน" ซึ่ง
 * แยก 'บีคอนแบตอ่อน' ออกจาก 'ลูกค้ายืนไกล' ได้) ถ้าวันหนึ่งต่อ channel จริง **ห้าม
 * ใส่สองฟิลด์นี้ลง payload** โดยไม่แก้ ADR-20 หัวข้อ 5 ก่อน
 */
data class ProximityChangedEvent(
    val regionIdentifier: String,
    /**
     * uuid/major/minor ของ **region spec ที่ลงทะเบียนไว้** ไม่ใช่ค่าที่ถอดจากเฟรม
     * — ฝั่ง Kotlin ไม่มี parser (ADR-14 หัวข้อ 4.1) จึงไม่มีทางรู้ค่ารายเฟรม
     *
     * `null` ได้จริงสองกรณี: region นั้นเป็นแบบกว้างที่ไม่ระบุ major/minor
     * (ADR-8 wildcard) หรืออ่านรายการ region ที่เก็บไว้ไม่สำเร็จ — **ต้องเป็น
     * `null` ตามจริง ห้ามเดาค่าแทน**
     */
    val uuid: String?,
    val major: Int?,
    val minor: Int?,
    val from: ProximityBucket?,
    /** `null` = "gate ไม่มีคำตอบแล้ว" (stale) **ไม่ใช่** [ProximityBucket.FAR] */
    val to: ProximityBucket?,
    val reason: ProximityTransitionReason,
    val medianMeters: Double?,
    val timestampMillis: Long,
    /** ⚠️ log เท่านั้น ไม่ใช่สัญญา wire — ดู kdoc ของคลาส */
    val rssi: Int?,
    /** ⚠️ log เท่านั้น ไม่ใช่สัญญา wire — ดู kdoc ของคลาส */
    val txPower: Int?,
)

/**
 * ทางออกของชั้น proximity (ADR-20 ชั้นที่ 2) ไปยัง host app
 *
 * แยกเป็น `object` ของตัวเองแทนการเพิ่มเมธอดใน `BackgroundRegionMonitor` โดยตั้งใจ:
 * ชั้น 1 (region enter/exit) มีหลักฐานจากอุปกรณ์จริงระดับ `observed` แล้ว (ADR-14)
 * ส่วนชั้นนี้ยังไม่เคยรันบนเครื่องจริงเลยแม้แต่ครั้งเดียว จึงยังเป็น POC
 * — การแยกไฟล์ทำให้ `git diff` ของรอบนี้พิสูจน์ได้ทันทีว่า**ไม่มีบรรทัดใดของชั้น 1
 * ถูกแตะ** ซึ่งเป็นเงื่อนไขที่ ADR-20 หัวข้อ 1 บังคับไว้
 *
 * pattern เดียวกับ [BackgroundRegionMonitor.setRegionStateObserver] เป๊ะ (host app
 * ตั้ง observer ใน `Application.onCreate()` ซึ่งเป็นจุดเดียวที่ทำงานเสมอไม่ว่า
 * process จะเกิดด้วยเหตุใด) — และด้วยเหตุผลเดียวกัน **SDK ไม่ตั้งให้เอง**
 *
 * ⚠️ **ยังไม่มี `flutterSink` คู่ขนานเหมือนชั้น 1 และไม่มีคิว event ลงดิสก์** —
 * ADR-20 หัวข้อ 5 ระบุว่ารอบนี้ยังไม่ส่งขึ้น Dart การมีคิวไว้ก่อนจะเป็นการล็อก
 * สัญญาที่ยังไม่พิสูจน์ ผลที่ต้องยอมรับ: event ที่เกิดตอนไม่มี observer **หายไป
 * จริง ๆ** (ไม่ใช่ค้างรอ) — รับได้เพราะ example app ตั้ง observer ตั้งแต่
 * `Application.onCreate()` ก่อน `onReceive()` เสมอ
 */
object BackgroundProximityMonitor {

    fun interface ProximityObserver {
        fun onProximityChanged(event: ProximityChangedEvent)
    }

    @Volatile
    private var observer: ProximityObserver? = null

    fun setProximityObserver(newObserver: ProximityObserver?) {
        observer = newObserver
    }

    /**
     * ส่ง [event] ให้ observer — **ครบทุก transition ไม่กรองอะไรทั้งสิ้น**
     *
     * `closer` / `farther` / `stale` ถูกส่งออกหมดตามสัญญาที่ ADR-20 หัวข้อ 5 นิยาม
     * ไว้ให้ iOS ทำตาม **การตัดสินว่า event ไหน "ควรรบกวนผู้ใช้" เป็นนโยบายของแอป
     * ไม่ใช่ความสามารถของแพลตฟอร์ม** จึงอยู่ที่ `ExampleProximityWatcher` แนวเดียว
     * กับตำแหน่งของ cooldown (ADR-20 หัวข้อ 6 · ADR-11 หัวข้อ 7 เรื่องตำแหน่งของ
     * debounce) — ถ้ากรองที่นี่ ชั้น 2 จะไม่มีสัญญาณ "ออก/วัดไม่ได้" ให้ใครเลย
     * ทั้งที่ [ProximityGate.sweepStale] มีอยู่เพื่อสิ่งนี้โดยเฉพาะ และรอบทดสอบบน
     * เครื่องจริงจะไม่มีบรรทัดหลักฐานที่ตอบได้ว่า `exitMeters`/`staleAfter` ใช้ได้
     * จริงหรือไม่
     *
     * ห่อ observer ด้วย `runCatching` ด้วยเหตุผลเดียวกับ
     * `BackgroundRegionMonitor.emit()`: โค้ดของ host app ที่ throw ต้องไม่ลาก
     * เส้นทางเบื้องหลังของ SDK ล้มไปด้วย
     */
    fun emit(event: ProximityChangedEvent) {
        runCatching { observer?.onProximityChanged(event) }
    }
}
