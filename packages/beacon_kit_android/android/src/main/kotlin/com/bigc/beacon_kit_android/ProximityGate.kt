package com.bigc.beacon_kit_android

import kotlin.math.pow

/**
 * bucket ความใกล้ที่ [ProximityGate] ยืนยันได้ — **ไม่มี `unknown`**
 *
 * ต่างจาก `BeaconProximity` ฝั่ง Dart ที่ reuse enum เดิมซึ่งมี `unknown` ติดมาด้วย
 * (แล้วต้องประกาศ invariant ว่า `unknown` ห้ามรั่วออกทางเอาต์พุต — ADR-19 หัวข้อ
 * 6(ช)) — ฝั่ง Kotlin สร้าง enum ใหม่ได้เลยจึงตัด `unknown` ทิ้งตั้งแต่ระดับชนิด
 * ข้อมูล "ไม่มีคำตอบ" แทนด้วย `null` ของ Kotlin ทุกจุด
 *
 * [wireName] คือชื่อที่ใช้ใน payload ของ event (ADR-20 หัวข้อ 5) และในไฟล์หลักฐาน
 * — **ต้องตรงกับชื่อ enum ฝั่ง Dart** (`BeaconProximity.near` ฯลฯ) ไม่ใช่ชื่อค่าคง
 * ที่ตัวใหญ่ของ Kotlin เพราะ iOS/Dart จะอ่านค่านี้ตรง ๆ ตอนสัญญาถูกต่อจริง
 */
enum class ProximityBucket(val wireName: String) {
    IMMEDIATE("immediate"),
    NEAR("near"),
    FAR("far"),
    ;

    companion object {
        /** ถอดกลับจาก [wireName] — `null` เมื่อไม่ตรงกับตัวใด (ค่าที่เก็บไว้เสียหาย) */
        fun fromWireName(value: String?): ProximityBucket? =
            entries.firstOrNull { it.wireName == value }
    }
}

/**
 * อันดับความใกล้ (ยิ่งน้อยยิ่งใกล้) — ใช้เทียบว่า candidate "ใกล้กว่า" หรือ "ไกลกว่า"
 * bucket ที่ยืนยันอยู่ ตรงกับ `_rankOf` ของ `proximity_gate.dart` เป๊ะ
 *
 * ฝั่ง Dart ต้องมีสาขา `unknown` ที่ `throw StateError` เพราะ enum ที่ reuse มามี
 * ค่านั้นอยู่ — ที่นี่ไม่มีสาขานั้นเพราะ [ProximityBucket] ไม่มี `unknown` ตั้งแต่แรก
 * (ไม่ใช่การละเลย แต่คือความต่างที่ตั้งใจ ดู kdoc ของ [ProximityBucket])
 */
internal fun rankOfBucket(bucket: ProximityBucket): Int = when (bucket) {
    ProximityBucket.IMMEDIATE -> 0
    ProximityBucket.NEAR -> 1
    ProximityBucket.FAR -> 2
}

/** เหตุผลของ transition — ตรงกับ `ProximityTransitionReason` ฝั่ง Dart */
enum class ProximityTransitionReason(val wireName: String) {
    /** ใกล้ขึ้น และผ่านเกณฑ์ dwell ติดกันครบ [ProximityGate.dwellSamples] แล้ว */
    CLOSER("closer"),

    /** ไกลลง — ยืนยันทันทีไม่ต้อง dwell (ADR-19 หัวข้อ 6(ค)) */
    FARTHER("farther"),

    /**
     * เงียบเกิน [ProximityGate.staleAfterMillis] — "วัดไม่ได้อีกแล้ว" ไม่ใช่ "ไกล"
     * `to` เป็น `null` เสมอเมื่อ reason นี้ (ADR-19 หัวข้อ 6(ฉ))
     */
    STALE("stale"),
    ;

    companion object {
        fun fromWireName(value: String?): ProximityTransitionReason? =
            entries.firstOrNull { it.wireName == value }
    }
}

