package com.bigc.beacon_kit_android

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.bluetooth.le.ScanSettings
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import androidx.core.content.ContextCompat

/**
 * เฝ้า region เบื้องหลังด้วย `BluetoothLeScanner.startScan(..., PendingIntent)`
 *
 * **อ่าน ADR-14 ก่อนแก้ไฟล์นี้** — โดยเฉพาะหัวข้อที่บอกว่ากลไกนี้ **ไม่เท่ากับ**
 * region monitoring ของ iOS
 *
 * ## กลไกโดยย่อ
 *
 * ```
 *   startScan(filter ของ region A, settings, PendingIntent A)   <- ลงทะเบียนกับระบบ
 *          |
 *          v  (ระบบส่ง broadcast เมื่อเจอ แม้ process ตายไปแล้ว)
 *   BeaconScanReceiver  --> onSighting("A")
 *          |                     |
 *          |                     +-- ยังไม่เคยเห็น -> ยิง enter
 *          |                     +-- ตั้ง/เลื่อนนาฬิกาปลุก exit ไปอีก N วินาที
 *          v
 *   RegionExitAlarmReceiver --> ถ้าครบ N วินาทีแล้วยังไม่เห็นอีก -> ยิง exit
 * ```
 *
 * ## สามข้อที่ต้องรู้ก่อนใช้ (และห้ามอธิบายให้ฟังดูเทียบเท่า iOS)
 *
 * 1. **ไม่มี enter/exit จากระบบ** ฝั่ง iOS `CLLocationManager` ยิง
 *    `didEnterRegion`/`didExitRegion` ให้เอง ฝั่งนี้ระบบให้แค่ "เจอ advertisement"
 *    เท่านั้น — "ออกจากโซน" คือ **ข้อสรุปของเราเอง** จากการไม่เห็นครบ N วินาที
 * 2. **ไม่รอดข้าม force-stop และไม่รอดข้ามรีบูต** (ดูผลทดสอบใน ADR-14) ต่างจาก
 *    `monitoredRegions` ของ iOS ที่ระบบเก็บให้ข้าม launch — จึงต้องมี
 *    [BootCompletedReceiver] มาลงทะเบียนใหม่ และ force-stop ไม่มีทางแก้ด้วยโค้ด
 * 3. **ความเร็วของ exit ถูกจำกัดด้วยนาฬิกาปลุกของระบบ** ไม่ใช่ด้วยค่า N ที่ตั้ง
 *    `setAndAllowWhileIdle` ระบุไว้เองว่า "it will not dispatch these alarms more
 *    than about every minute... when in low-power idle modes this duration may be
 *    significantly longer, such as 15 minutes"
 *    (`AlarmManager.java:1286-1289`) — ตั้ง N = 30 วินาทีไม่ได้แปลว่าจะได้ exit
 *    ภายใน 30 วินาที
 */
object BackgroundRegionMonitor {

    /** action ของ broadcast ผลสแกน — ภายในแอปเท่านั้น (receiver ไม่ exported) */
    const val ACTION_SCAN_RESULT = "com.bigc.beacon_kit_android.SCAN_RESULT"

    /** action ของนาฬิกาปลุกที่ใช้ประกาศ exit */
    const val ACTION_REGION_EXIT = "com.bigc.beacon_kit_android.REGION_EXIT"

    const val EXTRA_REGION_IDENTIFIER = "regionIdentifier"

    /**
     * ผู้สังเกตการณ์ฝั่ง host app ที่ทำงานได้ **โดยไม่ต้องมี Flutter engine**
     *
     * คู่ขนานกับ `BeaconKitIosPlugin.startBackgroundRegionMonitoring` ฝั่ง iOS ที่
     * ADR-10 เพิ่มเข้ามาด้วยเหตุผลเดียวกันเป๊ะ: เครื่องมือวัดต้องไม่ตายพร้อมกับสิ่ง
     * ที่มันควรวัด host app ตั้งค่านี้ใน `Application.onCreate()` ซึ่งเป็นจุดที่
     * **ทำงานเสมอ** ไม่ว่า process จะถูกสร้างขึ้นมาด้วยเหตุใด
     *
     * **SDK ไม่ทำให้เองอัตโนมัติ** ด้วยเหตุผลเดียวกับ ADR-10: plugin ไม่มีทางแทรก
     * ตัวเข้าไปในวงจรชีวิตของ `Application` ของแอปที่ใช้มันได้ และไม่ควรบังคับรูปแบบ
     * การเก็บ log แบบใดแบบหนึ่งให้ผู้ใช้ SDK
     */
    fun interface RegionStateObserver {
        fun onRegionStateEvent(event: BackgroundRegionStateEvent)
    }

