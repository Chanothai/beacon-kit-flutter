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
 * ⚠️ **[rssi]/[txPower]/[beaconTag]/[storeError]/[droppedNoIdentityCount] ไม่ใช่ส่วนหนึ่งของสัญญา wire**
 * — มีไว้ให้ไฟล์หลักฐานของ host app เขียนลง log เท่านั้น (ตอบคำถาม "median ที่ได้มาจากสัญญาณแรงแค่ไหน" ซึ่ง
 * แยก 'บีคอนแบตอ่อน' ออกจาก 'ลูกค้ายืนไกล' ได้) ถ้าวันหนึ่งต่อ channel จริง **ห้าม
 * ใส่ฟิลด์เหล่านี้ลง payload** โดยไม่แก้ ADR-20 หัวข้อ 5 ก่อน
 */
data class ProximityChangedEvent(
    val regionIdentifier: String,
    /**
     * uuid ของ **region spec ที่ลงทะเบียนไว้** (`ScanFilter` ตั้ง mask `0xFF` เต็ม
     * 16 ไบต์ของ uuid เสมอ — เฟรมที่หลุดผ่านตัวกรองมาถึงการันตี uuid ตรงกับ region
     * แล้ว ถอดจากเฟรมซ้ำจึงไม่จำเป็น, ADR-20 หัวข้อ 1(ก)) ส่วน [major]/[minor]
     * **ถอดจากเฟรมจริง** เพราะ region แบบกว้าง (ADR-8 wildcard) ไม่การันตีสองค่านี้
     * เลย (ADR-20 หัวข้อ 1(ก) แก้ 11 ก.ย. 2026 / หัวข้อ 3)
     *
     * `uuid` เป็น `null` ได้กรณีเดียว: อ่านรายการ region ที่เก็บไว้ไม่สำเร็จหรือหา
     * region ของ `regionIdentifier` นี้ไม่เจอ — เคสนั้น sample ทั้งอันจะถูกทิ้งไป
     * ก่อนถึงจุดสร้าง event นี้แล้ว (ดู `BeaconScanReceiver.processProximity`) จึง
     * ไม่ควรเห็น `uuid == null` ในทางปฏิบัติ **ห้ามเดาค่าแทนถ้าเกิดขึ้นจริง**
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
    /**
     * ⚠️ log เท่านั้น ไม่ใช่สัญญา wire — **ตัวแยกเชิงกายภาพว่าบรรทัดนี้เป็นของ
     * บีคอนตัวไหน** (คนละคำถามกับ [uuid]/[major]/[minor] ซึ่งเป็นตัวแยกเชิงตรรกะ)
     *
     * ## ทำไมต้องมี — และทำไมที่มาเปลี่ยนไปตั้งแต่ 11 ก.ย. 2026
     *
     * ก่อนหน้านี้ gate key คือ `"<regionIdentifier>|<MAC>"` (ADR-20 หัวข้อ 3 ฉบับ
     * 9 ก.ย. 2026) และฟิลด์นี้ถอด MAC ออกจาก key ได้เลย — **key เปลี่ยนเป็น
     * `"<regionIdentifier>|<uuid>|<major>|<minor>"` แล้ว (ADR-20 หัวข้อ 3 แก้ 11
     * ก.ย. 2026) MAC จึงไม่อยู่ใน key อีกต่อไป** ฟิลด์นี้ต้องดึงจาก
     * `ScanResult.device?.address` ตรง ๆ ต่อ sample ที่มี `ScanResult` จริงแทน
     *
     * **ผลที่ต้องยอมรับ:** transition ที่มาจาก [ProximityGate.sweepStale] ไม่มี
     * `ScanResult` คู่มาด้วย (เป็นการตรวจความเงียบ ไม่ใช่ sample ใหม่) จึงได้
     * `beaconTag = null` เสมอ — บรรทัด `stale` จะเห็น `mac=n/a` เสมอนับจากนี้
     * (เป็นผลที่ ADR-20 หัวข้อ 3 ระบุไว้ล่วงหน้าแล้ว ไม่ใช่ regression)
     *
     * เหตุผลเดิมที่ยังยืนอยู่: เมื่อ region หนึ่งเห็นบีคอนหลายตัว (ปกติมากสำหรับ
     * region กว้างของ ADR-8) บรรทัดของคนละบีคอน **อ่านแล้วแยกไม่ออกเลย** ทำให้
     * `stale` สามบรรทัดติดกันดูเหมือนบั๊กยิงซ้ำ ทั้งที่เป็นบีคอนสามตัว (เกิดจริงใน
     * ไฟล์หลักฐาน 9 ก.ย. 2026 ช่วง 16:45-16:48)
     *
     * เก็บแค่ **สองไบต์ท้ายของ MAC** ไม่ใช่ทั้งค่า: พอแยกบีคอนในรอบทดสอบได้จริง
     * โดยไม่ต้องเขียนที่อยู่เต็มลงไฟล์ที่ถูก commit เข้า repo (`docs/test-data/`)
     */
    val beaconTag: String?,
    /**
     * ⚠️ log เท่านั้น ไม่ใช่สัญญา wire — เหตุผลที่ `ProximityGateStore` ล้มเหลว
     * ในรอบนี้ (`null` = อ่าน/เขียนสำเร็จ) **หรือ** ข้อความรายงาน migration ของ
     * รูปร่าง state บนดิสก์ (`"migrated dropped=<n>"`, ADR-20 หัวข้อ 3 "Migration
     * ของ state บนดิสก์") — สองเรื่องนี้แยกกันด้วยเนื้อข้อความ (คนละ prefix)
     * เพราะ **migration สำเร็จ ≠ ดิสก์พัง** ดู kdoc ของ
     * `ProximityGateStore.lastMigrationDroppedCount` ว่าทำไมต้องแยก
     *
     * จำเป็นเพราะ **มีเส้นทางที่ state หายโดยไม่มี `stale` ออกมาเลย**: `load()`
     * ล้มเหลว → กู้ได้ map ว่าง → push ถัดไปได้ `from=none` โดยไม่มีอะไรฟ้อง และ
     * `statesFromJson()` ที่ข้าม key ที่ถอดไม่ออกทีละตัวก็ให้ผลเดียวกันเฉพาะ key
     * นั้น เดิมร่องรอยไปอยู่ใน logcat อย่างเดียวซึ่งหายไปแล้วตอนอ่านผลย้อนหลัง
     */
    val storeError: String?,
    /**
     * ⚠️ log เท่านั้น ไม่ใช่สัญญา wire — จำนวน `ScanResult` ใน **batch เดียวกับ
     * event นี้** ที่ถูกทิ้งไปทั้งอันเพราะประกอบ identity (uuid, major, minor)
     * ไม่ได้ (ถอด major/minor จากเฟรมไม่สำเร็จ หรือหา uuid จาก region spec ไม่เจอ)
     * — ตัวเลขวินิจฉัยล้วน ไม่มีตรรกะไหนอ่านไปตัดสินใจ (ADR-20 หัวข้อ 3)
     *
     * เป็น**ตัวนับระดับ batch** ไม่ใช่ระดับ key เหมือน
     * `ProximityKeyState.droppedNoTxPowerCount` เพราะ sample ที่ถอด identity ไม่ได้
     * ไม่มี key ให้ผูกตัวนับด้วยตั้งแต่แรก — **ห้าม fallback ไปใช้ major/minor จาก
     * region spec เงียบ ๆ เมื่อถอดจากเฟรมไม่ได้** เหตุผล: จะพากลับไปสู่บั๊กเดิมเป๊ะ
     * (บรรทัดหลักฐานอ่านไม่ออกว่าเป็นบีคอนตัวไหนโดยไม่มีอะไรฟ้อง — ดูหัวข้อ 8)
     * ฟิลด์นี้คือสิ่งที่ทำให้ความล้มเหลวนั้น**ฟ้องออกมาแทน**
     *
     * มีค่า default `0` เพื่อไม่ให้ผู้เรียกเดิม (เช่นเทสต์ที่สร้าง event ตรง ๆ โดย
     * ไม่เกี่ยวกับตัวนับนี้) ต้องแก้ตามทุกจุด — ผู้เรียกจริงใน
     * `BeaconScanReceiver.processProximity()` ส่งค่าที่นับได้จริงเสมอ ไม่พึ่ง
     * default นี้
     */
    val droppedNoIdentityCount: Int = 0,
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