/**
 * ผลลัพธ์ตอน bucket ของ key หนึ่งเปลี่ยนจริง — คืนจาก [ProximityGate.push] /
 * [ProximityGate.sweepStale] **เฉพาะตอนเปลี่ยนจริงเท่านั้น** ไม่ใช่ทุก sample
 *
 * `to == null` แปลว่า "gate ไม่มีคำตอบให้แล้ว" **ไม่ใช่ [ProximityBucket.FAR]** —
 * เกิดได้ทางเดียวคือ [ProximityTransitionReason.STALE] ผู้เรียกที่อยากรู้ว่า "ไกล
 * แล้วจริง ๆ" ต้องเช็ค `to == FAR` ตรง ๆ ไม่ใช่เช็คว่าไม่ใช่ near/immediate
 *
 * [key] เป็น `String` ไม่ใช่ (uuid, major, minor) แบบฝั่ง Dart — ดู kdoc ของ
 * [ProximityGate] หัวข้อ "key คืออะไรในเส้นทาง Android"
 */
data class ProximityTransition(
    val key: String,
    val from: ProximityBucket?,
    val to: ProximityBucket?,
    val reason: ProximityTransitionReason,
    /**
     * median ของหน้าต่างระยะ (เมตร) ที่ใช้ตัดสิน transition นี้ — `null` เมื่อ
     * reason เป็น [ProximityTransitionReason.STALE] (ไม่มีหน้าต่างให้คิดแล้ว)
     */
    val medianMeters: Double?,
)

/**
 * สถานะภายในของ key เดียว — **public เพราะ `ProximityGateStore` ต้อง serialize
 * มันลงดิสก์ทุก sighting** (ADR-20 หัวข้อ 3) ต่างจากฝั่ง Dart ที่ `_KeyState`
 * เป็น private ได้ เพราะ process ฝั่งนั้นไม่ถูกฆ่ากลาง dwell
 *
 * เป็น **immutable data class**: [ProximityGate] เปลี่ยนสถานะด้วย `copy()` แล้ว
 * ใส่กลับลง map เสมอ ไม่แก้ของเดิมในที่ — ทำให้ snapshot ที่ store ถืออยู่ไม่ถูก
 * แก้ใต้เท้าโดยไม่รู้ตัว (window เป็น `List` ไม่ใช่ `MutableList` ด้วยเหตุผลเดียวกัน)
 */
data class ProximityKeyState(
    /** bucket ที่ยืนยันแล้ว — `null` = ยังไม่เคยยืนยันอะไรเลยสำหรับ key นี้ */
    val confirmedBucket: ProximityBucket? = null,
    /** bucket ที่ใกล้กว่าและกำลังรอ dwell ครบ — `null` = ไม่มีตัวไหนรออยู่ */
    val pendingCloserBucket: ProximityBucket? = null,
    val pendingCloserCount: Int = 0,
    /**
     * จำนวน sample ที่ถูกทิ้งเพราะไม่มี `txPower` (ADR-19 หัวข้อ 6(จ)) — ตัวเลข
     * วินิจฉัยล้วน ไม่มีตรรกะไหนอ่านไปตัดสินใจ
     */
    val droppedNoTxPowerCount: Int = 0,
    /** หน้าต่างระยะ (เมตร) เรียงตามลำดับที่เข้ามา ตัวใหม่ต่อท้าย */
    val window: List<Double> = emptyList(),
    /**
     * เวลา (จาก [ProximityGate.clock], epoch millis) ของ sample **ที่ใช้ตัดสินใจ
     * ได้จริง** ล่าสุด — sample ที่ถูกทิ้งห้ามขยับค่านี้ ไม่งั้น staleness จะ
     * ตรวจจับ "มีสัญญาณเข้ามาแต่ใช้อะไรไม่ได้เลย" ไม่ได้
     */
    val lastSampleAt: Long? = null,
)

