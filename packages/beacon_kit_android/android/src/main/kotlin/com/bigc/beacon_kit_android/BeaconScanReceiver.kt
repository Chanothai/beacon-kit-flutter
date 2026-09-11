package com.bigc.beacon_kit_android

import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

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

        // ---- ชั้นที่ 2 ของ ADR-20: proximity ----
        //
        // **ต้องอยู่หลัง `onSighting` เสมอ ห้ามก่อน และห้ามขยับลำดับ
        // `reconcile()` → `onSighting()` ข้างบนแม้แต่บรรทัดเดียว** (ADR-17)
        //
        // ครอบทั้งก้อนด้วย try/catch แล้ว **กลืน** exception โดยตั้งใจ — ไม่ใช่
        // ความมักง่าย: ชั้น 1 (region enter/exit) มีหลักฐานจากอุปกรณ์จริงระดับ
        // `observed` แล้ว (ADR-14 — `reconcile()` ของ ADR-17 ยัง `code-complete,
        // unverified` ตาม `docs/test-checklists/android_background_scanning.md`)
        // และเป็นเหตุผลเดียวที่ process นี้ถูกปลุกขึ้นมา ส่วนชั้นนี้ยังไม่เคยรันบน
        // เครื่องจริงเลยแม้แต่ครั้งเดียว และเป็น POC ที่อ่าน
        // ค่าที่เก็บไว้บนดิสก์ (ถอด JSON ได้ไม่ครบ) และแตะ `ScanRecord` ดิบ ถ้า
        // ปล่อยให้ exception ลอยขึ้นไป `onReceive` จะตายทั้งเมธอด แต่งานของชั้น 1
        // ที่ทำไปแล้วข้างบนถูก commit ลงดิสก์เรียบร้อยแล้ว — ผลคือ crash ที่ผู้ใช้
        // เห็นโดยไม่ได้อะไรกลับมา และรอบถัดไปก็จะ crash ซ้ำแบบเดิม โยนต่อจึงแย่กว่า
        // กลืนในทุกทาง ตราบใดที่ยัง log ไว้ให้ตามได้ (ADR-20 หัวข้อ 1)
        try {
            processProximity(context, regionIdentifier, results)
        } catch (throwable: Throwable) {
            Log.w(TAG, "ชั้น proximity ล้มเหลว — enter/exit ของชั้น 1 ไม่ได้รับผลกระทบ", throwable)
        }
    }

    /**
     * เดิน `ProximityGate` ให้ครบหนึ่ง batch แล้วบันทึกสถานะลงดิสก์
     *
     * ลำดับสำคัญและห้ามสลับ:
     * 1. กู้สถานะจากดิสก์ — ถ้าข้ามขั้นนี้ dwell จะเริ่มนับหนึ่งใหม่ทุก sighting
     *    เพราะ process ถูกฆ่าคั่นกลาง แล้ว `dwellSamples` จะไม่มีวันครบ (ADR-20 §3)
     * 2. **อ่าน region spec เพื่อเอา uuid มาก่อนลูปเสมอ** — key ของ [ProximityGate]
     *    ต้องมี uuid ประกอบตั้งแต่ตอน [ProximityGate.push] ไม่ใช่แค่ตอนสร้าง event
     *    เท่านั้น (ต่างจากเดิมที่อ่านหลังลูปและเฉพาะตอนมี transition — ตอนนั้น
     *    key ยังไม่มี uuid เป็นส่วนหนึ่งจึงอ่านทีหลังได้ ADR-20 หัวข้อ 3 แก้ 11
     *    ก.ย. 2026)
     * 3. [ProximityGate.sweepStale] **ก่อน** ป้อน sample ใหม่ — ตรวจความเงียบที่
     *    ผ่านมาด้วยเวลาก่อนที่ sample ของรอบนี้จะไปต่ออายุ key ให้ (ADR-20 §4:
     *    ไม่มี timer ในเบื้องหลัง stale จึงถูกค้นพบตอน receiver ตื่นเท่านั้น)
     * 4. ป้อนทุก `ScanResult` ตามลำดับที่ระบบส่งมา — sample ที่ถอด identity
     *    (major/minor จากเฟรม + uuid จาก region spec) ไม่ได้ถูกทิ้งทั้งอัน **ไม่
     *    เรียก [ProximityGate.push] เลย** (ADR-20 หัวข้อ 3)
     * 5. **บันทึกลงดิสก์ก่อนแจ้ง observer** — หลักการเดียวกับที่ชั้น 1 เขียน
     *    หลักฐานก่อนยิง notification: ถ้าระบบฆ่า process ระหว่างนั้น อย่างน้อย
     *    สถานะที่นับมาได้ต้องไม่หาย
     */
    private fun processProximity(
        context: Context,
        regionIdentifier: String,
        results: List<ScanResult>,
    ) {
        val store = ProximityGateStore(context)
        val gate = ProximityGate(clock = System::currentTimeMillis)
        gate.restoreStates(store.load())

        // อ่าน region spec ครั้งเดียวต่อ batch ที่ต้นเมธอด **ก่อน** ลูปเสมอ (เป็น
        // การอ่านดิสก์) — ต้องอ่านก่อนเพราะ uuid ของ key ต้องมาจาก spec นี้ตั้งแต่
        // ตอนประกอบ key ให้ [ProximityGate.push] ไม่ใช่แค่ตอนประกอบ event ทีหลัง
        // เหมือนโค้ดเดิม (ADR-20 หัวข้อ 1(ก): `ScanFilter` ตั้ง mask เต็ม 16 ไบต์
        // ของ uuid เสมอ เฟรมที่หลุดผ่านมาถึงการันตี uuid แล้ว จึงไม่ต้องถอดจากเฟรม)
        val regionUuid = runCatching {
            BackgroundRegionMonitor.restoredRegions(context)
                .regions
                .firstOrNull { it.identifier == regionIdentifier }
                ?.uuid
                ?.toString()
        }.getOrNull()

        // เก็บ rssi/txPower/ที่อยู่วิทยุของ sample ที่จุดชนวน transition ไว้คู่กัน
        // เพื่อให้ไฟล์หลักฐานตอบได้ว่า median ที่ตัดสินใจมาจากสัญญาณแรงแค่ไหนและ
        // มาจากวิทยุตัวไหน — transition จาก sweepStale ไม่มี sample ประกอบ (ไม่มี
        // `ScanResult` คู่มาด้วยเพราะเป็นการตรวจความเงียบ ไม่ใช่ sample ใหม่) จึง
        // เป็น null ทั้งสามค่าตามจริง
        val pending = mutableListOf<PendingProximity>()

        for (transition in gate.sweepStale()) {
            pending.add(PendingProximity(transition, rssi = null, txPower = null, deviceAddress = null))
        }

        // ตัวนับระดับ batch — ไม่มี key ให้ผูกด้วยตั้งแต่แรกเพราะ parse ไม่สำเร็จ
        // แปลว่าไม่รู้ด้วยซ้ำว่าควรผูกกับ key ไหน (ต่างจาก droppedNoTxPowerCount
        // เดิมที่ผูกกับ key ที่รู้อยู่แล้วได้ — ADR-20 หัวข้อ 3)
        var droppedNoIdentityCount = 0

        for (result in results) {
            // อ่าน manufacturer data **ครั้งเดียวต่อ ScanResult** แล้วส่งต่อให้ทั้ง
            // txPower และ major/minor — ไม่ใช่เรียกซ้ำสองรอบ (ADR-20 หัวข้อ 1)
            val manufacturerData = result.scanRecord?.getManufacturerSpecificData(
                BeaconRegionSpec.APPLE_COMPANY_ID,
            )
            val txPower = ibeaconTxPowerFrom(manufacturerData)
            val identity = ibeaconIdentityFrom(manufacturerData)

            // ถอด major/minor จากเฟรมไม่ได้ หรือหา uuid ของ region ไม่เจอ =
            // ประกอบ key ไม่ได้เลยทั้งสองกรณี **ห้ามเรียก gate.push() และห้าม
            // fallback ไปใช้ major/minor จาก region spec เงียบ ๆ** — จะพากลับไป
            // สู่บั๊กเดิมเป๊ะที่บรรทัดหลักฐานอ่านไม่ออกว่าเป็นบีคอนตัวไหนโดยไม่มี
            // อะไรฟ้อง (ADR-20 หัวข้อ 3/8)
            if (identity == null || regionUuid == null) {
                droppedNoIdentityCount++
                continue
            }

            val transition = gate.push(
                key = proximityKeyFor(regionIdentifier, regionUuid, identity.major, identity.minor),
                rssi = result.rssi,
                txPower = txPower,
            )
            if (transition != null) {
                pending.add(
                    PendingProximity(
                        transition = transition,
                        rssi = result.rssi,
                        txPower = txPower,
                        deviceAddress = result.device?.address,
                    ),
                )
            }
        }

        store.save(gate.snapshotStates())
        // อ่านหลัง save เพื่อให้ครอบทั้งความล้มเหลวของ load และ save ในรอบเดียวกัน
        // — รวม migration ของรูปร่าง key (ถ้ามี) เข้าเป็นคอลัมน์เดียวกับ error จริง
        // แต่แยกด้วยเนื้อข้อความ (คนละ prefix) ไม่ให้ปนกันจนอ่านผิด (ADR-20 หัวข้อ 3)
        val storeError = buildString {
            store.lastError?.let { append(it) }
            store.lastMigrationDroppedCount?.let {
                if (isNotEmpty()) append(';')
                append("migrated dropped=$it")
            }
        }.ifEmpty { null }

        // ความล้มเหลวของดิสก์ต้องมีร่องรอย — ถ้า store อ่าน/เขียนไม่สำเร็จทุกครั้ง
        // dwell จะเริ่มนับหนึ่งใหม่ทุก sighting แล้ว gate จะเงียบตลอด ซึ่งอาการ
        // เหมือนกับ "ไม่มีบีคอนอยู่ใกล้" เป๊ะ (ดู kdoc ของ `ProximityGateStore`)
        store.lastError?.let { Log.w(TAG, "ProximityGateStore ล้มเหลว: $it") }

        // ถอด identity ไม่ได้ต้องมีร่องรอยเสมอ ไม่ใช่แค่ log ไว้ในนี้ (ดูต่อว่ายัง
        // ต้องโผล่ในบรรทัดหลักฐานผ่าน [ProximityChangedEvent.droppedNoIdentityCount]
        // ด้วยเมื่อ batch นี้มี event ให้แนบ — ADR-20 หัวข้อ 3)
        if (droppedNoIdentityCount > 0) {
            Log.w(
                TAG,
                "ถอด major/minor จากเฟรมไม่ได้ $droppedNoIdentityCount sample ในรอบนี้ — ทิ้งทั้งหมด ไม่ fallback",
            )
        }

        if (pending.isEmpty()) return

        for (item in pending) {
            // uuid/major/minor ของ event นี้ต้องมาจาก**คีย์เดียวกับที่ gate ใช้จริง**
            // ไม่ใช่จาก regionUuid/identity ของลูปข้างบนตรง ๆ เพราะ transition ที่
            // มาจาก sweepStale() ไม่มี sample สดคู่มาด้วยเลย — คีย์ที่ผูกกับ
            // transition เป็นแหล่งเดียวที่ถูกต้องสำหรับทั้งสองเส้นทาง (ADR-20 หัวข้อ 3)
            val keyParts = proximityKeyPartsOrNull(item.transition.key)
            BackgroundProximityMonitor.emit(
                ProximityChangedEvent(
                    regionIdentifier = regionIdentifier,
                    uuid = keyParts?.uuid,
                    major = keyParts?.major,
                    minor = keyParts?.minor,
                    from = item.transition.from,
                    to = item.transition.to,
                    reason = item.transition.reason,
                    medianMeters = item.transition.medianMeters,
                    timestampMillis = System.currentTimeMillis(),
                    rssi = item.rssi,
                    txPower = item.txPower,
                    beaconTag = beaconTagOf(item.deviceAddress),
                    storeError = storeError,
                    droppedNoIdentityCount = droppedNoIdentityCount,
                ),
            )
        }
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

/** tag ของ logcat สำหรับเส้นทางเบื้องหลัง — สั้นกว่า 23 ตัวอักษรตามข้อจำกัดของ `Log` */
private const val TAG = "BeaconScanReceiver"

/**
 * sample หนึ่งตัวที่รอส่งเป็น [ProximityChangedEvent] — จับคู่ [ProximityTransition]
 * ของ `ProximityGate` เข้ากับสัญญาณดิบของ `ScanResult` ที่จุดชนวน transition นั้น
 *
 * ทั้งสามฟิลด์สัญญาณดิบเป็น `null` พร้อมกันเสมอเมื่อ transition มาจาก
 * [ProximityGate.sweepStale] เพราะเส้นทางนั้นไม่มี `ScanResult` คู่มาด้วย (เป็นการ
 * ตรวจความเงียบ ไม่ใช่ sample ใหม่)
 */
private data class PendingProximity(
    val transition: ProximityTransition,
    val rssi: Int?,
    val txPower: Int?,
    /** ที่อยู่ดิบของวิทยุ — ยังไม่ตัดเหลือสองไบต์ท้าย ดู [beaconTagOf] เป็นคนตัด */
    val deviceAddress: String?,
)

/**
 * key ของ `ProximityGate` สำหรับหนึ่งบีคอนที่เห็นใน region หนึ่ง
 *
 * **รูปแบบและลำดับตรงกับ `ProximityKeyCodec.key()` ฝั่ง iOS เป๊ะ**
 * (`packages/beacon_kit_ios/.../ProximityGate.swift:212-219`) — ทั้งสองแพลตฟอร์ม
 * ต้องตอบคำถาม "นี่บีคอนตัวไหน" ด้วยวิธีเดียวกัน (ADR-20 หัวข้อ 3 แก้ 11 ก.ย. 2026)
 *
 * ## ทำไมไม่มี MAC อยู่ในนี้อีกต่อไป (ต่างจากฉบับ 9 ก.ย. 2026)
 *
 * ฉบับแรกใช้ `"<regionIdentifier>|<MAC>"` เพราะตอนนั้นฝั่ง Kotlin ยังไม่มี parser
 * ถอด major/minor จากเฟรม (ADR-14 หัวข้อ 4.1) — ตอนนี้ถอดได้แล้ว
 * ([ibeaconIdentityFrom]) จึงกลับไปใช้ (uuid, major, minor) ตามที่ตั้งใจไว้แต่แรก
 * และตรงกับ iOS ⚠️ **MAC ไม่ใช่ identity ที่ยั่งยืน** (หมุนแบบสุ่มได้ตาม privacy
 * feature ของ BLE) จึงไม่ควรอยู่ใน key แต่ยังมีประโยชน์สำหรับดีบั๊กฮาร์ดแวร์ — ดู
 * [beaconTagOf] และ [ProximityChangedEvent.beaconTag]
 *
 * [uuid] มาจาก **region spec ที่ลงทะเบียนไว้** ไม่ใช่จากเฟรม (`ScanFilter` ตั้ง
 * mask `0xFF` เต็ม 16 ไบต์ของ uuid เสมอ — เฟรมที่หลุดผ่านมาถึงการันตี uuid แล้ว,
 * ADR-20 หัวข้อ 1(ก)) ส่วน [major]/[minor] มาจาก [ibeaconIdentityFrom] เพราะ region
 * แบบกว้าง (ADR-8 wildcard) ไม่การันตีสองค่านี้เลย
 *
 * แปลง [uuid] เป็นตัวพิมพ์เล็กเสมอ (`lowercase()`) แม้ `UUID.toString()` ของ Java
 * จะคืนตัวพิมพ์เล็กอยู่แล้วตามสเปก — เขียนไว้ตรง ๆ ไม่พึ่งพฤติกรรม implicit ของ
 * เมธอดต้นทาง เพื่อให้ตรงกับ `uuid.lowercased()` ฝั่ง Swift เป๊ะโดยไม่ต้องสมมติ
 */
internal fun proximityKeyFor(regionIdentifier: String, uuid: String, major: Int, minor: Int): String =
    "$regionIdentifier|${uuid.lowercase()}|$major|$minor"

/** ผลของการถอด [proximityKeyFor] กลับ — ดู [proximityKeyPartsOrNull] */
internal data class ProximityKeyParts(
    val regionIdentifier: String,
    val uuid: String,
    val major: Int,
    val minor: Int,
)

/**
 * ถอด key ของ `ProximityGate` กลับเป็นส่วนประกอบ — **`null` ทั้งก้อนเมื่อรูปแบบ
 * ไม่ตรง ห้ามเดาค่าแทน** (แนวเดียวกับ `ProximityKeyCodec.Parsed` ฝั่ง iOS)
 *
 * จำเป็นเพราะ transition ที่มาจาก [ProximityGate.sweepStale] ไม่มี `ScanResult`
 * สดคู่มาด้วยเลย (เป็นการตรวจความเงียบ ไม่ใช่ sample ใหม่) — **key ที่ผูกอยู่กับ
 * transition นั้นเองจึงเป็นแหล่งเดียวที่ยังตอบได้ว่า uuid/major/minor ของบีคอนตัวนี้
 * คืออะไร** ตอนสร้าง [ProximityChangedEvent] (ทั้งเส้นทางที่มี sample สดและเส้นทาง
 * stale ใช้ฟังก์ชันนี้ร่วมกัน ไม่ใช่คนละที่มา — กัน drift)
 *
 * key ที่ถูกกู้จากดิสก์ผ่าน `ProximityGateStore.load()` การันตีรูปร่าง 4 ส่วนอยู่
 * แล้ว (ADR-20 หัวข้อ 3 "Migration ของ state บนดิสก์") จึง**ไม่ควร**เจอ `null` จาก
 * ฟังก์ชันนี้ในทางปฏิบัติ แต่เขียนให้ทนทานไว้เผื่อ state เพี้ยนแบบที่ยังคิดไม่ถึง
 */
internal fun proximityKeyPartsOrNull(key: String): ProximityKeyParts? {
    val parts = key.split('|')
    if (parts.size != 4) return null
    val major = parts[2].toIntOrNull() ?: return null
    val minor = parts[3].toIntOrNull() ?: return null
    return ProximityKeyParts(regionIdentifier = parts[0], uuid = parts[1], major = major, minor = minor)
}

/**
 * ตัวแยกบีคอนสำหรับไฟล์หลักฐาน — **สองไบต์ท้ายของ MAC เท่านั้น**
 *
 * ก่อน ADR-20 หัวข้อ 3 (แก้ 11 ก.ย. 2026) ฟังก์ชันนี้ถอด MAC ออกจาก gate key ได้
 * เพราะ MAC เคยเป็นส่วนหนึ่งของ key — พอ key เปลี่ยนเป็น (region, uuid, major,
 * minor) MAC ไม่อยู่ในนั้นแล้ว **[deviceAddress] จึงต้องมาจาก
 * `ScanResult.device?.address` ตรง ๆ ต่อ sample ที่มี `ScanResult` จริงแทน** ดู
 * เหตุผลเต็มที่ [ProximityChangedEvent.beaconTag]
 *
 * คืน `null` เมื่อ [deviceAddress] เป็น `null` (เกิดจริงทุกครั้งกับ transition จาก
 * `sweepStale` ที่ไม่มี `ScanResult` คู่มาด้วย — ไม่ใช่ error ห้ามเดาค่าแทน) และคืน
 * ค่าดิบทั้งก้อนเมื่อไม่มี `:` ปนอยู่เลย (รูปแบบที่ไม่คาดคิดจากระบบ — ตัดสองไบต์
 * ท้ายไม่ได้ก็ยังดีกว่าไม่มีอะไรให้ดูเลย)
 */
internal fun beaconTagOf(deviceAddress: String?): String? {
    val address = deviceAddress ?: return null
    if (!address.contains(':')) return address
    return address.split(':').takeLast(2).joinToString(":")
}

/**
 * ผลของการถอด major/minor จากเฟรม iBeacon — ดู [ibeaconIdentityFrom]
 *
 * **ไม่ใช่ entity ซ้ำกับ `BeaconAdvertisement`** (ADR-14 หัวข้อ 4.1 · ADR-20 หัวข้อ
 * 1(ข)) — เป็นแค่ค่าดิบสองตัวที่ถอดมาได้ ไม่มี field อื่นใดของเฟรม ไม่มีพฤติกรรม
 * ใด ๆ นอกจากถือค่า
 */
internal data class IBeaconIdentity(val major: Int, val minor: Int)

/**
 * อ่าน `txPower` จาก manufacturer-specific data ของ iBeacon — **pure function**
 *
 * แยกออกมาเป็นฟังก์ชันระดับไฟล์ที่รับ `ByteArray?` (ไม่ใช่ `ScanResult`) ด้วยเหตุผล
 * เดียวกับที่ `BeaconRegionSpec.scanFilterDataAndMask()` ถูกแยกออกจาก `toScanFilter()`:
 * `ScanResult`/`ScanRecord` เป็นคลาสของ framework ที่สร้างใน JVM unit test ไม่ได้เลย
 * ถ้าปล่อยตรรกะการอ่านไบต์ไว้ข้างในเมธอดที่รับ `ScanResult` มันจะกลายเป็นตรรกะที่
 * เสี่ยงที่สุดในไฟล์นี้และทดสอบไม่ได้เลย — และอาการเวลาผิดคือ "ระยะเพี้ยนเป็นเท่าตัว"
 * ซึ่งดูเหมือนสัญญาณอ่อนธรรมดา ไม่มีอะไรฟ้องว่าเป็นบั๊ก
 *
 * layout (หลัง company id ถูกตัดออกโดย `getManufacturerSpecificData` แล้ว —
 * `ScanFilter.java:618-638` และหัวข้อ "รูปแบบของ byte ที่กรอง" ใน `BeaconRegionSpec`):
 * ```
 * 02 15 | uuid (16) | major (2) | minor (2) | txPower (1)
 * ```
 *
 * **ทั้ง prefix และ offset อ้างของเดิมตัวเดียว ไม่เขียนเลขซ้ำ** (ADR-20 หัวข้อ 1):
 * prefix มาจาก [BeaconRegionSpec.IBEACON_PREFIX] และ offset คำนวณจากความยาวของ
 * prefix นั้นบวกความยาวของฟิลด์ที่คั่นอยู่ ไม่ใช่ค่าคงที่ `22` ที่เขียนทิ้งไว้
 *
 * คืน `null` (ไม่ใช่ค่า default เงียบ ๆ) เมื่อ array เป็น `null` / สั้นเกินไป /
 * prefix ไม่ใช่ `02 15` — `ProximityGate` จะทิ้ง sample นั้นและนับ
 * `droppedNoTxPowerCount` ให้เอง ตาม ADR-19 หัวข้อ 6(จ) ที่ห้าม default ค่า txPower
 *
 * ค่าที่คืนเป็น **signed** (`Byte.toInt()`) เพราะ txPower ของ iBeacon คือ RSSI ที่วัด
 * ได้ที่ระยะ 1 เมตร ซึ่งเป็นค่าติดลบเสมอในทางปฏิบัติ — อ่านเป็น unsigned จะได้ ~200
 * แล้วสูตรระยะจะพุ่งเป็นหลักพันเมตรโดยไม่มีอะไรฟ้อง
 */
internal fun ibeaconTxPowerFrom(manufacturerData: ByteArray?): Int? {
    val data = manufacturerData ?: return null
    val prefix = BeaconRegionSpec.IBEACON_PREFIX

    // uuid 16 + major 2 + minor 2 ไบต์ คั่นระหว่าง prefix กับ txPower
    val txPowerIndex = prefix.size + 16 + 2 + 2
    if (data.size < txPowerIndex + 1) return null

    for (index in prefix.indices) {
        if (data[index] != prefix[index]) return null
    }

    return data[txPowerIndex].toInt()
}

/**
 * อ่าน major/minor จาก manufacturer-specific data ของ iBeacon — **pure function**
 * แพทเทิร์นเดียวกับ [ibeaconTxPowerFrom] เป๊ะและด้วยเหตุผลเดียวกัน: รับ `ByteArray?`
 * ไม่ใช่ `ScanResult`/`ScanRecord` เพราะสองคลาสนั้นสร้างใน JVM unit test ไม่ได้เลย
 * (ADR-20 หัวข้อ 1 ขยายจากถอด 1 ไบต์ (txPower) เป็น 5 ไบต์ (txPower + major +
 * minor) เมื่อ 11 ก.ย. 2026)
 *
 * ⚠️ **นี่คือ parser ตัวที่สองของฟิลด์เดียวกันกับที่ `IBeaconParser` (Dart) ทำอยู่
 * แล้ว** (`packages/beacon_kit_platform_interface/lib/src/parsers/ibeacon_parser.dart`)
 * — เบี่ยงจาก ADR-14 หัวข้อ 4.1 จริง ยอมรับได้เฉพาะเพราะ major/minor เป็นฟิลด์
 * identity ที่ region แบบกว้าง (ADR-8 wildcard) ไม่การันตีมาให้จาก `ScanFilter` เลย
 * ต่างจาก uuid (ADR-20 หัวข้อ 1(ก)) — **เทสของฟังก์ชันนี้ต้องใช้ byte fixture ชุด
 * เดียวกับ `ibeacon_parser_test.dart`** ไม่ใช่แค่ค่าที่แต่งขึ้นเอง ไม่งั้นสองภาษาจะ
 * drift กันได้โดยไม่มีเทสจับเลย (ADR-20 หัวข้อ 1(ข)) — เป็นเงื่อนไขบังคับของขั้น
 * beacon-qa ไม่ใช่ทางเลือก
 *
 * layout เดียวกับ [ibeaconTxPowerFrom]:
 * ```
 * 02 15 | uuid (16) | major (2) | minor (2) | txPower (1)
 * ```
 *
 * **offset อ้าง [BeaconRegionSpec.IBEACON_PREFIX] ตัวเดียวกับ [ibeaconTxPowerFrom]
 * ห้ามเขียนเลขซ้ำเป็นตัวที่สอง** (ADR-20 หัวข้อ 1(ค)): major เริ่มที่
 * `prefix.size + 16`, minor เริ่มที่ `prefix.size + 18`
 *
 * อ่านเป็น **unsigned big-endian uint16** (`0..65535`) ต่างจาก [ibeaconTxPowerFrom]
 * ที่เป็น signed — major/minor ของ iBeacon เป็นเลขไม่ติดลบตามสเปก Apple และตรงกับ
 * `(manufacturerData[20] << 8) | manufacturerData[21]` (ไม่มีการ mask ลบ sign) ที่
 * `IBeaconParser.parse()` ฝั่ง Dart ทำอยู่แล้ว
 *
 * คืน `null` **ทั้งก้อน** (ไม่ใช่ค่าบางส่วน ห้ามเดา) เมื่อ array เป็น `null` / สั้น
 * เกินไป / prefix ไม่ใช่ `02 15` — ผู้เรียกต้องทิ้ง sample นั้นทั้งอันและห้าม
 * fallback ไปใช้ major/minor จาก region spec เงียบ ๆ (ADR-20 หัวข้อ 3)
 */
internal fun ibeaconIdentityFrom(manufacturerData: ByteArray?): IBeaconIdentity? {
    val data = manufacturerData ?: return null
    val prefix = BeaconRegionSpec.IBEACON_PREFIX

    val majorIndex = prefix.size + 16
    val minorIndex = majorIndex + 2
    if (data.size < minorIndex + 2) return null

    for (index in prefix.indices) {
        if (data[index] != prefix[index]) return null
    }

    val major = ((data[majorIndex].toInt() and 0xFF) shl 8) or (data[majorIndex + 1].toInt() and 0xFF)
    val minor = ((data[minorIndex].toInt() and 0xFF) shl 8) or (data[minorIndex + 1].toInt() and 0xFF)
    return IBeaconIdentity(major = major, minor = minor)
}
