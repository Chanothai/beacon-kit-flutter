// Test ของ usecase `ResolveBigcBeaconMetadata` (SPRINT.md A3, ARCHITECTURE.md
// ADR-5 / ADR-7) — pure Dart, ไม่พึ่ง Flutter binding เพราะ domain/usecase
// layer ต้องไม่ import อะไรจาก Flutter SDK (ถ้าเทสต์นี้ต้อง import Flutter
// binding แปลว่า flutter-dev ทำผิดกฎ dependency direction ให้รายงานกลับ)
//
// ทุกเคสโหลดจาก docs/fixtures/bigc_identity_*.json — ดูรูปแบบไฟล์และเหตุผลที่
// ต่างจาก fixture ibeacon_*/eddystone_* ใน docs/fixtures/README.md หัวข้อ
// "fixture กลุ่ม bigc_identity_*.json ต่างจาก fixture parser ยังไง"
//
// คำเตือนสำคัญ: UUID ทุกตัวในไฟล์ fixture กลุ่มนี้เป็น SYNTHETIC TEST DATA
// เท่านั้น ไม่ใช่ BigC proximity UUID จริง — ค่าจริงอยู่ที่
// docs/sources/bigc_provisioning.md เพียงที่เดียวตาม ADR-5 ห้าม copy มาที่นี่
//
// สถานะ: เขียนตาม contract ที่ flutter-dev agent (คนละ agent, ทำงานคู่ขนาน)
// จะ implement ใน lib/src/usecases/resolve_bigc_beacon_metadata.dart ยังไม่ได้
// ยืนยันว่าคอมไพล์/รันผ่านจริง เพราะ implementation ยังไม่เสร็จพร้อมกัน — เป็น
// เรื่องปกติของการทำงานคู่ขนานแบบ test-first ดู SPRINT.md ก่อนอ่านผลเทสต์นี้

import 'dart:convert';
import 'dart:io';

import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// หา docs/fixtures/ โดยไล่ขึ้นจาก cwd — เหมือน pattern ใน
/// test/parsers/fixture_loader.dart เพื่อให้รันผ่านได้ไม่ว่าจะสั่ง
/// `flutter test` จาก root ของ package นี้เอง หรือจาก root ของ repo ทั้งก้อน
Directory _findFixturesDir() {
  var dir = Directory.current;
  while (true) {
    final candidate = Directory('${dir.path}/docs/fixtures');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'ไม่พบ docs/fixtures/ เมื่อไล่ค้นขึ้นไปจาก ${Directory.current.path} — '
        'ต้องรันเทสต์นี้จากภายใน repo beacon-kit',
      );
    }
    dir = parent;
  }
}

/// โหลด fixture ทุกไฟล์ docs/fixtures/bigc_identity_*.json ที่มี
/// `"kind": "bigc_identity_mapping"`
List<Map<String, dynamic>> _loadBigcIdentityFixtures() {
  final dir = _findFixturesDir();
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.uri.pathSegments.last.startsWith('bigc_identity_') &&
                f.path.endsWith('.json'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final fixtures = <Map<String, dynamic>>[];
  for (final file in files) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) continue;
    if (decoded['kind'] != 'bigc_identity_mapping') continue;
    // นโยบายเดียวกับ fixture ADV packet: ห้ามใส่ raw_hex/source: captured ใน
    // fixture กลุ่มนี้ เพราะเป็น synthetic business-mapping data ล้วน ๆ ไม่ใช่
    // ข้อมูลจากอุปกรณ์จริง (docs/fixtures/README.md)
    if (decoded.containsKey('raw_hex') || decoded['source'] == 'captured') {
      throw StateError(
        "Fixture '${decoded['name']}' มี raw_hex หรือ source: captured แต่ "
        'fixture กลุ่ม bigc_identity_* ต้องเป็น synthetic data ล้วน ๆ ตามที่ '
        'ระบุใน docs/fixtures/README.md',
      );
    }
    final note = decoded['note'] as String?;
    if (note == null || !note.contains('SYNTHETIC TEST DATA')) {
      throw StateError(
        "Fixture '${decoded['name']}' ต้องมี field note ที่ระบุชัดว่าเป็น "
        'SYNTHETIC TEST DATA ONLY เพื่อกันไม่ให้สับสนกับ UUID จริงของ BigC',
      );
    }
    fixtures.add(decoded);
  }
  return fixtures;
}

BigcBeaconIdentity _identityFromJson(Map<String, dynamic> json) =>
    BigcBeaconIdentity(
      uuid: json['uuid'] as String,
      major: json['major'] as int,
      minor: json['minor'] as int,
    );

BigcBeaconMetadata _metadataFromJson(Map<String, dynamic> json) =>
    BigcBeaconMetadata(
      brand: json['brand'] as String,
      lot: json['lot'] as String,
      group: json['group'] as String,
      location: json['location'] as String,
    );