    @Volatile
    private var observer: RegionStateObserver? = null

    fun setRegionStateObserver(newObserver: RegionStateObserver?) {
        observer = newObserver
    }

    /**
     * ผู้ส่งต่อไปยัง Flutter — ตั้งโดย plugin ตอน engine มีชีวิต และล้างเมื่อ detach
     *
     * แยกจาก [observer] เพราะอายุต่างกันคนละระดับ: ตัวนี้มีอยู่เฉพาะช่วงที่ engine
     * ทำงาน ส่วน [observer] อยู่ตลอดอายุ process ถ้ารวมเป็นตัวเดียวกัน การ detach
     * engine จะเผลอถอดเครื่องมือวัดออกไปด้วย
     */
    @Volatile
    private var flutterSink: RegionStateObserver? = null

    fun setFlutterSink(sink: RegionStateObserver?) {
        flutterSink = sink
    }

    // ---- เริ่ม / หยุด ----

    /**
     * ผลของการพยายามลงทะเบียน — คืนกลับไปให้ Dart เพื่อ**ไม่ให้ล้มเหลวเงียบ**
     *
     * `startScan(..., PendingIntent)` คืน `int` (0 = สำเร็จ) แทนการ throw ซึ่งเป็น
     * รูปแบบที่ล้มเหลวเงียบได้ง่ายมากถ้าไม่ตรวจค่าที่คืนมา
     */
    data class StartResult(
        val registered: List<String>,
        val failed: Map<String, String>,
    )

    fun start(
        context: Context,
        regions: List<BeaconRegionSpec>,
        exitTimeoutSeconds: Int,
    ): StartResult {
        val appContext = context.applicationContext
        val store = BackgroundRegionStore(appContext)

        // หยุดของเดิมก่อนเสมอ ไม่งั้นการลงทะเบียนซ้ำจะทิ้ง PendingIntent เก่าค้างไว้
        // โดยไม่มีใครถอนได้อีกเลย (เราจำ region เก่าไม่ได้แล้วหลังเขียนทับรายการ)
        stopScansOnly(appContext, store.regions)

        store.regions = regions
        store.exitTimeoutSeconds = exitTimeoutSeconds
        store.isActive = true
        store.clearRegionStates()
        store.stampBootToken()

        return registerScans(appContext, regions)
    }

    fun stop(context: Context) {
        val appContext = context.applicationContext
        val store = BackgroundRegionStore(appContext)
        stopScansOnly(appContext, store.regions)
        for (region in store.regions) {
            cancelExitAlarm(appContext, region.identifier)
        }
        // ล้างทั้งหมดรวมคิว event — ผู้เรียกสั่งหยุดแล้ว การส่ง event เก่าให้ทีหลัง
        // จะทำให้แอปเข้าใจผิดว่ายังเฝ้าอยู่
        store.clearAll()
    }

    /**
     * ลงทะเบียนใหม่หลังรีบูต — เรียกจาก [BootCompletedReceiver] เท่านั้น
     *
     * ล้างสถานะเข้า/ออกทิ้งก่อนเสมอ เพราะเวลาแบบ elapsed ที่เก็บไว้มาจากรอบบูตก่อน
     * และ "อยู่ในโซน" ที่ค้างจากก่อนรีบูตเชื่อไม่ได้แล้ว (เครื่องอาจถูกยกไปที่อื่น
     * ระหว่างปิด) — ถ้าไม่ล้าง แอปจะคิดว่ายังอยู่ในโซนตลอดไปและไม่รายงาน enter อีกเลย
     */
    fun restoreAfterBoot(context: Context): StartResult {
        val appContext = context.applicationContext
        val store = BackgroundRegionStore(appContext)
        if (!store.isActive) {
            return StartResult(emptyList(), emptyMap())
        }
        store.clearRegionStates()
        store.stampBootToken()
        return registerScans(appContext, store.regions)
    }

