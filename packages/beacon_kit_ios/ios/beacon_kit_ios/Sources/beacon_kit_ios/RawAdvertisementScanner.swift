import CoreBluetooth
import Flutter

/// จัดการ path non-iBeacon (Eddystone/Ksensor/custom) บน iOS ผ่าน **CoreBluetooth**
/// (`CBCentralManager`) — ส่ง raw advertisement bytes ออกไปเท่านั้น ไม่ถอดรหัสฝั่ง
/// native เลย (Dart parser เช่น `EddystoneParser` เป็นคน parse ต่อ)
///
/// เหตุผลที่ iBeacon ห้ามผ่าน path นี้: iOS mask manufacturer data ของ iBeacon ทิ้ง
/// ที่ระดับ CoreBluetooth เอง เห็นได้แค่ peripheral identifier + RSSI ไม่มี
/// major/minor ให้ — ดู ARCHITECTURE.md หัวข้อ "ข้อจำกัดของ iOS ที่บังคับให้
/// สถาปัตยกรรมต่างจาก Android" — ตาม ADR-4 ห้ามส่ง manufacturerData ของ iBeacon มา
/// ช่องนี้เด็ดขาด แม้ native จะเห็นก็ตาม (ถือว่าเกินสโคป ไม่ decode ในรอบนี้)
final class RawAdvertisementScanner: NSObject, CBCentralManagerDelegate, FlutterStreamHandler {
  private var centralManager: CBCentralManager?
  private var eventSink: FlutterEventSink?

  /// เก็บคำขอ startScan ที่รอ `centralManagerDidUpdateState` ครั้งแรกอยู่ (สร้าง
  /// `CBCentralManager` แบบ lazy เพราะสถานะจริงรู้ได้ก็ต่อเมื่อ delegate callback
  /// แรกถูกเรียกเท่านั้น)
  private var pendingServiceUuidStrings: [String]?
  private var pendingResult: FlutterResult?

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Method channel entry points

  /// [serviceUuidStrings] บังคับระบุเสมอ ไม่มี wildcard scan (ตาม ADR-4 — เพื่อให้
  /// contract เดียวกันทำงานถูกทั้ง foreground/background)
  func startScan(serviceUuidStrings: [String], result: @escaping FlutterResult) {
    guard let centralManager = centralManager else {
      // ยังไม่เคยสร้าง CBCentralManager มาก่อน — สร้างแล้วรอ
      // centralManagerDidUpdateState บอกสถานะจริงก่อนค่อย scan
      pendingServiceUuidStrings = serviceUuidStrings
      pendingResult = result
      self.centralManager = CBCentralManager(delegate: self, queue: nil)
      return
    }
    startScanIfReady(centralManager: centralManager, serviceUuidStrings: serviceUuidStrings, result: result)
  }

  func stopScan() {
    centralManager?.stopScan()
  }

  private func startScanIfReady(
    centralManager: CBCentralManager,
    serviceUuidStrings: [String],
    result: @escaping FlutterResult
  ) {
    switch centralManager.state {
    case .unauthorized:
      result(
        FlutterError(
          code: "BLUETOOTH_PERMISSION_DENIED",
          message: "Bluetooth permission denied",
          details: nil
        )
      )
      return
    case .poweredOn:
      break
    default:
      result(
        FlutterError(
          code: "BLUETOOTH_UNAVAILABLE",
          message: "Bluetooth state is \(centralManager.state.rawValue), expected poweredOn",
          details: nil
        )
      )
      return
    }

    let serviceUuids = serviceUuidStrings.map { CBUUID(string: $0) }
    centralManager.scanForPeripherals(withServices: serviceUuids, options: nil)
    result(nil)
  }

  // MARK: - CBCentralManagerDelegate

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard let serviceUuidStrings = pendingServiceUuidStrings, let result = pendingResult else {
      return
    }
    pendingServiceUuidStrings = nil
    pendingResult = nil
    startScanIfReady(centralManager: central, serviceUuidStrings: serviceUuidStrings, result: result)
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    guard let eventSink = eventSink else { return }

    var payload: [String: Any] = [
      "peripheralId": peripheral.identifier.uuidString,
      "rssi": RSSI.intValue,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000),
    ]

    // ห้ามส่ง manufacturerData ของ iBeacon มาช่องนี้เด็ดขาด (ADR-4) — ถ้า native เห็น
    // CBAdvertisementDataManufacturerDataKey ใน advertisementData ให้ข้ามไปเลย ไม่
    // ต้องใส่อะไรเกี่ยวกับมันใน payload (เกินสโคปสปรินต์นี้)
    if let rawServiceData = advertisementData[CBAdvertisementDataServiceDataKey]
      as? [CBUUID: Data]
    {
      var serviceData: [String: FlutterStandardTypedData] = [:]
      for (cbuuid, data) in rawServiceData {
        serviceData[Self.fullUuidString(from: cbuuid)] = FlutterStandardTypedData(bytes: data)
      }
      payload["serviceData"] = serviceData
    }

    eventSink(payload)
  }

  /// `CBUUID.uuidString` คืนรูปสั้น (4 hex สำหรับ 16-bit เช่น `"FEAA"`, 8 hex สำหรับ
  /// 32-bit) หรือรูปเต็ม 36 ตัวอักษรสำหรับ 128-bit แล้วแต่ว่า Bluetooth SIG UUID นั้น
  /// เป็นแบบไหน — ADR-4 กำหนดให้ key ของ `serviceData` เป็นรูปเต็มเสมอ
  /// (`0000feaa-0000-1000-8000-00805f9b34fb`) จึงต้อง normalize โดยขยายด้วย
  /// Bluetooth Base UUID เอง
  private static func fullUuidString(from cbuuid: CBUUID) -> String {
    let raw = cbuuid.uuidString
    if raw.count == 36 {
      return raw.lowercased()
    }

    let first8Chars: String
    switch raw.count {
    case 4:
      first8Chars = "0000" + raw
    case 8:
      first8Chars = raw
    default:
      // ไม่ควรเกิดขึ้นจริง (CBUUID รองรับแค่ 16/32/128-bit) — fallback แบบปลอดภัย
      first8Chars = raw.padding(toLength: 8, withPad: "0", startingAt: 0)
    }
    return "\(first8Chars)-0000-1000-8000-00805f9b34fb".lowercased()
  }
}
