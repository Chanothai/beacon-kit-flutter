import Flutter
import UIKit

/// region event หนึ่งครั้งในรูปแบบที่ **โค้ด native ของ host app** ใช้ได้ตรง ๆ
///
/// เป็นชนิดข้อมูลของ `startBackgroundRegionMonitoring(onRegionStateEvent:)` —
/// จงใจไม่ใช้ `[String: Any]` แบบเดียวกับ payload ที่ส่งข้าม method channel
/// เพราะฝั่งนั้นถูกบังคับด้วย `StandardMethodCodec` ส่วนฝั่งนี้เป็น Swift ล้วน
/// ไม่มีเหตุผลให้ผู้เรียกต้องมา cast เอง
public struct BeaconKitRegionStateEvent {
  /// identifier ที่แอปตั้งไว้ตอนลงทะเบียน region (ADR-8 ใช้เป็นรหัสสาขา)
  public let regionIdentifier: String
  public let uuid: UUID
  /// `nil` = wildcard ตาม ADR-5
  public let major: UInt16?
  /// `nil` = wildcard ตาม ADR-5
  public let minor: UInt16?
  /// `"enter"` | `"exit"` | `"unknown"` — ค่าเดียวกับ payload ของ ADR-6 หัวข้อ 2
  public let state: String
  public let timestamp: Date
}

/// Entry point ของ `beacon_kit_ios` — register 1 method channel (`beacon_kit_ios/methods`)
/// + 3 event channel แล้ว route คำเรียกไปยัง manager ที่รับผิดชอบตาม path:
///
/// - iBeacon path (CoreLocation, ranging + region monitoring ไม่ผ่าน Dart
///   parser) → `IBeaconRangingManager`
/// - non-iBeacon broadcast path (CoreBluetooth, raw bytes ให้ Dart parser ถอด) →
///   `RawAdvertisementScanner`
///
/// เหตุผลที่ iOS แยกสอง API นี้เด็ดขาดและใช้ปนกันไม่ได้ ดู ARCHITECTURE.md หัวข้อ
/// "ข้อจำกัดของ iOS ที่บังคับให้สถาปัตยกรรมต่างจาก Android" และ ADR-4
/// "iOS platform channel contract"
///
/// **ADR-6 (28 ส.ค. 2026):** เพิ่ม event channel ที่ 3
/// (`beacon_kit_ios/region_state_events`) สำหรับ enter/exit/unknown ของ region
/// — ยิงจาก `IBeaconRangingManager.regionStateStreamHandler` (คนละ stream
/// handler กับ ranging channel แม้จะเป็น manager ตัวเดียวกัน ดูเหตุผลที่
/// `RegionStateEventStreamHandler` ใน `IBeaconRangingManager.swift`)
public class BeaconKitIosPlugin: NSObject, FlutterPlugin {
  /// ใช้ instance ที่ share กันทั้งแอป ไม่ใช่ตัวใหม่ต่อการ register หนึ่งครั้ง —
  /// เหตุผลเต็มอยู่ที่ `IBeaconRangingManager.shared` (ADR-10)
  private let iBeaconRangingManager = IBeaconRangingManager.shared
  private let rawAdvertisementScanner = RawAdvertisementScanner()