    /**
     * identifier ของ region ที่ **เราเอง** เก็บไว้ว่ากำลังเฝ้าอยู่
     *
     * ⚠️ **ห้ามใช้ตัวนี้เขียนไฟล์หลักฐาน** — list ว่างที่คืนมาไม่ได้บอกว่า "ไม่มี
     * region" หรือ "อ่านค่าที่เก็บไว้ไม่ได้" ใช้ [restoredRegions] แทน
     */
    fun restoredRegionIdentifiers(context: Context): List<String> =
        BackgroundRegionStore(context.applicationContext).regions.map { it.identifier }

    /**
     * region ที่เราจำไว้ **พร้อมเหตุผลถ้าอ่านไม่สำเร็จ** — สำหรับเส้นทางที่เขียน
     * หลักฐาน ซึ่งต้องรายงาน "ว่าง" กับ "อ่านไม่ออก" ด้วยข้อความคนละแบบ
     */
    fun restoredRegions(context: Context): ParsedRegionList =
        BackgroundRegionStore(context.applicationContext).readRegions()

    fun isActive(context: Context): Boolean =
        BackgroundRegionStore(context.applicationContext).isActive

    // ---- การลงทะเบียนกับ BluetoothLeScanner ----

    private fun registerScans(
        context: Context,
        regions: List<BeaconRegionSpec>,
    ): StartResult {
        val registered = mutableListOf<String>()
        val failed = mutableMapOf<String, String>()

        if (!hasScanPermission(context)) {
            for (region in regions) {
                failed[region.identifier] = "BLUETOOTH_PERMISSION_DENIED"
            }
            return StartResult(registered, failed)
        }

        val scanner = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)
            ?.adapter
            ?.takeIf { it.isEnabled }
            ?.bluetoothLeScanner
        if (scanner == null) {
            for (region in regions) {
                failed[region.identifier] = "BLUETOOTH_UNAVAILABLE"
            }
            return StartResult(registered, failed)
        }

        // SCAN_MODE_LOW_POWER ตรงกับความจริง ไม่ใช่การยอมแพ้: ScanSettings.java:48-52
        // ระบุว่าโหมดนี้ "is enforced if the scanning application is not in
        // foreground" — การขอ LOW_LATENCY ในเส้นทางเบื้องหลังจึงเป็นการขอสิ่งที่
        // ระบบจะลดให้เองอยู่ดี และทำให้คนอ่านโค้ดเข้าใจผิดว่าได้ความถี่สูง
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()

        for (region in regions) {
            val pendingIntent = scanPendingIntent(context, region.identifier, create = true)
            if (pendingIntent == null) {
                failed[region.identifier] = "PENDING_INTENT_FAILED"
                continue
            }
            val code = try {
                scanner.startScan(listOf(region.toScanFilter()), settings, pendingIntent)
            } catch (error: SecurityException) {
                failed[region.identifier] = "BLUETOOTH_PERMISSION_DENIED"
                continue
            }
            if (code == 0) {
                registered.add(region.identifier)
            } else {
                failed[region.identifier] = scanErrorName(code)
            }
        }

