package com.bigc.beacon_kit_android

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.UUID

/**
 * Entry point ของ `beacon_kit_android`
 *
 * ## ขอบเขตตอนนี้: สองเส้นทางที่ **แยกกันโดยสิ้นเชิง**
 *
 * | เส้นทาง | ใช้อะไร | ทำงานเมื่อ |
 * |---|---|---|
 * | สแกนตอนแอปเปิดอยู่ (ก้อนที่ 1, ADR-12) | `startScan(..., ScanCallback)` | เฉพาะตอน process มีชีวิตและมีคนฟัง stream |
 * | เฝ้า region เบื้องหลัง (ก้อนที่ 2, ADR-14) | `startScan(..., PendingIntent)` + นาฬิกาปลุก | แม้ process ตายไปแล้ว — ระบบสร้าง process ใหม่มาส่งให้ |
 *
 * **สองเส้นทางนี้ไม่ใช่ "โหมด" ของกันและกัน** ใช้พร้อมกันได้และไม่รบกวนกัน แต่ก็
 * ไม่ทดแทนกัน: เส้นทางแรกให้ advertisement ดิบทุกใบ เส้นทางที่สองให้แค่ enter/exit
 *
 * ส่ง **byte ดิบ** กลับไปให้ Dart parser ถอด ไม่มี parser ฝั่ง Kotlin เลย —
 * ตั้งใจให้ทั้ง iOS และ Android ใช้โค้ดถอดรหัสชุดเดียวกันใน
 * `beacon_kit_platform_interface` เส้นทางเบื้องหลังรักษากติกานี้ไว้ได้ด้วยการ
 * ลงทะเบียนสแกน **หนึ่งครั้งต่อหนึ่ง region** พร้อม `ScanFilter` ที่เจาะจงถึงระดับ
 * UUID/major/minor จึงรู้ว่าเป็น region ไหนโดยไม่ต้องถอด byte เลย
 * (ดู `BeaconRegionSpec.toScanFilter`)
 */
class BeaconKitAndroidPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private companion object {
        const val METHOD_CHANNEL = "beacon_kit_android/methods"
        const val EVENT_CHANNEL = "beacon_kit_android/raw_advertisement_events"

        /**
         * ช่องของ event เข้า/ออก region ที่คำนวณเบื้องหลัง (ADR-14)
         *
         * **แยกจาก `EVENT_CHANNEL` ด้วยเหตุผลเดียวกับที่ ADR-6 แยกฝั่ง iOS:**
         * ผลสแกนดิบมาถี่มาก ส่วน enter/exit นาน ๆ ครั้ง ถ้ารวมช่องเดียวกัน
         * ผู้ฟังที่สนใจแค่ enter/exit ต้อง deserialize แล้วกรองทิ้งตลอดเวลา
         *
         * **ชื่อไม่มีคำว่า `ibeacon` โดยตั้งใจ** — ฝั่ง iOS ใช้
         * `region_state_events` ที่มาจาก CoreLocation ส่วนฝั่งนี้เราคำนวณเอง
         * ชื่อ `background_region_events` บอกที่มาตรงตัวว่าเป็นเส้นทางเบื้องหลัง
         */
        const val BACKGROUND_REGION_EVENT_CHANNEL =
            "beacon_kit_android/background_region_events"

        /** request code ของเราเอง — เลือกค่าที่ไม่ชนกับ plugin อื่นทั่วไป */
        const val PERMISSION_REQUEST_CODE = 0xBEAC

        /** company ID ของ Apple ที่ iBeacon ใช้ */
        const val APPLE_COMPANY_ID = 0x004C