  /// เตรียม CoreLocation ให้พร้อมรับ region event **ตั้งแต่รอบ launch** โดยไม่ต้อง
  /// รอ Flutter engine หรือ Dart — เรียกจาก
  /// `application(_:didFinishLaunchingWithOptions:)` ของ host app
  ///
  /// **ทำไม SDK ถึงบังคับเองไม่ได้ และทำไมจำเป็น (ADR-10):**
  /// plugin ของ Flutter ถูก register ผ่าน `GeneratedPluginRegistrant` ซึ่งในแอปที่
  /// ใช้ scene lifecycle จะเกิดใน `didInitializeImplicitFlutterEngine` — header ของ
  /// Flutter ระบุว่า callback นั้น "Called once the implicit `FlutterEngine` is
  /// initialized, such as when created by a FlutterViewController from a
  /// storyboard" (FlutterEngine.h:476-490) นั่นคือมันผูกกับการที่ **UI ถูกสร้าง**
  /// ตอน iOS ปลุก process ที่ถูกฆ่าขึ้นมาเบื้องหลังเพื่อส่ง location event ไม่มี
  /// scene ไหนถูก connect ไม่มี `FlutterViewController` จึงไม่มีการ register
  /// plugin เลย = ไม่มี `CLLocationManager` และไม่มี delegate ให้ CoreLocation
  /// เรียก event ที่แอปถูกปลุกขึ้นมารับจึงตกหายไปทั้งหมด
  ///
  /// ที่ต้องมี `CLLocationManager` + delegate ให้ทันในรอบ launch นั้นตรงกับที่
  /// Apple เขียนไว้ว่า "If your app actively receives and processes location
  /// updates and terminates, it should restart those APIs upon launch in order to
  /// continue receiving updates. When you start those services, the system resumes
  /// the delivery of queued location updates."
  /// (developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
  ///
  /// - Parameter onRegionStateEvent: hook ที่จะถูกเรียกทุกครั้งที่ region เปลี่ยน
  ///   state — ทำงานแม้ Flutter engine ยังไม่มีอยู่ SDK ไม่ยุ่งว่า host จะเอาไปทำ
  ///   อะไร (เขียน log / ยิง notification / ส่งขึ้น server)
  /// - Returns: identifier ของ region ที่ระบบยังเก็บไว้ให้ข้าม launch — ใช้เป็น
  ///   หลักฐานได้ว่า region รอดข้าม process จริงหรือหายไปแล้ว
  @discardableResult
  public static func startBackgroundRegionMonitoring(
    onRegionStateEvent: ((BeaconKitRegionStateEvent) -> Void)? = nil
  ) -> [String] {
    let manager = IBeaconRangingManager.shared
    if let onRegionStateEvent = onRegionStateEvent {
      manager.onRegionStateEvent = onRegionStateEvent
    }
    return manager.monitoredRegionIdentifiers
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BeaconKitIosPlugin()

    let methodChannel = FlutterMethodChannel(
      name: "beacon_kit_ios/methods",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let iBeaconRangingEventChannel = FlutterEventChannel(
      name: "beacon_kit_ios/ibeacon_ranging_events",
      binaryMessenger: registrar.messenger()
    )
    iBeaconRangingEventChannel.setStreamHandler(instance.iBeaconRangingManager)

    let rawAdvertisementEventChannel = FlutterEventChannel(
      name: "beacon_kit_ios/raw_advertisement_events",
      binaryMessenger: registrar.messenger()
    )
    rawAdvertisementEventChannel.setStreamHandler(instance.rawAdvertisementScanner)

    // ADR-6: channel ใหม่ ไม่ reuse ของ ranging เพราะ semantic ต่างกันโดย
    // พื้นฐาน (ยิงถี่มาก vs ยิงเฉพาะตอน state เปลี่ยนจริง — ดู ARCHITECTURE.md
    // ADR-6 หัวข้อ 2 เหตุผลเต็ม)
    let regionStateEventChannel = FlutterEventChannel(
      name: "beacon_kit_ios/region_state_events",
      binaryMessenger: registrar.messenger()
    )
    regionStateEventChannel.setStreamHandler(instance.iBeaconRangingManager.regionStateStreamHandler)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startIBeaconMonitoring":
      handleStartIBeaconMonitoring(call, result: result)
    case "stopIBeaconMonitoring":
      handleStopIBeaconMonitoring(call, result: result)
    case "getIBeaconAuthorizationLevel":
      // B6: method ใหม่ ไม่แตะ signature ของ startIBeaconMonitoring/
      // stopIBeaconMonitoring ตามที่ ADR-6 หัวข้อ 2 ล็อกไว้ — ดูเหตุผลเต็มที่
      // คอมเมนต์ของ case .proceed ใน IBeaconRangingManager.startMonitoring()
      iBeaconRangingManager.currentAuthorizationLevel(result: result)
    case "startBluetoothScan":
      handleStartBluetoothScan(call, result: result)
    case "stopBluetoothScan":
      rawAdvertisementScanner.stopScan()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - CoreLocation (iBeacon) path

  private func handleStartIBeaconMonitoring(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let rawRegions = args["regions"] as? [[String: Any]]
    else {
      // เหตุผลเดียวกับ handleStartBluetoothScan: เคสนี้คือ "argument ผิดรูปแบบ"
      // (ส่งมาไม่ใช่ List<Map> เลย) ซึ่งเป็นบั๊กฝั่งผู้เรียก ไม่ใช่ "UUID string
      // parse ไม่ผ่าน" INVALID_REGION_UUID สงวนไว้ให้เคสหลังเท่านั้น — ยิงจาก
      // IBeaconRangingManager.startMonitoring() ตอน UUID(uuidString:) คืน nil
      result(
        FlutterError(
          code: "INVALID_ARGUMENT",
          message: "'regions' ต้องเป็น List<Map> ที่มี identifier/uuid",
          details: nil
        )
      )
      return
    }
    iBeaconRangingManager.startMonitoring(regions: rawRegions, result: result)
  }

  private func handleStopIBeaconMonitoring(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    let args = call.arguments as? [String: Any]
    let identifiers = args?["identifiers"] as? [String]
    iBeaconRangingManager.stopMonitoring(identifiers: identifiers)
    result(nil)
  }

  // MARK: - CoreBluetooth (non-iBeacon) path

  private func handleStartBluetoothScan(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let serviceUuidStrings = args["serviceUuids"] as? [String]
    else {
      // ห้ามใช้ BLUETOOTH_UNAVAILABLE ตรงนี้ — เคสนี้คือ "ผู้เรียกส่ง argument ผิด
      // รูปแบบ" ซึ่งเป็นบั๊กฝั่ง Dart แก้ได้ด้วยการแก้โค้ด ไม่ใช่สภาวะของ
      // CoreBluetooth (CBManagerState != poweredOn) ที่ผู้ใช้ต้องไปเปิด Bluetooth
      // เอง การใช้ code เดียวกันทำให้ดีบักตอนทดสอบกับเครื่องจริงหลงทาง เพราะจะไป
      // ไล่หาว่า Bluetooth ปิดอยู่หรือเปล่าทั้งที่ปัญหาอยู่คนละที่
      // BLUETOOTH_UNAVAILABLE ตัวจริงยิงจาก RawAdvertisementScanner.swift เท่านั้น
      result(
        FlutterError(
          code: "INVALID_ARGUMENT",
          message: "'serviceUuids' ต้องเป็น List<String> (ไม่มี wildcard scan)",
          details: nil
        )
      )
      return
    }
    rawAdvertisementScanner.startScan(serviceUuidStrings: serviceUuidStrings, result: result)
  }
}