        return StartResult(registered, failed)
    }

    private fun stopScansOnly(context: Context, regions: List<BeaconRegionSpec>) {
        val scanner = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)
            ?.adapter
            ?.bluetoothLeScanner
            ?: return
        for (region in regions) {
            // ต้องเป็น PendingIntent "ตัวเดียวกัน" กับตอนลงทะเบียน — สร้างด้วย
            // พารามิเตอร์ชุดเดิมจะได้ตัวเดิมกลับมาเสมอ (ระบบเทียบด้วย
            // Intent.filterEquals + requestCode) และ **ห้ามใช้ FLAG_CANCEL_CURRENT**
            // ตามที่ BluetoothLeScanner.java:384-387 เตือนไว้ว่าจะทำให้ stop ไม่มีผล
            val pendingIntent = scanPendingIntent(context, region.identifier, create = true)
                ?: continue
            runCatching { scanner.stopScan(pendingIntent) }
        }
    }

    /**
     * `PendingIntent` ของผลสแกนสำหรับ region หนึ่งอัน
     *
     * ## ทำไมต้อง `FLAG_MUTABLE`
     *
     * ระบบส่งผลสแกนกลับมาโดย **เติม extras** (`EXTRA_LIST_SCAN_RESULT`,
     * `EXTRA_CALLBACK_TYPE`, `EXTRA_ERROR_CODE` — `BluetoothLeScanner.java:184-186`)
     * เข้าไปใน Intent ที่ส่งออก ซึ่งทำผ่านพารามิเตอร์ `intent` ของ
     * `PendingIntent.send()` และเอกสารของเมธอดนั้นระบุตรง ๆ ว่า
     *
     * > "Additional Intent data. See Intent.fillIn() for information on how this is
     * > applied to the original Intent. **If flag FLAG_IMMUTABLE was set when this
     * > pending intent was created, this argument will be ignored.**"
     * > — `PendingIntent.java:917-919`
     *
     * `FLAG_IMMUTABLE` จึงหมายถึง "ได้ broadcast แต่ไม่มีผลสแกนติดมาด้วย" ซึ่งเป็น
     * ความล้มเหลวแบบเงียบชนิดที่แย่ที่สุด — **ยืนยันบนเครื่องจริงแล้ว** ดู ADR-14
     *
     * ## ทำไมต้องมี data URI ต่างกันต่อ region
     *
     * ระบบเทียบว่า `PendingIntent` สองตัวเป็นตัวเดียวกันหรือไม่ด้วย
     * `Intent.filterEquals` (action / data / type / component / categories) +
     * requestCode — **extras ไม่ถูกนับ** ถ้าต่างกันแค่ extras จะได้ตัวเดิมกลับมา
     * แปลว่าทุก region จะใช้ `PendingIntent` ตัวเดียวกันและ `identifier` ที่พกไป
     * จะเป็นของ region สุดท้ายที่ลงทะเบียนเสมอ — บั๊กที่หาสาเหตุยากมาก
     * จึงใส่ทั้ง data URI ที่ไม่ซ้ำ **และ** requestCode ที่ไม่ซ้ำ
     *
     * Intent เป็นแบบระบุ component ชัดเจน (`setClass`) จึงไม่ชนกับข้อห้าม
     * "mutable implicit PendingIntent" ที่ Android 14 บล็อก
     * (`PendingIntent.isNewMutableDisallowedImplicitPendingIntent`)
     */
    fun scanPendingIntent(
        context: Context,
        regionIdentifier: String,
        create: Boolean,
    ): PendingIntent? {
        val intent = Intent(ACTION_SCAN_RESULT)
            .setClass(context, BeaconScanReceiver::class.java)
            .setData(Uri.parse("beaconkit://scan/$regionIdentifier"))
            .putExtra(EXTRA_REGION_IDENTIFIER, regionIdentifier)

        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (!create) flags = flags or PendingIntent.FLAG_NO_CREATE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }

        return PendingIntent.getBroadcast(
            context,
            requestCodeFor("scan", regionIdentifier),
            intent,
            flags,
        )
    }

    // ---- นาฬิกาปลุกสำหรับประกาศ exit ----

    private fun exitAlarmPendingIntent(
        context: Context,
        regionIdentifier: String,
    ): PendingIntent {
        val intent = Intent(ACTION_REGION_EXIT)
            .setClass(context, RegionExitAlarmReceiver::class.java)
            .setData(Uri.parse("beaconkit://exit/$regionIdentifier"))
            .putExtra(EXTRA_REGION_IDENTIFIER, regionIdentifier)

        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        // นาฬิกาปลุกไม่ต้องให้ใครเติมข้อมูล — ใช้ IMMUTABLE ตามคำแนะนำของเอกสาร
        // ("It is strongly recommended to use FLAG_IMMUTABLE" — PendingIntent.java:278)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }

        return PendingIntent.getBroadcast(
            context,
            requestCodeFor("exit", regionIdentifier),
            intent,
            flags,
        )
    }

    /**
     * ตั้งนาฬิกาปลุกให้ยิง exit เมื่อครบเวลา
     *
     * ## ทำไม `setAndAllowWhileIdle` ไม่ใช่ `setExactAndAllowWhileIdle`
     *
     * ตัวหลังต้องขอสิทธิ์พิเศษบน Android 12 ขึ้นไป: "apps targeting SDK level 31 or
     * higher need to request the SCHEDULE_EXACT_ALARM permission to use this API,
     * unless the app is exempt from battery restrictions"
     * (`AlarmManager.java:1352-1356`) และเอกสารเดียวกันระบุว่า "Exact alarms should
     * only be used for user-facing features" — การตรวจว่าออกจากโซนแล้วหรือยัง
     * **ไม่ใช่ฟีเจอร์ที่ผู้ใช้กดเรียก** การขอสิทธิ์นั้นจึงเกินความจำเป็นและเป็น
     * สิทธิ์ที่ผู้ใช้/ระบบถอนได้ตลอดเวลา ซึ่งจะทำให้ exit หยุดทำงานเงียบ ๆ
     *
     * **ราคาที่จ่ายและต้องรายงานตรง ๆ:** `setAndAllowWhileIdle` ระบุเองว่า "it will
     * not dispatch these alarms more than about every minute... when in low-power
     * idle modes this duration may be significantly longer, such as 15 minutes"
     * (`AlarmManager.java:1286-1289`) — ค่า N ที่แอปตั้งจึงเป็น **ขั้นต่ำ** ไม่ใช่
     * เวลาที่จะได้จริง
     *
     * ใช้ `ELAPSED_REALTIME_WAKEUP` ไม่ใช่ `RTC_WAKEUP` เพราะการนับ "ไม่เห็นมากี่
     * วินาที" ต้องใช้นาฬิกาที่ไม่กระโดดตามการ sync เวลาของเครือข่าย
     */
    private fun scheduleExitAlarm(
        context: Context,
        regionIdentifier: String,
        atElapsedMillis: Long,
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            atElapsedMillis,
            exitAlarmPendingIntent(context, regionIdentifier),
        )
    }

    private fun cancelExitAlarm(context: Context, regionIdentifier: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return
        alarmManager.cancel(exitAlarmPendingIntent(context, regionIdentifier))
    }

    // ---- เครื่องสถานะ enter/exit ----

    /**
     * มีผลสแกนของ region นี้เข้ามา
     *
     * เรียกจาก [BeaconScanReceiver] ซึ่งอาจอยู่ใน process ที่เพิ่งถูกสร้างขึ้นมา
     * เพื่องานนี้โดยเฉพาะ — ทุกอย่างที่จำเป็นจึงอ่านจากดิสก์ ไม่พึ่ง state ในหน่วยความจำ
     */
    fun onSighting(context: Context, regionIdentifier: String, timestampMillis: Long) {
        val appContext = context.applicationContext
        val store = BackgroundRegionStore(appContext)
        if (!store.isActive) return
        if (store.regionFor(regionIdentifier) == null) {
            // region ถูกถอนไปแล้วแต่การลงทะเบียนสแกนยังค้าง — ถอนทิ้งเสียเลย
            // ไม่งั้นจะปลุก process ทิ้ง ๆ ขว้าง ๆ ไปเรื่อยจนกว่าจะรีบูต
            stopScansOnly(appContext, listOf(BeaconRegionSpec(regionIdentifier, ZERO_UUID)))
            return
        }

        val timeoutMillis = store.exitTimeoutSeconds * 1000L
        val now = SystemClock.elapsedRealtime()
        val wasInside = store.isInside(regionIdentifier)

        // เลื่อนนาฬิกาปลุกเฉพาะเมื่อเวลาที่เหลือน้อยกว่า 3 ใน 4 ของหน้าต่าง —
        // ตอนอยู่ใกล้ beacon ผลสแกนเข้ามาถี่มาก การตั้งนาฬิกาปลุกใหม่ทุกครั้งคือ
        // การปลุกระบบทิ้งเปล่าและกินแบตโดยไม่ได้อะไรเพิ่ม
        val scheduledAt = store.scheduledExitAlarmElapsedMillis(regionIdentifier)
        val shouldReschedule = !wasInside ||
            !store.storedElapsedTimesAreFromThisBoot() ||
            scheduledAt - now < timeoutMillis * 3 / 4

        val alarmAt = if (shouldReschedule) now + timeoutMillis else scheduledAt
        store.recordSighting(regionIdentifier, alarmAt)
        if (shouldReschedule) {
            scheduleExitAlarm(appContext, regionIdentifier, alarmAt)
        }

        if (!wasInside) {
            emit(
                appContext,
                BackgroundRegionStateEvent(
                    regionIdentifier = regionIdentifier,
                    state = "enter",
                    timestampMillis = timestampMillis,
                    fromBackgroundProcess = !HostProcessInfo.hasEverBeenForeground,
                ),
            )
        }
    }

    /**
     * นาฬิกาปลุกดังแล้ว — ตรวจว่าครบเวลาจริงหรือยัง
     *
     * **ต้องตรวจซ้ำ ไม่ใช่ประกาศ exit ทันที** เพราะนาฬิกาปลุกอาจดังช้ากว่าที่ตั้งไว้
     * มาก (Doze) และระหว่างนั้นอาจเห็น beacon อีกครั้งแล้ว ถ้าประกาศทันทีจะได้
     * exit ปลอมสลับกับ enter ทันที ซึ่งคือ region flapping ที่ ADR-11 วิเคราะห์ไว้
     * — คราวนี้เป็น flap ที่ **เราสร้างเอง** ไม่ใช่ของแพลตฟอร์ม
     */
    fun onExitAlarm(context: Context, regionIdentifier: String) {
        val appContext = context.applicationContext
        val store = BackgroundRegionStore(appContext)
        if (!store.isActive) return
        if (!store.isInside(regionIdentifier)) return

        val timeoutMillis = store.exitTimeoutSeconds * 1000L
        val now = SystemClock.elapsedRealtime()
        // อ่าน**ก่อน** `markOutside()` เสมอ — เมธอดนั้นลบคีย์ `alarmAtElapsed.*` ทิ้ง
        // (BackgroundRegionStore.markOutside) ถ้าอ่านทีหลังจะได้ 0 ทุกครั้ง
        val scheduledAt = store.scheduledExitAlarmElapsedMillis(regionIdentifier)

        if (!store.storedElapsedTimesAreFromThisBoot()) {
            // เทียบเวลาข้ามรอบบูตไม่ได้ — ประกาศ exit เพราะการลงทะเบียนสแกนหายไป
            // กับการรีบูตอยู่แล้ว การค้างสถานะ "อยู่ในโซน" ไว้ต่อจะแย่กว่า
            store.markOutside(regionIdentifier)
            emit(
                appContext,
                BackgroundRegionStateEvent(
                    regionIdentifier = regionIdentifier,
                    state = "exit",
                    timestampMillis = System.currentTimeMillis(),
                    fromBackgroundProcess = !HostProcessInfo.hasEverBeenForeground,
                    // **ไม่ส่งค่าเวลาเลยในสาขานี้ โดยตั้งใจ** — `scheduledAt` และ
                    // `lastSeenElapsed` ที่เก็บไว้มาจากคนละรอบบูตกับ `now` การลบ
                    // กันจึงให้ตัวเลขที่ดูสมเหตุสมผลแต่ไม่มีความหมาย ซึ่งอันตราย
                    // กว่าการไม่มีค่า · บรรทัด exit ที่ทั้งสามฟิลด์เป็น `n/a`
                    // จึงอ่านได้ว่า "มาจากสาขานี้" — เป็นสาขาเดียวที่ให้ผลแบบนั้น
                ),
            )
            return
        }

        val sinceLastSeen = now - store.lastSeenElapsedMillis(regionIdentifier)
        if (sinceLastSeen < timeoutMillis) {
            // เห็นอีกครั้งหลังตั้งนาฬิกาปลุกไว้ — เลื่อนออกไปแทนการประกาศ exit
            val alarmAt = store.lastSeenElapsedMillis(regionIdentifier) + timeoutMillis
            store.recordExitAlarmScheduled(regionIdentifier, alarmAt)
            scheduleExitAlarm(appContext, regionIdentifier, alarmAt)
            return
        }

        store.markOutside(regionIdentifier)
        emit(
            appContext,
            BackgroundRegionStateEvent(
                regionIdentifier = regionIdentifier,
                state = "exit",
                timestampMillis = System.currentTimeMillis(),
                fromBackgroundProcess = !HostProcessInfo.hasEverBeenForeground,
                // สามค่านี้ทำให้บรรทัด exit อธิบายตัวเองได้โดยไม่ต้องเดา:
                // `sinceLastSeen` = หน้าต่างที่ **ได้จริง** (เทียบกับ 30 วิที่ขอไป)
                // `scheduledAt`/`now` = ระยะที่ระบบเลื่อนนาฬิกาปลุกออกไป
                exitSinceLastSeenMillis = sinceLastSeen,
                exitScheduledAtElapsedMillis = scheduledAt,
                exitFiredAtElapsedMillis = now,
            ),
        )
    }

    /**
     * ส่ง event ออกไปทุกทางที่มี **โดยเรียงลำดับตามความสำคัญของการรอด**
     *
     * 1. [observer] ของ host app (เขียนไฟล์หลักฐาน) — ทำงานได้เสมอ ไม่พึ่ง engine
     * 2. คิวลงดิสก์ **ถ้าไม่มี engine** — เพื่อให้ Dart ได้รับตอนเปิดแอปครั้งถัดไป
     * 3. ส่งเข้า Flutter ทันที **ถ้ามี engine**
     *
     * ลำดับนี้ไม่ใช่เรื่องความสวยงาม: ข้อ 1 ต้องมาก่อนเพราะถ้าระบบฆ่า process
     * ระหว่างทาง อย่างน้อยหลักฐานต้องลงดิสก์แล้ว — เหตุผลเดียวกับที่ฝั่ง iOS เขียน
     * log ก่อนยิง notification เสมอ
     */
    private fun emit(context: Context, event: BackgroundRegionStateEvent) {
        runCatching { observer?.onRegionStateEvent(event) }

        val sink = flutterSink
        if (sink == null) {
            BackgroundRegionStore(context).enqueueEvent(event)
        } else {
            runCatching { sink.onRegionStateEvent(event) }
        }
    }

    // ---- ตัวช่วย ----

    private val ZERO_UUID = java.util.UUID(0, 0)

    /**
     * requestCode ที่ไม่ซ้ำกันต่อ (ชนิด, region)
     *
     * ใช้ `hashCode` ของสตริงซึ่ง **ชนกันได้** ในทางทฤษฎี — ยอมรับได้เพราะมี data
     * URI ที่ไม่ซ้ำเป็นตัวแยกหลักอยู่แล้ว (`Intent.filterEquals` เทียบ data ด้วย)
     * requestCode เป็นแค่ชั้นเสริม ไม่ใช่ตัวแยกเดียว
     */
    private fun requestCodeFor(kind: String, regionIdentifier: String): Int =
        "$kind:$regionIdentifier".hashCode()

    private fun hasScanPermission(context: Context): Boolean {
        val required = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.ACCESS_FINE_LOCATION)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return required.all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * แปลง error code ที่ `startScan` คืนมาเป็นชื่อ — **ไม่ hard-code ตัวเลข throttle**
     *
     * ADR-12 หัวข้อ 2(ค) บันทึกไว้ว่าตัวเลขที่ระบบใช้ throttle ยืนยันไม่ได้จาก
     * เอกสารหรือซอร์สที่ตรวจได้ สิ่งที่ทำได้คือรายงาน code ที่มีความหมายกลับไป
     */
    private fun scanErrorName(code: Int): String = when (code) {
        android.bluetooth.le.ScanCallback.SCAN_FAILED_ALREADY_STARTED ->
            "SCAN_FAILED_ALREADY_STARTED"
        android.bluetooth.le.ScanCallback.SCAN_FAILED_APPLICATION_REGISTRATION_FAILED ->
            "SCAN_FAILED_APPLICATION_REGISTRATION_FAILED"
        android.bluetooth.le.ScanCallback.SCAN_FAILED_FEATURE_UNSUPPORTED ->
            "SCAN_FAILED_FEATURE_UNSUPPORTED"
        android.bluetooth.le.ScanCallback.SCAN_FAILED_INTERNAL_ERROR ->
            "SCAN_FAILED_INTERNAL_ERROR"
        android.bluetooth.le.ScanCallback.SCAN_FAILED_SCANNING_TOO_FREQUENTLY ->
            "SCAN_FAILED_SCANNING_TOO_FREQUENTLY"
        else -> "SCAN_FAILED_UNKNOWN_$code"
    }
}

/**
 * ข้อมูลว่า process นี้เคยมี UI หรือยัง — ตั้งโดย plugin ตอน attach กับ Activity
 *
 * SDK ต้องบอกให้ได้ว่า event ที่ยิงออกไปเกิดตอน process ยังไม่เคยมี UI หรือไม่
 * เพราะนั่นคือความต่างที่ทั้งสปรินต์ต้องพิสูจน์ — และ SDK ต้องไม่บังคับให้ host app
 * ต้องมี `Application` subclass เพื่อจะรู้เรื่องนี้
 */
object HostProcessInfo {
    @Volatile
    var hasEverBeenForeground: Boolean = false
        private set

    fun markForeground() {
        hasEverBeenForeground = true
    }
}