/// Fake in-memory repository — ไม่ใช้ mockito ตามที่ QA agent กำหนดในสปรินต์นี้
/// map คงที่ที่ตั้งไว้ล่วงหน้าจาก fixture["repository_mappings"]
class FakeBigcBeaconMetadataRepository implements BigcBeaconMetadataRepository {
  /// **บั๊กที่แก้ (28 ส.ค. 2026, sprint-lead พบตอนรัน `flutter test` รวม
  /// หลัง flutter-dev/beacon-qa ทำงานคู่ขนานเสร็จ):** เดิม constructor เก็บ
  /// `_mappings` เป็น `Map<BigcBeaconIdentity, BigcBeaconMetadata>` ตรง ๆ ซึ่ง
  /// ใช้ `BigcBeaconIdentity.==` (เทียบ `uuid` แบบ case-sensitive ตรงตัวตามที่
  /// เอกสารของ entity เองระบุว่า "ไม่บังคับ case ตอนสร้าง — normalize เป็น
  /// หน้าที่ของผู้ใช้") ทำให้ fixture
  /// `bigc_identity_success_uuid_case_insensitive` (query uuid เป็น lowercase
  /// แต่ mapping เก็บด้วย uuid ตัวพิมพ์ใหญ่/ผสม) หา match ไม่เจอ →
  /// `notFound` ทั้งที่ fixture คาดหวัง `success`
  ///
  /// **ไม่ใช่บั๊กของ `ResolveBigcBeaconMetadata` เอง** — usecase ส่ง identity
  /// ดิบเข้า `repository.resolve()` ตามที่รับมาเป๊ะ ๆ โดยตั้งใจ (ยืนยันด้วย
  /// เทสต์ "ไม่แปลง uuid case ก่อนส่งเข้า repository" ด้านล่าง) การ
  /// normalize case ของ uuid ตอนค้นหาเป็นความรับผิดชอบของ repository/backend
  /// เอง (ตาม ADR-5 mapping เก็บใน backend/database แยกต่างหาก) — database
  /// จริงแทบทุกตัวจะ normalize/ไม่สนตัวพิมพ์เล็กใหญ่ของ UUID ตอน query อยู่
  /// แล้ว จึงแก้ที่ fake repository นี้ให้ทำ lookup ด้วย key ที่ normalize
  /// uuid เป็น lowercase ก่อนเทียบ แทนที่จะพึ่ง `BigcBeaconIdentity.==` ตรง ๆ
  /// (major/minor ไม่ normalize เพิ่มเพราะเป็น `int` อยู่แล้ว ไม่มีปัญหาเรื่อง
  /// case)
  FakeBigcBeaconMetadataRepository(
    Map<BigcBeaconIdentity, BigcBeaconMetadata> mappings,
  ) : _mappings = {
        for (final entry in mappings.entries)
          _canonicalKey(entry.key): entry.value,
      };

  final Map<String, BigcBeaconMetadata> _mappings;

  /// เก็บ identity ทุกตัวที่ถูกเรียก resolve() จริง — ใช้ยืนยันว่า
  /// uuidMismatch/majorOutOfRange/minorOutOfRange ไม่แตะ repository เลย
  final List<BigcBeaconIdentity> resolvedCalls = [];

  factory FakeBigcBeaconMetadataRepository.fromFixture(
    List<dynamic> repositoryMappings,
  ) {
    final map = <BigcBeaconIdentity, BigcBeaconMetadata>{};
    for (final entry in repositoryMappings.cast<Map<String, dynamic>>()) {
      final identity = _identityFromJson(
        entry['identity'] as Map<String, dynamic>,
      );
      final metadata = _metadataFromJson(
        entry['metadata'] as Map<String, dynamic>,
      );
      map[identity] = metadata;
    }
    return FakeBigcBeaconMetadataRepository(map);
  }

  static String _canonicalKey(BigcBeaconIdentity identity) =>
      '${identity.uuid.toLowerCase()}|${identity.major}|${identity.minor}';

  @override
  Future<BigcBeaconMetadata?> resolve(BigcBeaconIdentity identity) async {
    resolvedCalls.add(identity);
    return _mappings[_canonicalKey(identity)];
  }
}