/**
 * ประมาณระยะ (เมตร) จาก RSSI + txPower — port ตรงจาก `distance_estimator.dart`
 *
 * `d = 10 ^ ((txPower − rssi) / (10 × n))` (log-distance path loss, Rappaport
 * §4.11.3 — `docs/sources/rssi_path_loss_model.md` หัวข้อ 1-2)
 *
 * **pure function ล้วน** ตัวเลขเข้า → ตัวเลขออก และ [pathLossExponent] เป็น
 * พารามิเตอร์บังคับ **ห้ามมี default ซ่อนในฟังก์ชันนี้** ด้วยเหตุผลเดียวกับฝั่ง
 * Dart: `n` ผันผวนตามสถานที่จริงมาก การใส่ default ที่นี่คือการกลืนการตัดสินใจ
 * เชิงสถานที่ไปเงียบ ๆ (ค่า default ระดับ POC อยู่ที่ [ProximityGate] เท่านั้น)
 *
 * ⚠️ ค่าที่คืน **ไม่ใช่ระยะที่แม่นยำ** ห้ามเอาไปแสดงราวกับเป็นตำแหน่งจริง
 */
fun estimateDistanceMeters(rssi: Int, txPower: Int, pathLossExponent: Double): Double =
    10.0.pow((txPower - rssi) / (10.0 * pathLossExponent))

/**
 * ชั้นตัดสินใจ "ใกล้พอหรือยัง" ฝั่ง Kotlin — **port ตรงจาก
 * `packages/beacon_kit/lib/src/proximity/proximity_gate.dart`** ซึ่งเป็น
 * reference implementation ตาม ADR-20 หัวข้อ 2 (ห้ามแก้ฝั่ง Dart ในรอบนี้)
 *
 * ## pure Kotlin ล้วน — ห้าม import `android.*` ในไฟล์นี้เด็ดขาด
 *
 * ไม่มี I/O ไม่แตะ BLE API ไม่มี timer ในตัวเอง และ**ไม่เรียกนาฬิกาของระบบเอง**
 * ([clock] ต้องฉีดเข้ามาเสมอ) เหตุผลเดียวกับฝั่ง Dart: เทสต์ต้องคุมเวลาได้แบบ
 * deterministic โดยไม่ต้องมีอุปกรณ์จริง — ถ้าไฟล์นี้เผลอเรียก
 * `System.currentTimeMillis()` แม้ตัวเดียว เทสต์ stale ทั้งหมดจะกลายเป็น Track B
 * ทันที การเก็บสถานะลงดิสก์เป็นหน้าที่ของ `ProximityGateStore` คนละไฟล์
 *
 * ## key คืออะไรในเส้นทาง Android (ต่างจากฝั่ง Dart โดยตั้งใจ)
 *
 * ฝั่ง Dart ใช้ `(uuid, major, minor)` เพราะมี parser ถอดทุกเฟรมให้อยู่แล้ว —
 * ฝั่ง Kotlin **ไม่มี parser** (ADR-14 หัวข้อ 4.1) จึงไม่มีค่าเหล่านั้นรายเฟรม
 * ผู้เรียกจึงประกอบ key เองเป็น `"<regionIdentifier>|<ScanResult.device.address>"`
 * (ดู `BeaconScanReceiver`) — คลาสนี้มอง key เป็นสตริงทึบ ไม่ตีความ
 *
 * ## สิ่งที่ **ตั้งใจไม่ port** มาจากฝั่ง Dart
 *
 * `appleProximityWindow` / `_appleBucketCandidate` (เส้นทางที่ OS ถอด `CLProximity`
 * ให้แล้ว, ADR-19 หัวข้อ 4 ข้อ 1) **ไม่มีในไฟล์นี้** เพราะ Android ไม่มี API ที่
 * ให้ bucket ความใกล้มาเลย มีแต่ RSSI ดิบใน `ScanResult` — เส้นทางนั้นจึงเป็นไป
 * ไม่ได้ในทางกายภาพ ไม่ใช่ลืม port (ดูคอมเมนต์ในตัว [push] ตรงจุดที่ Dart แตก
 * สองทาง)
 *
 * ## ค่า default = ตาราง ADR-19 หัวข้อ 8 เป๊ะ
 *
 * เป็นค่า **POC เท่านั้น ยังไม่ calibrate จากสาขาจริง** ห้ามใช้เป็นค่า production
 * โดยไม่ผ่านรอบเก็บข้อมูลภาคสนามก่อน (ADR-19 หัวข้อ 7/8) — ADR-20 หัวข้อ 6 บันทึก
 * ไว้ว่ารอบนี้ยังไม่มี API ให้ตั้งค่าจาก Dart โดยตั้งใจ
 */