        /**
         * `ScanRecord.getManufacturerSpecificData(id)` **ตัด company ID ออกไปแล้ว**
         * แต่ `IBeaconParser` ฝั่ง Dart คาดหวัง AD value เต็ม 25 bytes รวม company ID
         * (ระบุไว้ใน doc ของ parser เอง) — จึงต้องต่อกลับเข้าไปก่อนส่งข้าม channel
         * little-endian: 0x4C 0x00
         */
        val APPLE_COMPANY_ID_PREFIX = byteArrayOf(0x4C, 0x00)
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var backgroundRegionChannel: EventChannel? = null
    private var backgroundRegionSink: EventChannel.EventSink? = null
    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var scanner: BluetoothLeScanner? = null
    private var isScanning = false

    /**
     * `MethodChannel.Result` ของคำขอสิทธิ์ที่ค้างอยู่
     *
     * **ต้องถูกเรียกให้ครบพอดีหนึ่งครั้งเสมอ** — บทเรียนตรงจากบั๊กบน iOS รอบ 2
     * (ARCHITECTURE.md ADR-6): ถ้าปล่อยให้มี Future ที่ไม่มีวัน complete ฝั่ง Dart
     * จะค้างเงียบโดยไม่มี error ซึ่งเป็นอาการที่ดีบักยากที่สุด
     */
    private var pendingPermissionResult: MethodChannel.Result? = null

    // ---- FlutterPlugin ----

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext

        // ADR-17 หัวข้อ 3: ต้องมาก่อน `drainQueuedBackgroundEvents()` (เรียกจาก
        // ใน `onListen` ของ backgroundRegionChannel ด้านล่าง) เสมอ — ถ้า
        // reconcile() สังเคราะห์ exit(stale) ขึ้นมาใหม่ ต้องถูก enqueue ก่อนการ
        // drain ครั้งนี้ ไม่งั้น event ที่เพิ่งสังเคราะห์จะตกค้างรอรอบเปิดแอป
        // ถัดไป ทั้งที่ควรไหลออกไปพร้อมคิวเดิมทันที — วางไว้ตรงนี้ (ต้นสุดของ
        // onAttachedToEngine) รับประกันลำดับได้เพราะเมธอดนี้ทำงานจบก่อนเสมอ
        // ก่อนที่ Dart จะเรียก listen() บนช่องที่กำลังจะสร้างข้างล่าง
        BackgroundRegionMonitor.reconcile(applicationContext!!)

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(this@BeaconKitAndroidPlugin)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).apply {
            setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
        backgroundRegionChannel =
            EventChannel(binding.binaryMessenger, BACKGROUND_REGION_EVENT_CHANNEL).apply {
                setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        backgroundRegionSink = events
                        BackgroundRegionMonitor.setFlutterSink { event ->
                            mainHandler.post { backgroundRegionSink?.success(event.toMap()) }
                        }
                        // ส่ง event ที่คิวไว้ตอนไม่มี engine ให้ครบก่อน แล้วค่อยรับ
                        // ของใหม่ — ต้องทำ **หลัง** ตั้ง sink เพื่อไม่ให้ event ที่มา
                        // ระหว่างนั้นตกหล่นระหว่างสองขั้นตอน
                        drainQueuedBackgroundEvents()
                    }

                    override fun onCancel(arguments: Any?) {
                        // ถอด sink ก่อนล้างตัวแปร เพื่อให้ event ที่เกิดหลังจากนี้
                        // ถูกคิวลงดิสก์แทนการหายไปเงียบ ๆ
                        BackgroundRegionMonitor.setFlutterSink(null)
                        backgroundRegionSink = null
                    }
                })
            }
    }

    /**
     * ส่ง event ที่เกิดตอนไม่มี Flutter engine ออกไปให้ Dart
     *
     * เส้นทางนี้คือสิ่งที่ทำให้ "แอปถูกปลุกตอนปิดอยู่แล้วเจอ beacon" ไปถึงผู้ใช้ SDK
     * ได้จริง — ถ้าไม่มี event เหล่านั้นจะหายทั้งหมดและไม่มีใครรู้ว่าเคยมี
     */
    private fun drainQueuedBackgroundEvents() {
        val context = applicationContext ?: return
        val queued = BackgroundRegionStore(context).drainPendingEvents()
        if (queued.isEmpty()) return
        mainHandler.post {
            for (event in queued) {
                backgroundRegionSink?.success(event.toMap())
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopScanInternal()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        backgroundRegionChannel?.setStreamHandler(null)
        // **ห้ามเรียก BackgroundRegionMonitor.stop() ตรงนี้** — engine ถูก detach
        // ทุกครั้งที่ผู้ใช้ปิดแอป ซึ่งเป็นเวลาที่การเฝ้าเบื้องหลัง *ต้อง* ยังอยู่
        // เป็นกับดักแบบเดียวกับที่ฝั่ง iOS ห้ามเรียก stopMonitoring ในเส้นทาง launch
        // (ดูคอมเมนต์ใน IBeaconRangingManager.init())
        BackgroundRegionMonitor.setFlutterSink(null)
        backgroundRegionSink = null
        methodChannel = null
        eventChannel = null
        backgroundRegionChannel = null
        applicationContext = null
        // คำขอที่ค้างต้องถูกปลดเสมอ ไม่งั้นฝั่ง Dart ค้างตลอดไป
        failPendingPermissionResult("engine ถูก detach ก่อนผู้ใช้ตอบ prompt")
    }

    // ---- ActivityAware ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
        // มี Activity = process นี้มี UI แล้ว จึงไม่ใช่ process ที่ระบบสร้างขึ้นมา
        // เองล้วน ๆ — ค่านี้ถูกติดไปกับทุก event เบื้องหลังเพื่อให้แยกได้ภายหลังว่า
        // event เกิดตอนแอปเปิดอยู่หรือตอนแอปถูกปิดไปแล้ว
        HostProcessInfo.markForeground()
        // ADR-17 หัวข้อ 3: แอปขึ้น foreground คือโอกาสที่ CPU ตื่นแน่นอน แม้
        // ผู้ใช้จะไม่ได้เดินเข้าใกล้ beacon เลยก็ตาม — ลำดับกับ markForeground()
        // ข้างบนไม่มีผล (ไม่ตัดกัน)
        BackgroundRegionMonitor.reconcile(binding.activity.applicationContext)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        // ไม่มี activity แล้ว = ไม่มีทางได้ callback ของ permission อีก ต้องปลดทันที
        failPendingPermissionResult("Activity ถูก detach ก่อนผู้ใช้ตอบ prompt")
    }

    // ---- MethodCallHandler ----

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startBluetoothScan" -> handleStartScan(call, result)
            "stopBluetoothScan" -> {
                stopScanInternal()
                result.success(null)
            }
            "startBackgroundRegionMonitoring" -> handleStartBackgroundMonitoring(call, result)
            "stopBackgroundRegionMonitoring" -> {
                val context = applicationContext
                if (context == null) {
                    result.error("BLUETOOTH_UNAVAILABLE", "ยังไม่ได้ attach กับ engine", null)
                } else {
                    BackgroundRegionMonitor.stop(context)
                    result.success(null)
                }
            }
            "getBackgroundRegionMonitoringStatus" -> handleBackgroundStatus(result)
            "getScanPermissionStatus" -> result.success(currentPermissionStatus())
            "requestScanPermissions" -> handleRequestPermissions(result)
            "openAppSettings" -> handleOpenAppSettings(result)
            else -> result.notImplemented()
        }
    }

    // ---- สแกน ----

    private fun handleStartScan(call: MethodCall, result: MethodChannel.Result) {
        val serviceUuids = call.argument<List<String>>("serviceUuids")
        if (serviceUuids == null) {
            // เคสนี้คือ "ผู้เรียกส่ง argument ผิดรูปแบบ" ซึ่งเป็นบั๊กของโค้ด
            // ไม่ใช่สภาวะของเครื่อง — แยก code ให้ชัดเหมือนฝั่ง iOS (ADR-4)
            // เพราะการใช้ code เดียวกันเคยทำให้ไล่หาสาเหตุผิดทางมาแล้ว
            result.error(
                "INVALID_ARGUMENT",
                "'serviceUuids' ต้องเป็น List<String>",
                null,
            )
            return
        }

        val context = applicationContext
        if (context == null) {
            result.error("BLUETOOTH_UNAVAILABLE", "ยังไม่ได้ attach กับ engine", null)
            return
        }

        if (currentPermissionStatus() != "granted") {
            result.error(
                "BLUETOOTH_PERMISSION_DENIED",
                "ยังไม่ได้สิทธิ์ BLUETOOTH_SCAN และ/หรือ ACCESS_FINE_LOCATION",
                null,
            )
            return
        }

        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)
            ?.adapter
        if (adapter == null || !adapter.isEnabled) {
            result.error(
                "BLUETOOTH_UNAVAILABLE",
                "Bluetooth ปิดอยู่หรือเครื่องไม่รองรับ",
                null,
            )
            return
        }

        val leScanner = adapter.bluetoothLeScanner
        if (leScanner == null) {
            result.error("BLUETOOTH_UNAVAILABLE", "ไม่มี BluetoothLeScanner", null)
            return
        }

        stopScanInternal()

        val filters = buildScanFilters(serviceUuids)
        if (filters.isEmpty()) {
            // กันไม่ให้หลุดไปเป็น unfiltered scan โดยไม่ตั้งใจ — ดูเหตุผลที่
            // buildScanFilters()
            result.error(
                "INVALID_ARGUMENT",
                "ต้องระบุ serviceUuids อย่างน้อย 1 ตัว (ห้าม unfiltered scan)",
                null,
            )
            return
        }

        val settings = ScanSettings.Builder()
            // SCAN_MODE_LOW_LATENCY เหมาะกับ foreground เท่านั้น (ScanSettings.java:60-63)
            // และระบบจะบังคับลดเป็น SCAN_MODE_LOW_POWER เองทันทีที่แอปไม่ได้อยู่
            // foreground (ScanSettings.java:48-52) — ก้อนที่ 1 จึงตั้งค่านี้ได้ตรงไปตรงมา
            // ส่วนก้อนที่ 2 (เบื้องหลัง) ต้องออกแบบใหม่ ไม่ใช่เอาโค้ดนี้ไปรันต่อ
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()

        try {
            leScanner.startScan(filters, settings, scanCallback)
            scanner = leScanner
            isScanning = true
            result.success(null)
        } catch (error: SecurityException) {
            // ถึงจะเช็คสิทธิ์ไปแล้วข้างบน ระบบก็ยังปฏิเสธได้ (เช่นสิทธิ์ถูกถอน
            // ระหว่างทาง) — ต้องดักไว้ ไม่ปล่อยให้ crash
            result.error("BLUETOOTH_PERMISSION_DENIED", error.message, null)
        }
    }

    /**
     * สร้าง `ScanFilter` — **ต้องมีอย่างน้อย 1 ตัวเสมอ ห้าม unfiltered scan**
     *
     * เหตุผลจาก `BluetoothLeScanner.java:104-107`: "For unfiltered scans, scanning
     * is stopped on screen off to save power... To avoid this, use
     * startScan(List, ScanSettings, ScanCallback) with desired ScanFilter."
     *
     * **ทำไมต้องมี filter ของ Apple manufacturer data เพิ่มจาก service UUID:**
     * iBeacon ไม่ได้ประกาศ service UUID ใด ๆ เลย ข้อมูลอยู่ใน manufacturer data
     * ล้วน ๆ ถ้ากรองด้วย service UUID อย่างเดียวจะไม่มีวันเห็น iBeacon —
     * `ScanFilter` หลายตัวถูกนำมา **OR** กัน จึงเพิ่มเข้าไปได้โดยไม่กระทบ Eddystone
     *
     * mask `0xFF 0xFF` = ต้องตรงทั้งสอง byte (`0x02 0x15` คือ iBeacon type + length
     * ที่คงที่เสมอ) เพื่อไม่ให้ manufacturer data อื่นของ Apple หลุดเข้ามาด้วย
     */
    private fun buildScanFilters(serviceUuids: List<String>): List<ScanFilter> {
        val filters = serviceUuids.mapNotNull { raw ->
            runCatching { UUID.fromString(raw) }.getOrNull()?.let { uuid ->
                ScanFilter.Builder().setServiceUuid(ParcelUuid(uuid)).build()
            }
        }.toMutableList()

        if (filters.isNotEmpty()) {
            filters.add(
                ScanFilter.Builder()
                    .setManufacturerData(
                        APPLE_COMPANY_ID,
                        byteArrayOf(0x02, 0x15),
                        byteArrayOf(0xFF.toByte(), 0xFF.toByte()),
                    )
                    .build(),
            )
        }
        return filters
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            result ?: return
            val payload = buildPayload(result)
            // callback ของ BLE ไม่ได้อยู่บน main thread แต่ EventSink ต้องถูกเรียก
            // จาก main thread เท่านั้น
            mainHandler.post { eventSink?.success(payload) }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
            results?.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
        }

        override fun onScanFailed(errorCode: Int) {
            val code = when (errorCode) {
                SCAN_FAILED_ALREADY_STARTED -> "SCAN_FAILED_ALREADY_STARTED"
                SCAN_FAILED_APPLICATION_REGISTRATION_FAILED ->
                    "SCAN_FAILED_APPLICATION_REGISTRATION_FAILED"
                SCAN_FAILED_FEATURE_UNSUPPORTED -> "SCAN_FAILED_FEATURE_UNSUPPORTED"
                SCAN_FAILED_INTERNAL_ERROR -> "SCAN_FAILED_INTERNAL_ERROR"
                // ADR-12: ตัวเลขที่ระบบใช้ throttle ยืนยันไม่ได้จากเอกสาร จึงไม่
                // hard-code อะไรทั้งสิ้น แค่ส่ง error code ที่มีความหมายกลับไป
                // ให้ฝั่ง Dart แสดงผล ดีกว่าเงียบแล้วให้คนเดาเอง
                SCAN_FAILED_SCANNING_TOO_FREQUENTLY -> "SCAN_FAILED_SCANNING_TOO_FREQUENTLY"
                else -> "SCAN_FAILED_UNKNOWN_$errorCode"
            }
            mainHandler.post {
                eventSink?.error(code, "BluetoothLeScanner เริ่มสแกนไม่สำเร็จ", null)
            }
        }
    }

    /**
     * แปลง `ScanResult` เป็น map ที่ฝั่ง Dart อ่านได้ — **ส่ง byte ดิบ ไม่ถอดอะไร**
     */
    private fun buildPayload(result: ScanResult): Map<String, Any?> {
        val record = result.scanRecord

        val serviceData = mutableMapOf<String, ByteArray>()
        record?.serviceData?.forEach { (parcelUuid, bytes) ->
            // key เป็น 128-bit lowercase ให้ตรงกับฝั่ง iOS เพื่อให้โค้ด Dart
            // ชุดเดียวกันหา key เจอทั้งสองแพลตฟอร์ม
            serviceData[parcelUuid.uuid.toString().lowercase()] = bytes
        }

        val appleData = record?.getManufacturerSpecificData(APPLE_COMPANY_ID)
        val appleWithCompanyId = appleData?.let { APPLE_COMPANY_ID_PREFIX + it }

        return mapOf(
            "deviceAddress" to result.device.address,
            "rssi" to result.rssi,
            "timestamp" to System.currentTimeMillis(),
            "serviceData" to serviceData,
            "appleManufacturerData" to appleWithCompanyId,
        )
    }

    private fun stopScanInternal() {
        if (!isScanning) return
        runCatching { scanner?.stopScan(scanCallback) }
        isScanning = false
        scanner = null
    }

    // ---- สิทธิ์ ----

    /**
     * สิทธิ์ที่ต้องมีครบ — ต่างกันตามเวอร์ชัน Android (ADR-12)
     *
     * `BLUETOOTH_SCAN` มีเฉพาะ Android 12 (API 31) ขึ้นไป ส่วน `ACCESS_FINE_LOCATION`
     * ต้องมีทุกเวอร์ชันเพราะเราอนุมานตำแหน่งจริง
     */
    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.ACCESS_FINE_LOCATION)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun currentPermissionStatus(): String {
        val context = applicationContext ?: return "denied"
        val missing = requiredPermissions().filter {
            ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) return "granted"

        val currentActivity = activity ?: return "denied"
        // ถ้าระบบบอกว่าไม่ต้องแสดงเหตุผลแล้ว = จะไม่แสดง prompt ให้อีก
        // (ผู้ใช้เลือกไม่ให้ถามซ้ำ หรือถูกนโยบายของเครื่องบล็อก)
        val anyBlocked = missing.any {
            !ActivityCompat.shouldShowRequestPermissionRationale(currentActivity, it)
        }
        return if (anyBlocked) "permanentlyDenied" else "denied"
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        if (currentPermissionStatus() == "granted") {
            result.success("granted")
            return
        }

        val currentActivity = activity
        if (currentActivity == null) {
            // **branch ที่ห้ามลืม** — ไม่มี Activity = ไม่มีทางได้ callback
            // ถ้าเก็บ result ไว้รอ ฝั่ง Dart จะค้างตลอดไปโดยไม่มี error
            result.error(
                "NO_ACTIVITY",
                "ขอสิทธิ์ไม่ได้เพราะยังไม่มี Activity attach อยู่",
                null,
            )
            return
        }

        if (pendingPermissionResult != null) {
            // มีคำขอค้างอยู่แล้ว — ตอบทันทีแทนการต่อคิว เพราะ Android จะไม่แสดง
            // prompt ซ้อน และคำขอที่สองจะไม่มีวันได้ callback ของตัวเอง
            result.error(
                "REQUEST_IN_PROGRESS",
                "มีคำขอสิทธิ์ค้างอยู่ รอผู้ใช้ตอบ prompt เดิมก่อน",
                null,
            )
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            currentActivity,
            requiredPermissions(),
            PERMISSION_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false

        val pending = pendingPermissionResult
        pendingPermissionResult = null

        // อ่านสถานะจากระบบใหม่เสมอ ไม่สรุปจาก grantResults อย่างเดียว เพราะต้อง
        // แยก denied ออกจาก permanentlyDenied ซึ่งต้องถาม
        // shouldShowRequestPermissionRationale หลังผู้ใช้ตอบแล้วเท่านั้น
        pending?.success(currentPermissionStatus())
        return true
    }

    private fun failPendingPermissionResult(reason: String) {
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        pending.error("PERMISSION_REQUEST_ABORTED", reason, null)
    }

    // ---- เฝ้า region เบื้องหลัง (ADR-14) ----

    /**
     * ลงทะเบียนเฝ้า region เบื้องหลัง
     *
     * **ตอบกลับด้วยผลรายอันเสมอ ไม่ตอบแค่ success/fail รวม** — `startScan` ที่รับ
     * `PendingIntent` คืน `int` แทนการ throw ถ้าเราสรุปเป็นค่าเดียว ผู้เรียกจะไม่มี
     * ทางรู้ว่า region ไหนลงทะเบียนไม่ติด และอาการจะออกมาเป็น "บางสาขาใช้ได้ บาง
     * สาขาไม่ได้" ที่ไล่หาสาเหตุยากมาก
     */
    private fun handleStartBackgroundMonitoring(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val context = applicationContext
        if (context == null) {
            result.error("BLUETOOTH_UNAVAILABLE", "ยังไม่ได้ attach กับ engine", null)
            return
        }

        val rawRegions = call.argument<List<Map<*, *>>>("regions")
        if (rawRegions == null || rawRegions.isEmpty()) {
            result.error(
                "INVALID_ARGUMENT",
                "'regions' ต้องเป็น List ที่มีอย่างน้อย 1 region",
                null,
            )
            return
        }

        val regions = rawRegions.mapNotNull(BeaconRegionSpec::fromMap)
        if (regions.size != rawRegions.size) {
            result.error(
                "INVALID_REGION_UUID",
                "มี region ที่ไม่มี identifier หรือ uuid ที่ถูกต้อง",
                null,
            )
            return
        }
        val duplicateIdentifiers = regions.groupBy { it.identifier }
            .filterValues { it.size > 1 }
            .keys
        if (duplicateIdentifiers.isNotEmpty()) {
            // identifier คือกุญแจของทุกอย่างที่เก็บลงดิสก์ ถ้าซ้ำ สถานะของสอง region
            // จะทับกันเงียบ ๆ แล้วรายงาน enter/exit ผิดโดยไม่มีอะไรฟ้อง
            result.error(
                "INVALID_ARGUMENT",
                "identifier ของ region ต้องไม่ซ้ำกัน: $duplicateIdentifiers",
                null,
            )
            return
        }

        val exitTimeoutSeconds = (call.argument<Number>("exitTimeoutSeconds"))?.toInt()
            ?: BackgroundRegionStore.DEFAULT_EXIT_TIMEOUT_SECONDS
        if (exitTimeoutSeconds <= 0) {
            result.error(
                "INVALID_ARGUMENT",
                "'exitTimeoutSeconds' ต้องมากกว่า 0",
                null,
            )
            return
        }

        val started = BackgroundRegionMonitor.start(context, regions, exitTimeoutSeconds)
        result.success(
            mapOf(
                "registered" to started.registered,
                "failed" to started.failed,
            ),
        )
    }

    /**
     * สถานะปัจจุบันของการเฝ้าเบื้องหลัง — คู่ขนานกับสิ่งที่ฝั่ง iOS ได้จาก
     * `CLLocationManager.monitoredRegions`
     *
     * ⚠️ **แต่ที่มาต่างกันโดยสิ้นเชิง และห้ามอธิบายให้ฟังดูเหมือนกัน** ฝั่ง iOS
     * ค่านั้นมาจาก **ระบบ** เป็นคำตอบว่า "ระบบกำลังเฝ้าอะไรอยู่จริง" ส่วนค่านี้
     * มาจาก **ไฟล์ของเราเอง** เป็นคำตอบว่า "เราเคยสั่งให้เฝ้าอะไรไว้"
     * ถ้าระบบล้างการลงทะเบียนทิ้ง (เช่นหลัง force-stop) ค่านี้จะยัง**บอกว่ามี**
     * ทั้งที่ไม่มีอะไรทำงานอยู่แล้ว — Android ไม่มี API ให้ถามความจริงข้อนั้น
     */
    private fun handleBackgroundStatus(result: MethodChannel.Result) {
        val context = applicationContext
        if (context == null) {
            result.error("BLUETOOTH_UNAVAILABLE", "ยังไม่ได้ attach กับ engine", null)
            return
        }
        val store = BackgroundRegionStore(context)
        result.success(
            mapOf(
                "isActive" to store.isActive,
                "regionIdentifiers" to store.regions.map { it.identifier },
                "exitTimeoutSeconds" to store.exitTimeoutSeconds,
                "queuedEventCount" to store.pendingEventCount(),
            ),
        )
    }

    private fun handleOpenAppSettings(result: MethodChannel.Result) {
        val context = applicationContext
        if (context == null) {
            result.error("NO_CONTEXT", "ยังไม่ได้ attach กับ engine", null)
            return
        }
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", context.packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        result.success(null)
    }
}
