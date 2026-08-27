import Flutter
import UIKit

/// Entry point ของ `beacon_kit_ios` — register 1 method channel (`beacon_kit_ios/methods`)
/// + 2 event channel แล้ว route คำเรียกไปยัง manager ที่รับผิดชอบตาม path:
///
/// - iBeacon path (CoreLocation, ranging เท่านั้น ไม่ผ่าน Dart parser) →
///   `IBeaconRangingManager`
/// - non-iBeacon broadcast path (CoreBluetooth, raw bytes ให้ Dart parser ถอด) →
///   `RawAdvertisementScanner`
///
/// เหตุผลที่ iOS แยกสอง API นี้เด็ดขาดและใช้ปนกันไม่ได้ ดู ARCHITECTURE.md หัวข้อ
/// "ข้อจำกัดของ iOS ที่บังคับให้สถาปัตยกรรมต่างจาก Android" และ ADR-4
/// "iOS platform channel contract"
public class BeaconKitIosPlugin: NSObject, FlutterPlugin {
  private let iBeaconRangingManager = IBeaconRangingManager()
  private let rawAdvertisementScanner = RawAdvertisementScanner()

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
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startIBeaconMonitoring":
      handleStartIBeaconMonitoring(call, result: result)
    case "stopIBeaconMonitoring":
      handleStopIBeaconMonitoring(call, result: result)
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