void main() {
  final fixtures = _loadBigcIdentityFixtures();

  test(
    'มี fixture ของ bigc_identity อย่างน้อย 8 เคส (ปกติ 2 + พัง/ขอบเขต 6 ตาม '
    'SPRINT.md A3)',
    () {
      expect(fixtures.length, greaterThanOrEqualTo(8));
    },
  );

  test('ทุก fixture bigc_identity ต้องประกาศชัดว่าเป็น synthetic data '
      '(ห้ามใช้ UUID จริงของ BigC ตาม ADR-5)', () {
    for (final fixture in fixtures) {
      final note = fixture['note'] as String;
      expect(
        note,
        contains('SYNTHETIC TEST DATA'),
        reason: "fixture '${fixture['name']}' ต้องเตือนชัดว่าไม่ใช่ UUID จริง",
      );
    }
  });

  for (final fixture in fixtures) {
    test('bigc_identity fixture: ${fixture['name']}', () async {
      final testProximityUuid = fixture['test_bigc_proximity_uuid'] as String;
      final repository = FakeBigcBeaconMetadataRepository.fromFixture(
        fixture['repository_mappings'] as List<dynamic>,
      );
      final usecase = ResolveBigcBeaconMetadata(
        bigcProximityUuid: testProximityUuid,
        repository: repository,
      );

      final query = _identityFromJson(fixture['query'] as Map<String, dynamic>);
      final expectJson = fixture['expect'] as Map<String, dynamic>;

      final result = await usecase(query);

      switch (expectJson['result']) {
        case 'success':
          expect(result, isA<ResolveBigcBeaconMetadataSuccess>());
          final success = result as ResolveBigcBeaconMetadataSuccess;
          final expectedMetadata = _metadataFromJson(
            expectJson['metadata'] as Map<String, dynamic>,
          );
          expect(success.metadata, equals(expectedMetadata));
        case 'failure':
          expect(result, isA<ResolveBigcBeaconMetadataFailure>());
          final failure = result as ResolveBigcBeaconMetadataFailure;
          final expectedReasonName = expectJson['reason'] as String;
          expect(
            failure.reason.name,
            equals(expectedReasonName),
            reason:
                "fixture '${fixture['name']}' คาดหวัง reason "
                '$expectedReasonName แต่ได้ ${failure.reason.name}',
          );

          // uuidMismatch/majorOutOfRange/minorOutOfRange ต้องไม่แตะ
          // repository เลย ตาม contract ที่ QA agent ได้รับ (ตรวจ uuid ก่อน
          // แล้วช่วง major/minor ก่อนที่จะ query repository เสมอ)
          if (expectedReasonName != 'notFound') {
            expect(
              repository.resolvedCalls,
              isEmpty,
              reason:
                  "fixture '${fixture['name']}' คาดหวัง reason "
                  '$expectedReasonName ซึ่งควรถูก reject ก่อน query repository '
                  'แต่ repository.resolve() ถูกเรียก',
            );
          }
        default:
          fail(
            "fixture '${fixture['name']}' มี expect.result ที่ไม่รู้จัก: "
            "${expectJson['result']}",
          );
      }
    });
  }

  group('ResolveBigcBeaconMetadata — เคสเพิ่มเติมที่เขียนตรงในไฟล์ (ไม่พึ่ง fixture)', () {
    // UUID จำลองสำหรับเทสต์เท่านั้น ไม่ใช่ค่าจริงของ BigC (ค่าจริงอยู่ที่
    // docs/sources/bigc_provisioning.md ตาม ADR-5)
    const testProximityUuid = 'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE';

    test('เรียก repository.resolve() ด้วย identity เดิมที่รับเข้ามา (ไม่แปลง uuid case ก่อนส่งเข้า repository)', () async {
      final repository = FakeBigcBeaconMetadataRepository({});
      final usecase = ResolveBigcBeaconMetadata(
        bigcProximityUuid: testProximityUuid,
        repository: repository,
      );
      const identity = BigcBeaconIdentity(
        uuid: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        major: 5,
        minor: 5,
      );

      final result = await usecase(identity);

      expect(result, isA<ResolveBigcBeaconMetadataFailure>());
      expect(
        (result as ResolveBigcBeaconMetadataFailure).reason,
        ResolveBigcBeaconMetadataFailureReason.notFound,
      );
      expect(repository.resolvedCalls, hasLength(1));
      expect(repository.resolvedCalls.single, equals(identity));
    });

    test('major = 0 และ minor = 0 ถือว่าอยู่ในช่วง uint16 ที่ยอมรับ (ขอบล่างของช่วง)', () async {
      const identity = BigcBeaconIdentity(
        uuid: testProximityUuid,
        major: 0,
        minor: 0,
      );
      final repository = FakeBigcBeaconMetadataRepository({
        identity: const BigcBeaconMetadata(
          brand: 'B',
          lot: 'L',
          group: 'G',
          location: 'Loc',
        ),
      });
      final usecase = ResolveBigcBeaconMetadata(
        bigcProximityUuid: testProximityUuid,
        repository: repository,
      );

      final result = await usecase(identity);

      expect(result, isA<ResolveBigcBeaconMetadataSuccess>());
    });

    test('major = 65535 และ minor = 65535 ถือว่าอยู่ในช่วง uint16 ที่ยอมรับ (ขอบบนของช่วง)', () async {
      const identity = BigcBeaconIdentity(
        uuid: testProximityUuid,
        major: 65535,
        minor: 65535,
      );
      final repository = FakeBigcBeaconMetadataRepository({
        identity: const BigcBeaconMetadata(
          brand: 'B',
          lot: 'L',
          group: 'G',
          location: 'Loc',
        ),
      });
      final usecase = ResolveBigcBeaconMetadata(
        bigcProximityUuid: testProximityUuid,
        repository: repository,
      );

      final result = await usecase(identity);

      expect(result, isA<ResolveBigcBeaconMetadataSuccess>());
    });
  });
}