class ProximityGate(
    /**
     * แหล่งเวลา (epoch millis) — **ฉีดผ่าน constructor เสมอ ไม่มี default**
     * ผู้เรียกจริงส่ง `System::currentTimeMillis` เข้ามา เทสต์ส่งนาฬิกาปลอม
     */
    val clock: () -> Long,
    /** median ต้อง ≤ ค่านี้ ถึงจะเริ่มนับเป็น near/immediate (ทิศ "เข้า") */
    val enterMeters: Double = 3.0,
    /** median ต้อง > ค่านี้ ถึงจะนับว่าออกจาก near/immediate (ทิศ "ออก") */
    val exitMeters: Double = 5.0,
    /** median ≤ ค่านี้ = immediate แทน near (ไม่มี hysteresis แยกสำหรับขอบนี้) */
    val immediateMeters: Double = 1.0,
    /** จำนวน sample สูงสุดในหน้าต่างที่ใช้หา median ต่อ key */
    val windowSize: Int = 5,
    /** จำนวน sample ติดกันขั้นต่ำก่อนยืนยัน bucket ที่ "ใกล้กว่า" */
    val dwellSamples: Int = 3,
    /** path loss exponent `n` ที่ส่งต่อให้ [estimateDistanceMeters] */
    val pathLossExponent: Double = 2.5,
    /**
     * เงียบเกินกี่มิลลิวินาทีถึงถือว่า "วัดไม่ได้อีกแล้ว"
     *
     * ⚠️ **60 วินาที — เบี่ยงจาก ADR-19 หัวข้อ 8 (10 วินาที) โดยตั้งใจ ตาม ADR-20
     * หัวข้อ 7 พร้อมข้อมูลจากเครื่องจริงกำกับ** ค่า 10 วินาทีของ ADR-19 คิดจากอัตรา
     * ~1 sample/วินาทีของ foreground ranging ฝั่ง Apple (= ยอมให้พลาด ~10 รอบ) แต่
     * เส้นทางเบื้องหลังของ Android ส่ง sighting มาเป็น **batch ที่ห่างกันมัธยฐาน
     * 12-17.5 วินาที** (วัดจริงจาก `docs/test-data/2026-09-09_android_proximity_background.log`)
     * ค่า 10 วินาทีจึงล้าง state ทิ้ง **38 จาก 52 ช่องว่าง** ทำให้ dwell เริ่มนับหนึ่ง
     * ใหม่ตลอดและ hysteresis ไม่เคยได้ทำงานเลย — 60 วินาทีคือ ~3.5 เท่าของช่วงห่าง
     * จริง ซึ่งเป็น**ตรรกะเดียวกับ ADR-19 เป๊ะ** (หลายเท่าของอัตรา sample จริง)
     * เพียงแต่แทนค่าอัตราที่วัดได้จริงของแพลตฟอร์มนี้ลงไป
     */
    val staleAfterMillis: Long = 60_000L,
) {
    init {
        require(exitMeters > enterMeters) {
            "exitMeters ต้องมากกว่า enterMeters เสมอ — ไม่งั้น hysteresis dead zone " +
                "ของ ADR-19 หัวข้อ 6(ข) จะกลับด้าน (ออกง่ายกว่าเข้า) ซึ่งไม่ป้องกัน flap " +
                "ตามที่ออกแบบไว้"
        }
    }

    /**
     * `LinkedHashMap` ไม่ใช่ `HashMap` — ลำดับ key ต้องคงที่ เพื่อให้ลำดับของ
     * transition ที่ [sweepStale] คืน (และลำดับที่เขียนลง JSON) ทำซ้ำได้ในเทสต์
     */
    private val states = LinkedHashMap<String, ProximityKeyState>()

    /**
     * bucket ที่ยืนยันแล้วของ [key] — `null` เมื่อไม่มี state (ไม่เคย push หรือ
     * หลุด stale ไปแล้ว) หรือมี state แต่ยังไม่เคยยืนยัน bucket ใดเลย
     */
    fun currentBucket(key: String): ProximityBucket? = states[key]?.confirmedBucket

    /** state ดิบของ [key] — สำหรับ `ProximityGateStore` และเทสต์เท่านั้น */
    fun stateOf(key: String): ProximityKeyState? = states[key]

    /**
     * สถานะของทุก key ณ ตอนนี้ (คัดลอกออกมา ไม่ใช่ view) — `ProximityGateStore`
     * เอาไป serialize ลงดิสก์ทุกครั้งที่จบ batch หนึ่ง
     */
    fun snapshotStates(): Map<String, ProximityKeyState> = LinkedHashMap(states)

    /**
     * เขียนทับสถานะทั้งหมดด้วยของที่กู้มาจากดิสก์ — **ต้องเรียกก่อน [push] เสมอ
     * ในเส้นทางเบื้องหลัง** ไม่งั้น dwell จะเริ่มนับหนึ่งใหม่ทุก sighting เพราะ
     * process ถูกฆ่าคั่นกลาง แล้ว `dwellSamples = 3` จะไม่มีวันครบ (ADR-20 หัวข้อ 3)
     */
    fun restoreStates(restored: Map<String, ProximityKeyState>) {
        states.clear()
        states.putAll(restored)
    }

    /**
     * ป้อน sample หนึ่งตัวของ [key] — คืน [ProximityTransition] **เฉพาะตอน bucket
     * ที่ยืนยันแล้วเปลี่ยนจริง** มิฉะนั้น `null`
     *
     * ลำดับการตัดสินตรงกับ `ProximityGate.push` ฝั่ง Dart เป๊ะ:
     * 1. อ่าน [clock] ครั้งเดียว
     * 2. เช็ค stale **ก่อนอย่างอื่นทั้งหมด**
     * 3. `txPower == null` → ทิ้ง sample + นับ counter เท่านั้น
     * 4. คำนวณระยะ → หน้าต่าง → median → classify → dwell
     *
     * [txPower] เป็น `Int?` โดยตั้งใจ — **ห้าม default ค่าเงียบ ๆ** ที่ฝั่งผู้เรียก
     * (ADR-19 หัวข้อ 6(จ)) ตัวเลข txPower ที่เดาเอาจะทำให้ระยะที่คำนวณได้ผิดเป็น
     * เท่าตัวโดยไม่มีอะไรฟ้อง
     */
    fun push(key: String, rssi: Int, txPower: Int?): ProximityTransition? {
        val now = clock()
        val existing = states[key]

        // ---- stale ก่อนอื่นทั้งหมด (ADR-19 หัวข้อ 6(ฉ)) ----
        // ใช้ clock() ไม่ใช่เวลาที่ติดมากับ sample เพราะความเงียบที่ต้องจับคือ
        // "ไม่มี push() เข้ามานานแค่ไหนตามเวลาจริง"
        var state = existing
        if (existing != null && isStale(existing, now)) {
            // รีเซ็ต **ทุกฟิลด์** ไม่ใช่แค่ confirmed — key ที่ค้าง dwell อยู่แล้ว
            // หายไปนาน ต้องไม่กลับมาสานต่อ dwell เดิมเหมือนข้อมูลต่อเนื่องกัน
            val fresh = ProximityKeyState()
            states[key] = fresh
            state = fresh
            val hadConfirmed = existing.confirmedBucket
            if (hadConfirmed != null) {
                // ทิ้ง sample ของรอบนี้ไปพร้อมกับ transition นี้โดยตั้งใจ — push()
                // คืนได้ทีละ 1 transition sample ที่จุดชนวน stale จะถูกประมวลผล
                // ใหม่ในรอบถัดไปด้วย state ที่รีเซ็ตแล้ว (ตรงกับฝั่ง Dart)
                return ProximityTransition(
                    key = key,
                    from = hadConfirmed,
                    to = null,
                    reason = ProximityTransitionReason.STALE,
                    medianMeters = null,
                )
            }
            // ไม่เคย confirm มาก่อน (แค่ค้าง dwell ตอนหายไป) — ไม่มีอะไรให้ประกาศ
            // ว่าหลุด ใช้ sample ของรอบนี้เริ่ม state ใหม่ต่อได้เลย
        }

        val current = state ?: ProximityKeyState()

        // เส้นทางที่ฝั่ง Dart แตกเป็นสองทางตรงนี้: ถ้า `advertisement.proximity`
        // ไม่เป็น null (iOS ranging, OS ถอด CLProximity ให้แล้ว) มันจะเข้าเส้นทาง
        // mode-of-window ของ Apple แทนการคำนวณระยะเอง — **เส้นทางนั้นถูกตัดออก
        // จากไฟล์นี้โดยตั้งใจ ไม่ใช่ลืม port**: Android ไม่มี API ที่ให้ bucket
        // ความใกล้มาเลย `ScanResult` มีแต่ RSSI ดิบ จึงเหลือเส้นทางเดียวคือ
        // คำนวณระยะเองเสมอ (ดู kdoc ของคลาสนี้)
        if (txPower == null) {
            // ADR-19 หัวข้อ 6(จ): ตัดสินอะไรไม่ได้เลย — นับ counter อย่างเดียว
            // **ห้ามแตะ lastSampleAt** เพราะ sample ที่ทิ้งไม่ควรต่ออายุ freshness
            // ให้ bucket ที่ยืนยันไว้ก่อนหน้า
            states[key] = current.copy(
                droppedNoTxPowerCount = current.droppedNoTxPowerCount + 1,
            )
            return null
        }

        val distanceMeters = estimateDistanceMeters(
            rssi = rssi,
            txPower = txPower,
            pathLossExponent = pathLossExponent,
        )
        val window = (current.window + distanceMeters).takeLast(windowSize)
        // ADR-19 หัวข้อ 6(ก): median ไม่ใช่ average
        val medianMeters = medianOf(window)
        val candidate = classify(medianMeters, current.confirmedBucket)

        return applyDwell(
            key = key,
            state = current.copy(window = window, lastSampleAt = now),
            candidate = candidate,
            medianMeters = medianMeters,
        )
    }

    /**
     * ตรวจทุก key ว่าเงียบเกิน [staleAfterMillis] แล้วหรือยัง **โดยไม่ต้องรอ
     * sample ใหม่** — จำเป็นเพราะเคสหลักคือ "ลูกค้าเดินออกจากร้าน" ซึ่งแปลว่าไม่มี
     * sample ให้ [push] จับความเงียบได้เองอีกเลย
     *
     * ในเส้นทางเบื้องหลังของ Android ผู้เรียกคือ `BeaconScanReceiver` ตอนที่ระบบ
     * ปลุกมันขึ้นมา ไม่ใช่ timer — **timer เป็นไปไม่ได้จริงในเส้นทางนี้** เพราะไม่มี
     * process อยู่ให้ timer เดิน (ADR-20 หัวข้อ 4) ผลที่ต้องยอมรับคือ stale ถูกค้น
     * พบตอน sighting ถัดไป ไม่ใช่ที่วินาทีที่ 10 พอดี
     */
    fun sweepStale(): List<ProximityTransition> {
        val now = clock()
        val transitions = mutableListOf<ProximityTransition>()

        for (key in states.keys.toList()) {
            val state = states[key] ?: continue
            if (!isStale(state, now)) continue

            states[key] = ProximityKeyState()
            val hadConfirmed = state.confirmedBucket
            if (hadConfirmed != null) {
                transitions.add(
                    ProximityTransition(
                        key = key,
                        from = hadConfirmed,
                        to = null,
                        reason = ProximityTransitionReason.STALE,
                        medianMeters = null,
                    ),
                )
            }
        }

        return transitions
    }

    /**
     * เงียบเกิน [staleAfterMillis] แล้วหรือยัง — `lastSampleAt == null` (ยังไม่เคย
     * มี sample ที่ใช้ตัดสินได้เลย) ถือว่า **ยังไม่ stale** ตรงกับ `_resetIfStale`
     * ฝั่ง Dart ที่คืน `null` ทันทีในกรณีนั้น
     */
    private fun isStale(state: ProximityKeyState, now: Long): Boolean {
        val lastSampleAt = state.lastSampleAt ?: return false
        return now - lastSampleAt > staleAfterMillis
    }

    /**
     * จัด candidate bucket จาก median ด้วย hysteresis (ADR-19 หัวข้อ 6(ข)) —
     * ทิศ "เข้า" ใช้ [enterMeters] ทิศ "ออก" ใช้ [exitMeters] จึงต้องรู้ bucket ที่
     * ยืนยันอยู่ตอนนี้ ([previousConfirmed]) ก่อนถึงจะตัดสินได้
     */
    internal fun classify(
        medianMeters: Double,
        previousConfirmed: ProximityBucket?,
    ): ProximityBucket {
        val wasClose = previousConfirmed == ProximityBucket.NEAR ||
            previousConfirmed == ProximityBucket.IMMEDIATE
        val isClose = if (wasClose) {
            medianMeters <= exitMeters
        } else {
            medianMeters <= enterMeters
        }
        if (!isClose) return ProximityBucket.FAR
        return if (medianMeters <= immediateMeters) {
            ProximityBucket.IMMEDIATE
        } else {
            ProximityBucket.NEAR
        }
    }

    /**
     * บังคับ dwell (ADR-19 หัวข้อ 6(ค)) — candidate ที่ **ใกล้กว่า** ต้องผ่านเกณฑ์
     * ติดกัน ≥ [dwellSamples] ก่อนยืนยัน ส่วน candidate ที่ **ไกลกว่า** ยืนยันทันที
     * เพราะต้นทุนของการประกาศ "ใกล้" ผิดแพงกว่าอีกทางอย่างไม่สมมาตร
     *
     * **sample แรกของ key ใช้ baseline เท่ากับ [ProximityBucket.FAR]** (ไม่ใช่
     * "ต้อง dwell เสมอ") — candidate แรกที่เป็น far จึงยืนยันได้ทันที ส่วน
     * near/immediate ยังต้อง dwell ตรงกับฝั่ง Dart และ ADR-19 หัวข้อ 6(ช)
     *
     * ฟังก์ชันนี้เป็นคนเขียน state กลับลง map เสมอทุกสาขา (ผู้เรียกส่ง state ที่
     * อัปเดต window/lastSampleAt มาแล้วแต่ยังไม่ได้บันทึก)
     */
    private fun applyDwell(
        key: String,
        state: ProximityKeyState,
        candidate: ProximityBucket,
        medianMeters: Double?,
    ): ProximityTransition? {
        val current = state.confirmedBucket
        if (current == candidate) {
            states[key] = state.copy(pendingCloserBucket = null, pendingCloserCount = 0)
            return null
        }

        val baselineRank = if (current != null) {
            rankOfBucket(current)
        } else {
            rankOfBucket(ProximityBucket.FAR)
        }
        val becomingCloser = rankOfBucket(candidate) < baselineRank

        if (!becomingCloser) {
            states[key] = state.copy(
                pendingCloserBucket = null,
                pendingCloserCount = 0,
                confirmedBucket = candidate,
            )
            return ProximityTransition(
                key = key,
                from = current,
                to = candidate,
                reason = ProximityTransitionReason.FARTHER,
                medianMeters = medianMeters,
            )
        }

        val pendingCount = if (state.pendingCloserBucket == candidate) {
            state.pendingCloserCount + 1
        } else {
            1
        }

        if (pendingCount < dwellSamples) {
            states[key] = state.copy(
                pendingCloserBucket = candidate,
                pendingCloserCount = pendingCount,
            )
            return null
        }

        states[key] = state.copy(
            pendingCloserBucket = null,
            pendingCloserCount = 0,
            confirmedBucket = candidate,
        )
        return ProximityTransition(
            key = key,
            from = current,
            to = candidate,
            reason = ProximityTransitionReason.CLOSER,
            medianMeters = medianMeters,
        )
    }

    companion object {
        /**
         * median ของ [values] — copy ก่อน sort (ห้ามเรียงของเดิมในที่ ลำดับของ
         * หน้าต่างคือข้อมูล ไม่ใช่แค่ที่เก็บ) ขนาดคี่ = ตัวกลาง · ขนาดคู่ = ค่า
         * เฉลี่ยของสองตัวกลาง — ตรงกับ `_median` ฝั่ง Dart
         */
        internal fun medianOf(values: List<Double>): Double {
            val sorted = values.sorted()
            val mid = sorted.size / 2
            return if (sorted.size % 2 == 1) {
                sorted[mid]
            } else {
                (sorted[mid - 1] + sorted[mid]) / 2
            }
        }
    }
}
