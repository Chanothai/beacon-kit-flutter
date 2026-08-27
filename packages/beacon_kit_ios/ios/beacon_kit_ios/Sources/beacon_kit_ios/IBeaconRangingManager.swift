import CoreLocation
import Flutter

/// จัดการ path ของ iBeacon บน iOS ผ่าน **CoreLocation** (`CLLocationManager`) — ไม่ใช่
/// CoreBluetooth เพราะ iOS mask ข้อมูล iBeacon ทิ้งที่ระดับ CoreBluetooth ทั้งหมด
/// (เห็นได้แค่ peripheral identifier + RSSI) CoreLocation เป็นทางเดียวที่ได้
/// uuid/major/minor/proximity แบบถอดมาให้แล้ว — ดู ARCHITECTURE.md หัวข้อ
/// "ข้อจำกัดของ iOS ที่บังคับให้สถาปัตยกรรมต่างจาก Android"
///
/// ยิง event ผ่าน `FlutterEventSink` ทุกครั้งที่ CoreLocation เรียก
/// `locationManager(_:didRange:satisfying:)` — เป็น batch ตามที่ OS ให้มา 1:1 กับ
/// callback (ฝั่ง Dart เป็นคน flatten เป็น `BeaconAdvertisement` ทีละตัวตาม ADR-4)
final class IBeaconRangingManager: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
  private let locationManager = CLLocationManager()
  private var eventSink: FlutterEventSink?

  /// region ที่กำลัง monitor+range อยู่ตอนนี้ keyed ด้วย identifier ที่แอปกำหนดมา —
  /// ใช้ทั้งตอน stop แบบเจาะจง และตอนหา regionIdentifier กลับจาก
  /// `CLBeaconIdentityConstraint` ที่ `didRange` ส่งมา (ดู ค.ห. ท้ายไฟล์)
  private var constraintsByIdentifier: [String: CLBeaconIdentityConstraint] = [:]

  /// เพดาน region ที่ `CLLocationManager` รองรับพร้อมกันบน iOS
  private static let maxMonitoredRegions = 20

  override init() {
    super.init()
    locationManager.delegate = self
  }

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

  /// เริ่ม monitor+range iBeacon ตาม [regions] — **แทนที่**ชุดที่ monitor อยู่เดิม
  /// ทั้งหมด (ไม่ merge) เช็คสิทธิ์และเพดาน 20 regions **ก่อน**สร้าง `CLBeaconRegion`
  /// แม้แต่ตัวเดียวเสมอ แบบ all-or-nothing ต่อการเรียกแต่ละครั้ง — ถ้า region ใด
  /// region หนึ่ง parse ไม่ผ่าน จะไม่มี region ไหนถูกสร้าง/แทนที่เลย (ดู
  /// ARCHITECTURE.md, ADR-4)
  func startMonitoring(regions: [[String: Any]], result: @escaping FlutterResult) {
    let authorizationStatus = CLLocationManager.authorizationStatus()
    switch authorizationStatus {
    case .denied, .restricted:
      result(
        FlutterError(
          code: "LOCATION_PERMISSION_DENIED",
          message: "Location permission denied/restricted",
          details: nil
        )
      )
      return
    case .notDetermined:
      // ไม่ block รอผลแบบ async — ขอสิทธิ์แล้วคืน error ทันที บอกให้ผู้เรียก retry
      // เองหลังผู้ใช้ตอบ system prompt
      locationManager.requestAlwaysAuthorization()
      result(
        FlutterError(
          code: "LOCATION_PERMISSION_DENIED",
          message: "Location permission not determined yet — requested, retry after user responds",
          details: nil
        )
      )
      return
    default:
      break
    }

    // เช็คเพดาน 20 regions ก่อนสร้าง CLBeaconRegion ใด ๆ ทั้งสิ้น (ตาม ADR-4:
    // regions.count + currentlyMonitoredCount > 20)
    let currentlyMonitoredCount = locationManager.monitoredRegions.count
    if regions.count + currentlyMonitoredCount > Self.maxMonitoredRegions {
      result(
        FlutterError(
          code: "TOO_MANY_REGIONS",
          message:
            "ขอ \(regions.count) region เพิ่ม บวกกับที่ monitor อยู่แล้ว \(currentlyMonitoredCount) เกินเพดาน \(Self.maxMonitoredRegions) ของ iOS",
          details: nil
        )
      )
      return
    }

    // Parse + validate ทุก region ก่อน แล้วค่อยเริ่ม stop ของเดิม/สร้างของใหม่จริง
    // (all-or-nothing — ถ้า region ใดพัง ไม่มีการเปลี่ยนแปลง state เดิมเลย)
    var parsedRegions: [(identifier: String, constraint: CLBeaconIdentityConstraint)] = []
    for rawRegion in regions {
      guard let identifier = rawRegion["identifier"] as? String,
        let uuidString = rawRegion["uuid"] as? String
      else {
        result(
          FlutterError(
            code: "INVALID_REGION_UUID",
            message: "region ขาด identifier หรือ uuid",
            details: nil
          )
        )
        return
      }
      guard let uuid = UUID(uuidString: uuidString) else {
        result(
          FlutterError(
            code: "INVALID_REGION_UUID",
            message: "uuid '\(uuidString)' ไม่ใช่ NSUUID ที่ถูกต้อง",
            details: nil
          )
        )
        return
      }

      let major = (rawRegion["major"] as? NSNumber)?.uint16Value
      let minor = (rawRegion["minor"] as? NSNumber)?.uint16Value

      let constraint: CLBeaconIdentityConstraint
      if let major = major, let minor = minor {
        constraint = CLBeaconIdentityConstraint(uuid: uuid, major: major, minor: minor)
      } else if let major = major {
        constraint = CLBeaconIdentityConstraint(uuid: uuid, major: major)
      } else {
        constraint = CLBeaconIdentityConstraint(uuid: uuid)
      }
      parsedRegions.append((identifier: identifier, constraint: constraint))
    }

    // ทุก region parse ผ่านหมดแล้ว — แทนที่ของเดิมทั้งหมด (ไม่ merge) แล้วเริ่มใหม่
    stopMonitoring(identifiers: nil)

    for parsedRegion in parsedRegions {
      let region = CLBeaconRegion(
        beaconIdentityConstraint: parsedRegion.constraint,
        identifier: parsedRegion.identifier
      )
      region.notifyEntryStateOnDisplay = false
      constraintsByIdentifier[parsedRegion.identifier] = parsedRegion.constraint
      locationManager.startMonitoring(for: region)
      locationManager.startRangingBeacons(satisfying: parsedRegion.constraint)
    }

    result(nil)
  }

  /// หยุด monitor+range ตาม [identifiers] — nil = หยุดทั้งหมดที่กำลัง monitor อยู่
  func stopMonitoring(identifiers: [String]?) {
    let targetIdentifiers = identifiers ?? Array(constraintsByIdentifier.keys)
    for identifier in targetIdentifiers {
      guard let constraint = constraintsByIdentifier[identifier] else { continue }
      let region = CLBeaconRegion(beaconIdentityConstraint: constraint, identifier: identifier)
      locationManager.stopMonitoring(for: region)
      locationManager.stopRangingBeacons(satisfying: constraint)
      constraintsByIdentifier.removeValue(forKey: identifier)
    }
  }

  // MARK: - CLLocationManagerDelegate

  func locationManager(
    _ manager: CLLocationManager,
    didRange beacons: [CLBeacon],
    satisfying beaconConstraint: CLBeaconIdentityConstraint
  ) {
    guard let eventSink = eventSink else { return }

    // CLBeaconIdentityConstraint เทียบค่าได้ (Apple ออกแบบมาให้เทียบกับ constraint
    // ที่ใช้ตอนเรียก startRangingBeacons(satisfying:) ได้โดยตรงใน callback นี้)
    guard
      let regionIdentifier = constraintsByIdentifier.first(where: { $0.value == beaconConstraint }
      )?.key
    else {
      return
    }

    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let payload: [[String: Any]] = beacons.map { beacon in
      [
        "regionIdentifier": regionIdentifier,
        "uuid": beacon.uuid.uuidString.lowercased(),
        "major": beacon.major.intValue,
        "minor": beacon.minor.intValue,
        "rssi": beacon.rssi,
        "proximity": Self.proximityString(beacon.proximity),
        "timestamp": timestamp,
      ]
    }
    eventSink(payload)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // ADR-4 ไม่ได้กำหนด error channel แยกสำหรับ ranging error รายครั้ง — ไม่มีที่ให้
    // forward ต่อไป Dart ได้ในสโคปสปรินต์นี้
  }

  private static func proximityString(_ proximity: CLProximity) -> String {
    switch proximity {
    case .immediate:
      return "immediate"
    case .near:
      return "near"
    case .far:
      return "far"
    case .unknown:
      return "unknown"
    @unknown default:
      return "unknown"
    }
  }
}
