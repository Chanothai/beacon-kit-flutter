# ออกแบบ PR A — exit-clear ฝั่ง Android (ProximityGateStore)

- branch: `feat/android-proximity-exit-clear`
- base: `36e0256` (main ที่รวม PR #32 — docs/readme-rewrite — แล้ว)
- สถานะ: **ออกแบบแล้ว ยังไม่ implement** (ห้ามอ่านเอกสารนี้ว่าเป็นหลักฐานว่าโค้ดทำงานได้จริง
  — ไม่มีรอบเดินอุปกรณ์จริงประกอบเอกสารฉบับนี้เลย)
- ขอบเขต: **เอกสารเท่านั้น** ไม่มีการแก้โค้ด/commit ใด ๆ ระหว่างเขียนเอกสารนี้
- วันที่เขียน: 14 ก.ย. 2026 (beacon-architect)

ทุกจุดที่เขียนว่า `path:บรรทัด` คือพิกัดที่เปิดไฟล์จริงยืนยันแล้ว ณ `36e0256` ในรอบเขียน
เอกสารนี้เท่านั้น (ไม่ได้คัดต่อจาก ADR-20 §7.1 โดยไม่เปิดไฟล์ซ้ำ) — ถ้า flutter-dev พบว่า
เลขบรรทัดขยับ (มี commit ใหม่ก่อนเริ่ม implement จริง) ให้ grep ชื่อ symbol ซ้ำ ไม่ใช่เชื่อ
เลขบรรทัดเป๊ะ ๆ

---

## 0. ส่วนต่างจากที่ ADR สมมติไว้ (อ่านก่อนเขียนโค้ดจริง)

**เลข `path:บรรทัด` ที่ ADR-20 §7.1 (ARCHITECTURE.md:4126-4160) อ้างไว้ทั้งหมด — ตรวจซ้ำแล้ว
ตรงเป๊ะทุกจุด ไม่มีเลขบรรทัดคลาด:**
- `ProximityGateStore.clear()` อยู่จริงที่ `ProximityGateStore.kt:179`
- `MainActivity.logMonitorLifecycle()` เรียก `ProximityGateStore(context).clear()` จริงที่
  `MainActivity.kt:168` — คอมเมนต์ "ไม่ใช่ตำแหน่งที่ถูกต้องถาวร" อยู่จริงในช่วง
  `MainActivity.kt:153-164`
- `BackgroundRegionStore.clearRegionStates()` ถูกเรียกจริงที่ `BackgroundRegionMonitor.kt:126`
  (ใน `start()`) และ `:157` (ใน `restoreAfterBoot()`)
- `proximityKeyPartsOrNull()` — **ชื่อฟังก์ชันตรงเป๊ะ** อยู่จริงที่ `BeaconScanReceiver.kt:345`
  คืน `ProximityKeyParts(regionIdentifier, uuid, major, minor)` (data class ที่
  `BeaconScanReceiver.kt:306-311`) — ไม่มีส่วนต่างจากที่ ADR อ้าง
- `ProximityGate.kt:199` คือบรรทัดจริงของ `staleAfterMillis: Long = 60_000L` และ
  `proximity_gate.dart:268` คือบรรทัดจริงของ `staleAfter = const Duration(seconds: 10)`
  (ตัวเลขตาราง ADR-20 §7.1 ตรงกับโค้ดปัจจุบัน)
- ฝั่ง iOS: `IBeaconRangingManager.swift:735` คือจุดเรียก `runProximityRegionExit()` จริง
  (`try runProximityRegionExit(regionIdentifier: region.identifier)`) และนิยามอยู่จริงที่
  `:1155`

**ส่วนที่ ADR-20 §7.1 ไม่ได้พูดถึงแต่สำคัญมากต่อการออกแบบ PR A — พบจากการเปิด
`IBeaconRangingManager.swift:1142-1182` (นิยามเต็มของ `runProximityRegionExit`) จริง:**

`runProximityRegionExit` ของ iOS ไม่ได้แค่ "ล้าง state" เฉย ๆ — มันยัง **ประกาศ
transition ด้วย reason ใหม่ `.regionExit`** ผ่าน `gate.clearStates(matchingPrefix:
emitting: .regionExit)` (`IBeaconRangingManager.swift:1168`) แล้วยิง event ออกไปทาง
`BackgroundProximityMonitor.emit()` เหมือน transition ปกติ (`:1175-1181`) — แต่คอมเมนต์
ในไฟล์เดียวกัน (`IBeaconRangingManager.swift:1149-1152`) เขียนไว้ตรง ๆ เองว่า:

> ⚠️ `regionExit` **ไม่ใช่ parity กับ Android** — ฝั่งนั้นไม่มี reason นี้จริง ๆ
> (ล้าง store ตอน `monitorStop` ของ example app ไม่ใช่ตอน region exit) และ
> `proximity_gate.dart` ก็ไม่มี · เป็นการเบี่ยงจาก reference **โดยตั้งใจ** และเป็น
> **หนี้ที่ต้องยกขึ้นไป Dart แล้วไหลลงทั้งสอง port** ในรอบถัดไป (ADR-21 หัวข้อ 8)

ยืนยันซ้ำอีกทางว่าฝั่ง Kotlin ไม่มี reason นี้จริง: `ProximityTransitionReason`
(`ProximityGate.kt:45-58`) มีแค่ `CLOSER` / `FARTHER` / `STALE` — ไม่มี `REGION_EXIT`
และไม่มีเมธอดรูปแบบ `clearStates(matchingPrefix:emitting:)` ใน `ProximityGate.kt` เลย
(grep `clearStates\|regionExit` ในไฟล์นี้ไม่พบ)

**สรุปผลต่อ PR A:** ถ้าอ่าน ADR-20 §7.1 ตรง ๆ ว่า "ให้เทียบเท่า `runProximityRegionExit()`
ของ iOS" แบบผิวเผิน อาจตีความเกินไปว่าต้องเพิ่ม `ProximityTransitionReason.REGION_EXIT`
และยิง `ProximityChangedEvent` ใหม่บน Android ด้วย — **ไม่ใช่ขอบเขตของ PR A** ตาม
คอมเมนต์ของ iOS เองที่บอกว่าเรื่องนี้เป็นหนี้ข้าม-แพลตฟอร์มที่ต้องออกแบบระดับ Dart ก่อน
(ADR-21 §8) ไม่ใช่สิ่งที่ทำเงียบ ๆ ฝั่งเดียวใน PR A นี้ — **PR A ต้องเป็นการล้าง state
แบบเงียบเท่านั้น (silent clear) เหมือนที่ `clear()` วันนี้ทำ ไม่เพิ่ม reason ใหม่ ไม่ยิง
`ProximityChangedEvent` ใหม่** ดู §1/§4 ด้านล่างสำหรับผลต่อการออกแบบจริง

---

## 1. รูปแบบการลบ — API ใหม่ใน `ProximityGateStore`

### 1.1 ย้าย `clear()` เข้า `stop()` — ไม่ต้องมี API ใหม่

`clear()` (`ProximityGateStore.kt:179-181`) ล้างทั้งไฟล์ prefs ในคำสั่งเดียว
(`prefs.edit().clear().commit()`) — ใช้ signature เดิมได้ตรง ๆ ไม่ต้องเพิ่มอะไร เพียง
ย้ายจุดเรียกจาก `MainActivity.logMonitorLifecycle()` (`MainActivity.kt:167-169`) เข้าไป
ใน `BackgroundRegionMonitor.stop()` (`BackgroundRegionMonitor.kt:132-142`) ให้เรียกคู่กับ
`store.clearAll()` ของ `BackgroundRegionStore` (`BackgroundRegionMonitor.kt:141` →
`BackgroundRegionStore.clearAll()` ที่ `BackgroundRegionStore.kt:343-345` ใช้ pattern
เดียวกันเป๊ะ: `prefs.edit().clear().commit()`) — สมมาตรกันสนิท

**ผลข้างเคียงที่ต้องทำคู่กัน (ไม่ใช่แค่ย้ายบรรทัดเดียว):** `MainActivity.kt:165-169`
ต้อง**ลบ**การเรียก `ProximityGateStore(context).clear()` ออกทั้งบล็อก (ไม่ใช่ปล่อยให้เรียก
ซ้ำสองที่) และคอมเมนต์ทั้งก้อนที่ `MainActivity.kt:144-164` (อธิบายว่าทำไม `monitorStop`
ต้องล้าง store + ระบุว่าเป็นหนี้ที่ต้องย้าย) ต้องแก้ใหม่ให้บอกว่า **ย้ายเข้า SDK แล้ว**
ไม่ใช่ปล่อยคอมเมนต์เดิมทิ้งไว้ให้อ่านแล้วเข้าใจผิดว่ายังเป็นหน้าที่ของ example app —
รวมถึง annotation `proximityStoreCleared=true` ที่ต่อท้าย `rawSignals` ของบรรทัด
`monitorStop` (`MainActivity.kt:183`) ต้อง**ลบทิ้ง** เพราะหลัง PR A แล้ว example app
ไม่ได้เป็นคนล้างเองอีกต่อไป การยังคง annotate `=true` จะเป็นการโกหกว่า "ฉันล้างแล้ว"
ทั้งที่ตัวมันไม่ได้ทำอะไรเลย — ดู §4 สำหรับที่ที่หลักฐานควรย้ายไปอยู่แทน (logcat ของ SDK
เอง ไม่ใช่ evidence-log column ของ example app)

`stop()` ยังคง signature เดิม (`fun stop(context: Context): Unit`) ไม่ต้องเปลี่ยน
return type — ไม่มีผู้เรียกภายนอกคนไหนต้องการนับจำนวนที่ลบจาก `stop()` (มันคือ "ล้างหมด"
ไม่ใช่ "ล้างบางส่วน" การนับจึงไม่ได้ให้ข้อมูลอะไรเพิ่มเทียบกับ `clearRegion()` ด้านล่าง)
— แต่เพื่อให้มี log บรรทัดพิสูจน์ได้ (ดู §4) ให้เรียก `store.load()` **ก่อน** `store.clear()`
หนึ่งครั้งเพื่อเอาจำนวน key ไปล็อก (ต้นทุนอ่านครั้งเดียวตอน stop เป็นการดำเนินการที่ไม่ถี่
ยอมรับได้ ต่างจากเส้นทาง `onExitAlarm`/`reconcile` ที่ถี่กว่ามาก)

### 1.2 API ใหม่ — `ProximityGateStore.clearRegion(regionIdentifier: String): Int`

```kotlin
/**
 * ล้างเฉพาะ key ของ region ที่ระบุ — ใช้ตอนประกาศ exit ของ region เดียว (ต่างจาก [clear]
 * ที่ล้างทั้งหมดตอนหยุดเฝ้าทุก region)
 *
 * เทียบ regionIdentifier ที่ถอดได้จาก [proximityKeyPartsOrNull] แบบ **exact เท่านั้น**
 * (`parts.regionIdentifier == regionIdentifier`) ไม่ใช่ prefix match ของสตริงดิบ — ดู
 * เหตุผลเต็มในหัวข้อ 2 ของเอกสารออกแบบ PR A (`docs/briefs/2026-09-14_pr-a-exit-clear-design.md`)
 *
 * อ่าน-กรอง-เขียนกลับ**รอบเดียว**: [load] ครั้งเดียว, [save] ไม่เกินหนึ่งครั้ง (เขียนกลับ
 * เฉพาะเมื่อมีอะไรถูกกรองออกจริง — ถ้าไม่มี key ของ region นี้เลย ไม่ commit() เปล่า)
 *
 * คืนจำนวน key ที่ถูกลบ — ผู้เรียกเอาไปต่อท้าย log (ดู `BackgroundRegionMonitor`)
 */
fun clearRegion(regionIdentifier: String): Int {
    val states = load()
    val remaining = states.filterKeys { key ->
        proximityKeyPartsOrNull(key)?.regionIdentifier != regionIdentifier
    }
    val removedCount = states.size - remaining.size
    if (removedCount > 0) {
        save(remaining)
    }
    return removedCount
}
```

**อ่าน-กรอง-เขียนกลับรอบเดียวหรือหลายรอบ:** รอบเดียว — เรียก `load()` หนึ่งครั้ง, `save()`
อย่างมากหนึ่งครั้ง เหมือน pattern ที่ `BeaconScanReceiver.processProximity()` ทำอยู่แล้ว
(`load()` ที่ `BeaconScanReceiver.kt:117`, `save()` ที่ `:184` — คนละ call แต่อยู่ใน batch
เดียวกัน ไม่มี lock คั่นระหว่างกลาง)

**thread-safe/atomic แค่ไหนเทียบกับ `clear()` วันนี้:** **น้อยกว่า** `clear()` เดิม —
`clear()` เป็นคำสั่งเดียว (`edit().clear().commit()`) จึง atomic ในตัวเองระดับ
`SharedPreferences.Editor` (ไม่มีช่วงอ่านคั่นกลาง) ส่วน `clearRegion()` มีช่วง**อ่าน
(`load()`) แล้วค่อยเขียน (`save()`)** เป็นสอง `SharedPreferences` operation แยกกัน — เปิด
หน้าต่าง TOCTOU แคบ ๆ ถ้ามีผู้เขียนคนอื่นเข้ามาคั่นกลางระหว่างนั้น **นี่ไม่ใช่ความเสี่ยงใหม่
ที่ไฟล์นี้ไม่เคยมี** — `BeaconScanReceiver.processProximity()` เองก็ทำ `load()` แล้วค่อย
`save()` แบบเดียวกันโดยไม่มี lock คั่นอยู่แล้วในโค้ดวันนี้ (`BeaconScanReceiver.kt:117,184`)
`clearRegion()` จึงไม่ได้เพิ่ม "ชนิดความเสี่ยง" ใหม่ให้ `ProximityGateStore` เพียงแต่เพิ่ม
"จุดที่เสี่ยง" อีกจุดหนึ่ง (call site ที่สองที่ทำ load-then-save โดยไม่ล็อก) — ต้องบันทึกไว้
ตรง ๆ ว่าเป็น trade-off ที่ยอมรับ ไม่ใช่ช่องโหว่ที่มองข้าม: ถ้า `BeaconScanReceiver.onReceive()`
(ทำ load/save ของตัวเอง) กับ `BackgroundRegionMonitor.onExitAlarm()`/`reconcile()` (ทำ
`clearRegion()` ของมันเอง) ถูกปลุกพร้อมกันจริง ๆ จากคนละ broadcast (`BeaconScanReceiver`
กับ `RegionExitAlarmReceiver` เป็นคนละ receiver คนละ `onReceive()`) ผลลัพธ์ที่แย่ที่สุดคือ
การเขียนทับกันแล้ว key บางตัวที่ควรถูกลบไม่ถูกลบในรอบนั้น (หรือ state ที่เพิ่งนับใหม่จาก
sighting ถูกลบไปด้วยโดยไม่ตั้งใจ) — **ผลเสียหนักสุดคือ dwell เริ่มนับใหม่/key ค้างเกิน
ที่ควร ไม่ใช่ crash หรือข้อมูลชั้น 1 เสียหาย** เพราะ `ProximityGateStore` เป็นไฟล์ prefs
คนละไฟล์จาก `BackgroundRegionStore` เสมอ (`PREFS_NAME` ต่างกัน: `"beacon_kit_android.proximity"`
ที่ `ProximityGateStore.kt:184` vs `"beacon_kit_android.background"` ที่
`BackgroundRegionStore.kt:35`) — ยอมรับความเสี่ยงนี้ได้ในระดับเดียวกับที่ไฟล์นี้ยอมรับ
ความเสี่ยงแบบเดียวกันอยู่แล้วในเส้นทาง `processProximity()` (เอกสารของคลาสเองที่
`ProximityGateStore.kt:24-32` ก็ยอมรับไว้แล้วว่าชั้น 2 เป็น POC ที่ยอมข้อมูลเสียหายชั่วคราว
ได้ ไม่ใช่ source of truth ระดับเดียวกับชั้น 1) — **ไม่เพิ่ม `synchronized` ใหม่ใน PR A**
เพราะ `reconcile()` มี `synchronized(this)` ของตัวเองอยู่แล้วที่ระดับ `BackgroundRegionMonitor`
object (`BackgroundRegionMonitor.kt:602`) ซึ่งครอบเฉพาะเส้นทางของตัวมันเอง ไม่ครอบ
`onExitAlarm()` (คนละ synchronized block กัน) — เขียนไว้ตรง ๆ เป็นข้อจำกัดที่รู้ตัว ไม่ใช่
บั๊กที่ซ่อนไว้

**คืนค่าจำนวนที่ลบไหม:** คืน — `Int` (จำนวน key ที่ถูกกรองออก) ใช้สำหรับ log บรรทัดพิสูจน์
ตาม §4 และใช้เป็นเงื่อนไข "เขียนกลับเฉพาะเมื่อมีอะไรเปลี่ยนจริง" ในตัวมันเอง (ลด
`commit()` เปล่าที่ไม่จำเป็น)

**ไม่ต้องแก้ `ProximityGate.kt` (ตัว in-memory gate) เลยใน PR A** — `BackgroundRegionMonitor`
ไม่เคยถือ instance ของ `ProximityGate` อยู่แล้ว (`ProximityGate` ถูกสร้างใหม่ทุกครั้งเฉพาะ
ใน `BeaconScanReceiver.processProximity()` ที่ `BeaconScanReceiver.kt:116` แล้วทิ้งเมื่อจบ
เมธอด) การล้าง state ของ region ที่ออกจึงเป็นการล้างที่ระดับ**ดิสก์ (`ProximityGateStore`)
เท่านั้น** ไม่มี object ของ gate ที่ยังมีชีวิตอยู่ให้ต้องเคลียร์ในหน่วยความจำแยกต่างหาก

---

## 2. การจับคู่ prefix ที่ต้องรวมตัวคั่น — ทำไมห้าม `key.startsWith(regionIdentifier)` ดิบ ๆ

ยืนยันแล้ว (§0 ด้านบน) ว่า `proximityKeyPartsOrNull()` (`BeaconScanReceiver.kt:345-353`)
คือฟังก์ชันที่ ADR-20 §7.1 อ้างถึงจริง ชื่อตรง ตำแหน่งตรง คืน `ProximityKeyParts`
(`regionIdentifier`, `uuid`, `major`, `minor` — `BeaconScanReceiver.kt:306-311`)

**เหตุผลที่ `key.startsWith(regionIdentifier)` แบบดิบ ๆ (ไม่ผ่าน `proximityKeyPartsOrNull`)
อันตราย:** สมมติ region สองอันชื่อ `"bigc"` และ `"bigc-test"` ถูกเฝ้าพร้อมกัน (ค่าตัวอย่างนี้
ใช้ชื่อจริงจาก pattern ที่มีอยู่แล้วในเทสต์ปัจจุบัน — `ProximityGateStoreTest.kt:486`
ใช้ `"bigc-test|..."` เป็น fixture) คีย์ของสองบีคอนจะเป็น

```
bigc|e2c56db5-...|9902|2
bigc-test|e2c56db5-...|9902|2
```

ถ้าเรียก `key.startsWith("bigc")` (สตริง `"bigc"` ดิบ ๆ ไม่เติมตัวคั่น) ตอนล้าง region
`"bigc"` — คีย์ที่สอง (`"bigc-test|..."`) **ก็ขึ้นต้นด้วย `"bigc"` เหมือนกัน** จะถูกลบไปด้วย
ทั้งที่เป็นคนละ region กันโดยสิ้นเชิง — ต้นเหตุของบั๊กคือ `"|"` เป็นตัวคั่นที่ไม่ได้ถูกนับ
เป็นส่วนหนึ่งของการเทียบ prefix แบบสตริงดิบ

**ถ้าลองแก้แบบเติมตัวคั่นเข้าไปเอง (`key.startsWith("$regionIdentifier|")`)** ก็ยังไม่ใช่
คำตอบที่ถูกที่สุด: ADR-20 §3 เอง (`BeaconScanReceiver.kt:317-333`, คอมเมนต์ของ
`proximityKeyPartsOrNull`) บันทึกบั๊กที่เคยเกิดจริงไว้แล้วว่า `regionIdentifier` **เอง
มี `|` ปนอยู่ในตัวมันได้** (`BeaconRegionSpec.kt:15` ไม่กัน `|` เลย ตามที่คอมเมนต์อ้าง) —
เช่น region ชื่อ `"a|b"` (มีเทสต์จริงคลุมเคสนี้แล้วที่ `ProximityGateStoreTest.kt:440-475`
"regionIdentifier มี pipe ปนอยู่ต้องไม่ถูก... ตัดทิ้ง") ถ้าใช้การต่อสตริง `"$regionIdentifier|"`
เอง ต้องมั่นใจว่าตัดขอบเขตถูกจุดเดียวกับที่ `proximityKeyPartsOrNull` ตัดจากท้าย (ไม่ใช่
จากหัว) เป๊ะ ซึ่งเป็นการเขียนตรรกะถอด key **ซ้ำเป็นตัวที่สอง** — ขัดกับกติกาที่คอมเมนต์
ของฟังก์ชันเขียนไว้ตรง ๆ ว่า "แหล่งเดียวของตรรกะถอด key ในโมดูลนี้"
(`BeaconScanReceiver.kt:330-333`) และเป็นรูปแบบบั๊กเดียวกับที่เกิดไปแล้วครั้งหนึ่งตอนที่
`ProximityGateStore.isValidKeyShape()` เคยเขียน `key.split('|').size == 4` ของตัวเองก่อน
ถูกแก้ให้เรียก `proximityKeyPartsOrNull()` แทน (`ProximityGateStore.kt:247-259`
คอมเมนต์อ้างรอบแก้ 11 ก.ย. 2026 ตรง ๆ)

**คำตอบที่ถูกต้อง:** เรียก `proximityKeyPartsOrNull(key)` แล้วเทียบ `parts.regionIdentifier
== targetRegionIdentifier` แบบ **exact equality** (ไม่ใช่ prefix ใด ๆ อีกต่อไป) — ฟังก์ชันนี้
ถอด `regionIdentifier` กลับมาให้ครบถูกต้องอยู่แล้วไม่ว่าจะมี `|` ปนกี่ตัวก็ตาม (ตัดจากท้าย
ด้วยเงื่อนไข `parts.size >= 4` แล้วต่อส่วนที่เหลือกลับด้วย `|` — `BeaconScanReceiver.kt:346-352`)
วิธีนี้แก้ปัญหาทั้งสองเคส (`bigc` vs `bigc-test`, และ `regionIdentifier` ที่มี `|`) ในจุด
เดียวโดยไม่ต้องเขียนตรรกะแยกขอบเขต string เอง — ตรงกับสิ่งที่ `ProximityGateStore.
isValidKeyShape()` ทำอยู่แล้วสำหรับปัญหาคนละแบบ (ดู `ProximityGateStore.kt:259`) เป็น
รูปแบบเดียวกัน

---

## 3. การครอบ try/catch ไม่ให้ชั้น 1 พัง

### 3.1 หลักการที่ต้องยึด — อ้างจากโค้ดจริง ไม่ใช่แค่ ADR

ยืนยันหลักการจาก ARCHITECTURE.md:3777 (`### 1. สองชั้นตาม Apple — แต่ชั้นที่สองบน Android
ได้มาฟรี`, ADR-20 หัวข้อ 1): "ชั้น 2 ... ต้องถูกครอบด้วย `try/catch` ทั้งก้อน" และตัวอย่างจริง
ของหลักการนี้ทำงานอยู่แล้วที่ `BeaconScanReceiver.kt:82-86`:

```kotlin
try {
    processProximity(context, regionIdentifier, results)
} catch (throwable: Throwable) {
    Log.w(TAG, "ชั้น proximity ล้มเหลว — enter/exit ของชั้น 1 ไม่ได้รับผลกระทบ", throwable)
}
```

**จุดสำคัญที่ต้องพบเอง ไม่ใช่แค่คัดลอกแพทเทิร์นนี้ไปวาง:** try/catch ก้อนนี้อยู่ใน
`BeaconScanReceiver.onReceive()` และครอบ**เฉพาะ** `processProximity()` (บรรทัด 83) —
**ไม่ครอบ** `BackgroundRegionMonitor.reconcile()` (เรียกที่ `BeaconScanReceiver.kt:55`)
และไม่ครอบ `onSighting()` (เรียกที่ `:60`) เพราะสองอันนั้นเป็นชั้น 1 ที่ต้องพังได้ถ้าพัง
จริง (ห้ามกลืน error ของชั้น 1)

**แต่ path ที่ PR A ต้องแก้ไม่ใช่ path เดียวกับ `processProximity()` เลย** — `onExitAlarm()`
และ `reconcile()` ถูกเรียกจาก **`RegionExitAlarmReceiver.onReceive()`**
(`RegionExitAlarmReceiver.kt:33-34`):

```kotlin
BackgroundRegionMonitor.reconcile(context)
BackgroundRegionMonitor.onExitAlarm(context, regionIdentifier)
```

**ไฟล์นี้ไม่มี try/catch ใด ๆ เลยทั้งไฟล์** (อ่านทั้งไฟล์ 36 บรรทัดแล้วยืนยัน) —
ถ้าเพิ่มการเรียก `ProximityGateStore.clearRegion()` เข้าไปใน `onExitAlarm()`/`reconcile()`
โดยไม่มี try/catch ของตัวเอง แล้ว `clearRegion()` โยน exception ขึ้นมา (แม้จะไม่น่าเกิดจริง
เพราะ `load()`/`save()` ภายในห่อด้วย `runCatching` ของตัวเองอยู่แล้ว —
`ProximityGateStore.kt:83-141,166-176` — แต่ตัว `ProximityGateStore(context)` เองยัง
**ไม่ได้ห่อ** ตอนสร้าง instance: `context.applicationContext.getSharedPreferences(...)`
ที่ `ProximityGateStore.kt:48-49` เป็น property initializer ที่ยังไม่มี `runCatching`
คลุม) — exception นั้นจะลอยขึ้นไปทำให้ **`RegionExitAlarmReceiver.onReceive()` ทั้งเมธอด
crash** ซึ่งหมายความว่าสาขาที่ยังไม่ทันเรียก `store.markOutside*()`/observer ของชั้น 1
เลยก็ถูกตัดตอนไปด้วย — **นี่คืออาการที่ ADR-20 หัวข้อ 1 ห้ามไว้ตรง ๆ (ชั้น 2 ทำให้ชั้น 1
พัง) แม้จะเป็นคนละไฟล์จากตัวอย่างเดิมที่ ADR อ้างถึงก็ตาม**

### 3.2 ตำแหน่งครอบที่เสนอ — ครอบที่ call site เดียว ไม่ใช่ในตัว store

เสนอ: ห่อการเรียก `ProximityGateStore(context).clearRegion(regionIdentifier)` ด้วย
`runCatching` **ที่ call site ใน `BackgroundRegionMonitor.kt`** (ไม่ใช่แก้ให้
`ProximityGateStore.clearRegion()` เองกลืน exception ภายใน) ด้วยเหตุผล 2 ข้อ:

1. **รักษารูปแบบเดิมของไฟล์นี้** — `ProximityGateStore.load()`/`save()` ห่อ exception
   ของ**การอ่าน/เขียนดิสก์**ไว้แล้วภายในตัวเอง (เพราะเป็นความรับผิดชอบของมันเองที่ต้อง
   คืน `emptyMap()`/ตั้ง `lastError` แทนโยน) — แต่ **การสร้าง instance** (`ProximityGateStore(context)`)
   ไม่ใช่ความรับผิดชอบของคลาสนี้ที่จะรู้ว่า "เรียกจากชั้นไหน จะกลืนได้แค่ไหน" การตัดสินใจ
   ว่าจะกลืน exception ของทั้งก้อนหรือไม่ควรอยู่ที่**ผู้เรียก**ซึ่งรู้บริบทว่าตัวเองเป็น
   ชั้น 1 หรือชั้น 2 — ตรงกับที่ `BeaconScanReceiver.onReceive()` ทำอยู่แล้ว (ครอบที่จุด
   เรียก ไม่ใช่ใน `ProximityGate`/`ProximityGateStore` เอง)
2. **`BackgroundRegionMonitor.kt` ยังไม่เคยมี `android.util.Log`/`TAG` เลยทั้งไฟล์**
   (grep `android.util.Log\|Log\.\|TAG` ในไฟล์นี้ไม่พบเลยสักบรรทัด) — ต้องเพิ่มใหม่เป็น
   ครั้งแรกของไฟล์นี้เพื่อให้มี log บรรทัดพิสูจน์ (ดู §4) — การเพิ่ม `Log.w`/`TAG` ที่จุดนี้
   จุดเดียว (ไม่ใช่กระจายเข้าไปใน `ProximityGateStore`) ทำให้ไฟล์นี้ยังคงเป็น
   `Context`/framework-free ตามที่ `ProximityGateStore` เขียนไว้ (property `lastError`
   เป็น `String?` ธรรมดา ไม่เรียก `Log` เอง เหตุผลที่ `ProximityGateStore.kt:42-44`
   อธิบายไว้ตรง ๆ ว่าเพื่อให้เรียกได้จาก JVM unit test ที่ `Log` เป็นสตับ — คงหลักการเดิม
   ไว้ ไม่ทำลายมันโดยเพิ่ม `Log` เข้าไปใน `ProximityGateStore`)

**⚠️ ข้อควรระวังเรื่องความยาว TAG:** ถ้าตั้ง `TAG = "BackgroundRegionMonitor"` (23
ตัวอักษรเป๊ะ) — คอมเมนต์ที่มีอยู่แล้วของไฟล์ `BeaconScanReceiver.kt:259` เขียนกฎไว้ตรง ๆ ว่า
"tag ... สั้นกว่า 23 ตัวอักษรตามข้อจำกัดของ `Log`" (คือ **น้อยกว่า** 23 ไม่ใช่ **เท่ากับ**
23) — ชื่อคลาสเต็ม `BackgroundRegionMonitor` ยาวพอดี 23 ตัว **ชนขอบตามตัวอักษรของกฎที่
ไฟล์อื่นในโมดูลเดียวกันเขียนไว้เอง** — ต้อง implement ด้วยชื่อย่อ (เช่น
`"BgRegionMonitor"` หรือคล้ายกัน) ให้สั้นกว่า 23 จริง ไม่ใช่ใช้ชื่อคลาสเต็มตรง ๆ — จุดนี้
เป็นรายละเอียดเชิงเทคนิคที่ต้องยืนยันตอน implement จริง ไม่ใช่เดางวดนี้

**ตำแหน่งวางภายใน `emitExitAndMarkOutside()`:** `emitExitAndMarkOutside()`
(`BackgroundRegionMonitor.kt:750-765`) คือ**จุดคอขวดเดียว**ที่ทั้ง `onExitAlarm()`
(สองจุดเรียก: `:494` สาขา `staleBootMismatch`, `:531` สาขา `alarm`) และ `reconcile()`
(หนึ่งจุดเรียกที่ `:644`, ครอบทั้งสองสาขา `staleBootMismatch`/`staleReconcile` ของมันเอง)
ใช้ร่วมกัน — **เสนอวางเรียก `clearRegion()` ที่ท้ายฟังก์ชันนี้ หลังจากขั้นตอนของชั้น 1
(เรียก `observer`/`sink` แล้วพลิกสถานะ `markOutside*`) เสร็จสมบูรณ์แล้วเท่านั้น** ไม่ใช่
ก่อนหน้านั้น — เหตุผล: ถ้า `clearRegion()` throw ขึ้นมาระหว่างทาง อยากให้ throw **หลังจาก**
ที่ชั้น 1 ได้บันทึกหลักฐาน + พลิกสถานะไปแล้วเรียบร้อย ไม่ใช่ throw คั่นกลางจนขั้นตอนของ
ชั้น 1 บางส่วนไม่ทันเกิด — ตรงกับหลักการ "หลักฐานลงดิสก์ก่อนเปลี่ยนสถานะ" ที่คอมเมนต์ของ
ฟังก์ชันเดียวกันอธิบายไว้แล้วสำหรับลำดับภายในของมันเอง (`BackgroundRegionMonitor.kt:729-748`)
— PR A สืบทอดหลักการเดียวกัน เพิ่มแค่ขั้นที่ 3 ต่อท้ายขั้นเดิมสองขั้น

**เพิ่มพารามิเตอร์ `source: String` ให้ `emitExitAndMarkOutside()`** (private function
เปลี่ยน signature ได้อย่างปลอดภัยเพราะเรียกแค่ภายในไฟล์เดียวกัน) ค่าที่ส่งมาจาก 3 จุดเรียก
คือ `"onExitAlarm"` (2 จุด) และ `"reconcile"` (1 จุด) — เหตุผลอยู่ที่ §4 (log ต้องแยกที่มา
ได้ และ `exitReason` เดิมอย่างเดียวแยกไม่ได้ครบทุกกรณีเพราะ `staleBootMismatch` มาได้จาก
ทั้งสองทาง)

### 3.3 `stop()` — try/catch แยกจากกันโดยสิ้นเชิง

`stop()` ไม่ผ่าน `emitExitAndMarkOutside()` เลย (เป็นคนละ code path) ต้องห่อ
`ProximityGateStore(context).clear()` (และ `load()` ที่เรียกก่อนหน้าเพื่อนับจำนวนตาม §1.1)
ด้วย `runCatching` แยกต่างหากของตัวเองที่ใน `stop()` โดยตรง ด้วยเหตุผลเดียวกับ §3.2:
ผู้เรียก `stop()` (Dart ผ่าน platform channel) ต้องไม่ได้รับ exception ที่มาจากชั้น 2
เมื่อสั่งหยุดเฝ้า — ชั้น 1 ของ `stop()` (`stopScansOnly`, `cancelExitAlarm`,
`store.clearAll()`) ต้องเสร็จสมบูรณ์เสมอไม่ว่าชั้น 2 จะพังหรือไม่

---

## 4. หลักฐานที่ต้องเห็นใน log

### 4.1 รูปแบบที่มีอยู่แล้วในโมดูลนี้ (ต้องล้อ ไม่ใช่คิดใหม่)

เปิดไฟล์จริงแล้วสรุปรูปแบบ `Log.w(TAG, "...")` ที่ใช้อยู่ตอนนี้ในเส้นทางเบื้องหลัง —
ทั้งหมดอยู่ใน `BeaconScanReceiver.kt` (`BackgroundRegionMonitor.kt` ยังไม่มีเลยตามที่
บันทึกไว้ใน §3):

| ที่ | ข้อความ | รูปแบบ |
|---|---|---|
| `BeaconScanReceiver.kt:85` | `"ชั้น proximity ล้มเหลว — enter/exit ของชั้น 1 ไม่ได้รับผลกระทบ"` + `throwable` | คำอธิบายภาษาไทยสั้น ๆ + โยน throwable ต่อท้ายเป็น argument ที่สองของ `Log.w` |
| `BeaconScanReceiver.kt:199` | `"ProximityGateStore ล้มเหลว: $it"` (`$it` = `store.lastError`) | prefix บอกชื่อ component + `: ` + ค่าตัวแปร |
| `BeaconScanReceiver.kt:205-208` | `"ถอด major/minor จากเฟรมไม่ได้ $droppedNoIdentityCount sample ในรอบนี้ — ทิ้งทั้งหมด ไม่ fallback"` | ประโยคภาษาไทยฝัง ตัวเลขไว้กลางประโยค |

**เสนอบรรทัด log ใหม่สองแบบ ตามรูปแบบเดียวกัน** (ไปอยู่ใน `BackgroundRegionMonitor.kt`
เป็นครั้งแรกของไฟล์นี้ — ตั้ง `TAG` สั้นกว่า 23 ตัว ตาม §3.2):

**(ก) สำเร็จ — พิสูจน์ว่าล้างจริงและแยกที่มาได้:**
```
Log.i(TAG, "proximityGateStore.clearRegion region=$regionIdentifier removed=$removedCount source=$source")
```
เช่น `region=bigc removed=2 source=onExitAlarm` หรือ `region=bigc-test removed=0 source=reconcile`
(`removed=0` คือเคสที่เรียกแล้วไม่มีอะไรให้ลบ ยังคง log บรรทัดนี้เสมอไม่ข้าม เพื่อพิสูจน์
ว่า "เส้นทางนี้ถูกเรียกจริง" แยกจาก "ไม่มีอะไรให้ลบ" — เทียบกับหลักการเดียวกับที่
`lastMigrationDroppedCount` แยก `null` ออกจาก `0` ที่ `ProximityGateStore.kt:152-160`)

**(ข) ล้มเหลว — ชั้น 2 พังแต่ชั้น 1 ไม่กระทบ:**
```
Log.w(TAG, "proximityGateStore.clearRegion ล้มเหลว region=$regionIdentifier source=$source", throwable)
```
รูปแบบเดียวกับ `BeaconScanReceiver.kt:85` เป๊ะ (ข้อความ + throwable เป็น argument ที่สอง)

**(ค) `stop()` — คนละ source, ล้างทั้งหมด:**
```
Log.i(TAG, "proximityGateStore.clear removed=$removedCount source=stop")
```

### 4.2 ทำไมต้องมี `source=` แยกจาก `exitReason` เดิม

`event.exitReason` ที่มีอยู่แล้ว (ค่าคือ `REASON_ALARM`/`REASON_STALE_RECONCILE`/
`REASON_STALE_BOOT_MISMATCH` — `BackgroundRegionMonitor.kt:652-654`) **แยกที่มาไม่ได้
ครบทุกกรณี**: `REASON_ALARM` มาจาก `onExitAlarm()` เท่านั้นจริง (บรรทัด 531) และ
`REASON_STALE_RECONCILE` มาจาก `reconcile()` เท่านั้นจริง (บรรทัด 644 สาขา `else`) —
แต่ `REASON_STALE_BOOT_MISMATCH` **มาได้จากทั้งสองทาง** (`onExitAlarm()` บรรทัด 494
และ `reconcile()` บรรทัด 644 สาขา `if`) ถ้าใช้แค่ `exitReason` เป็นตัวแยกจะไม่สามารถ
พิสูจน์ตามที่โจทย์นี้บังคับไว้ตรง ๆ ว่า "ต้องแยกได้ว่ามาจาก `onExitAlarm` หรือ
`reconcile()`" ได้ครบทุกเคส — จึงต้องมี `source` เป็นพารามิเตอร์แยกต่างหากตาม §3.2
ไม่ใช่ derive จาก `exitReason`

### 4.3 evidence-log ของ example app (`BackgroundEvidenceLog`) — ไม่แตะ schema

ตาม §1.1: annotation `proximityStoreCleared=true` เดิมที่ `MainActivity.kt:183` ถูกลบ
ทิ้ง **ไม่ได้ถูกแทนที่ด้วยคอลัมน์ใหม่** ใน evidence-log ของ example app — เหตุผล:
`BackgroundEvidenceLog`/`evidence_log_line.dart` เป็น schema ของ**ชั้น 1** (region
enter/exit) ล้วน ๆ (6 คอลัมน์คงที่: `timestamp / processId / event / regionIdentifier /
conclusion / rawSignals`) ผูกกับ `BackgroundRegionStateEvent` — การเพิ่มข้อมูลของชั้น 2
(proximity) เข้าไปในนั้นเป็นการเปลี่ยน schema ข้ามขอบเขตชั้นที่ ADR-20 หัวข้อ 1 ห้ามไว้
("ชั้น 1 ... ไม่แตะแม้แต่บรรทัดเดียว" — แม้ประโยคนี้พูดถึง**โค้ด** enter/exit ไม่ใช่
schema ของ evidence-log โดยตรง แต่หลักการแยกชั้นเดียวกันใช้ได้) — **หลักฐานของ PR A
จึงอยู่ใน `adb logcat` ผ่านบรรทัด `Log.i`/`Log.w` ของ §4.1 เท่านั้น ไม่ใช่ในไฟล์
evidence-log** — ถ้าต้องการให้ evidence-log เห็นด้วย เป็นงานคนละ PR ที่ต้องออกแบบ schema
ใหม่แยกต่างหาก (ไม่ใช่ขอบเขตของ PR A)

---

## 5. ผลต่อ `staleAfter`

**ย้ำตามที่ ADR-20 §7.1 สั่งไว้ตรง ๆ (ARCHITECTURE.md:4126-4128): PR A ห้ามแตะค่า
`staleAfterMillis` แม้แต่ตัวเดียว** — ยืนยันด้วยการเปิดไฟล์จริงว่าค่าปัจจุบันคือ
`60_000L` ที่ `ProximityGate.kt:199` เอกสารออกแบบนี้และการ implement ที่ตามมาต้อง
**ไม่แตะบรรทัดนี้เลย** ทั้งทางตรง (แก้เลข) และทางอ้อม (แก้ default parameter ใน
constructor ที่เรียกมันจาก `BeaconScanReceiver.kt:116` — `ProximityGate(clock =
System::currentTimeMillis)` ใช้ default อยู่แล้ว ไม่ส่งค่าทับ ต้องคงแบบนั้นไว้)

**PR A ปลดล็อก PR B (ขยับเป็น `300_000L`) อย่างไร:** ตามที่ตารางใน ADR-20 §7.1
(ARCHITECTURE.md:4132-4135) บันทึกไว้ — ก่อน PR A ฝั่ง Android **ไม่มีอะไรล้างสถานะ
proximity ตอนออกจาก region เลย** (`ProximityGateStore.clear()` มีผู้เรียกรายเดียวคือ
`MainActivity.logMonitorLifecycle()` ตอน `monitorStop` ซึ่งคือ "หยุดเฝ้าทั้งชุด" ไม่ใช่
"ออกจาก region หนึ่งอัน") — ถ้าขยับ `staleAfter` เป็น 5 นาทีโดยไม่มี §1.2 ก่อน ลูกค้าที่
เดินออกจากโซนแล้วกลับเข้ามาใหม่ภายใน 5 นาทีจะไม่ได้ notification รอบสอง เพราะ
`confirmedBucket` ของ key เดิมยังค้างเป็น `near`/`immediate` อยู่ (ไม่มีใครล้าง และยัง
ไม่ถึงเวลา stale ที่ยาวขึ้น) transition ที่เข้ามาใหม่ตอนกลับเข้าโซนจะไม่ใช่ transition
จาก `none` อีกต่อไป — ไม่ผ่านตัวกรอง "เข้าสู่ความใกล้จาก far/ไม่เคยมี" — PR A (§1.2) แก้
จุดนี้โดยลบ key ของ region ที่ออกทิ้งทันทีที่ layer 1 ประกาศ exit จริง (ไม่ว่าจะมาจาก
`onExitAlarm` หรือ `reconcile()`) — ทำให้ sighting แรกของรอบกลับเข้าโซนใหม่**ไม่มี state
เก่าให้ชน**และเริ่มนับ dwell ใหม่ทั้งหมด ตรงกับพฤติกรรมที่ `staleAfter` สั้น (60 วินาที)
เคยบังหน้าปัญหานี้ไว้โดยบังเอิญ (ตามที่ ADR-20 §7.1 อธิบายไว้)

**พฤติกรรม "เดินออก-กลับเข้าภายใน 5 นาที" หลัง PR A เทียบกับวันนี้:**
- **วันนี้ (ก่อน PR A, `staleAfter=60s`):** ถ้ากลับเข้ามาภายใน 60 วินาที มีโอกาสชนกับ
  state เก่าที่ยังไม่ stale (พฤติกรรมเดียวกับปัญหาที่ PR A แก้ แต่หน้าต่างสั้นกว่ามาก
  จนแทบไม่มีใครสังเกตเห็นในทางปฏิบัติ) — ถ้ากลับเข้ามาหลัง 60 วินาที `sweepStale()` ได้
  ล้าง state ไปแล้วตามธรรมชาติ ไม่ต้องพึ่ง exit-clear เลย
- **หลัง PR A เท่านั้น (ยังไม่มี PR B, `staleAfter` ยังคง 60s):** ไม่มีผลต่างที่สังเกตได้
  จากภายนอกมากนัก เพราะ 60 วินาทีสั้นกว่าหน้าต่างที่ exit-clear จะมีผลชัดอยู่แล้วในเคส
  ส่วนใหญ่ — **PR A เพียงลำพังจึงเป็น "โครงสร้างที่ถูกต้องเตรียมไว้ก่อน" ไม่ใช่ feature ที่
  ผู้ทดสอบจะเห็นความต่างชัดเจนในรอบเดินของ PR A เอง** (ตาม ADR-20 §7.1: "ข้อ (1.2) คือ
  ตัวปลดล็อก `staleAfter`" — ความหมายคือเป็น**เงื่อนไขที่ต้องมีก่อน** ไม่ใช่ผลที่เห็นได้
  ทันทีในตัวมันเอง)
- **หลัง PR A + PR B (`staleAfter=300s`):** เดินออก-กลับเข้าภายใน 5 นาทีจะได้
  notification รอบสองเสมอ (เพราะ key ถูกล้างไปแล้วตอน exit ไม่ต้องรอ `staleAfter` ยาว ๆ)
  — นี่คือพฤติกรรมเป้าหมายที่ ADR-20 §7.1 ทั้งข้อต้องการ

**สถานะของเอกสารนี้และของ PR A ที่จะตามมา:** `code-complete, unverified` ไม่ใช่คำตอบ
ที่ถูกต้องด้วยซ้ำ ณ จุดนี้ — สถานะปัจจุบันคือ **"ออกแบบแล้ว ยังไม่ implement"** ยังไม่มี
โค้ดให้ทดสอบ และเอกสารนี้เองก็ไม่มีรอบเดินอุปกรณ์จริงประกอบ

---

## 6. รายการเทสที่จะเขียน (ยังไม่เขียนโค้ดเทสจริงรอบนี้)

**ไฟล์ทดสอบของโมดูลนี้อยู่ที่ `packages/beacon_kit_android/android/src/test/kotlin/com/bigc/beacon_kit_android/`
— เป็น JVM unit test ล้วน (ไม่ใช่ instrumented test, ไม่ต้อง Robolectric)** ยืนยันจาก
โครงสร้างไฟล์ที่มีอยู่แล้ว (`ProximityGateStoreTest.kt`, `BackgroundRegionMonitorOnExitAlarmTest.kt`,
`BeaconScanReceiverProximityTest.kt` ฯลฯ — ทั้งหมด `602`/`415`/`318` บรรทัดตามลำดับ ใช้
`FakeSharedPreferences` (interface ปลอมเองได้) + `Mockito.mock(Context::class.java)` +
`Mockito.mockStatic(...)` สำหรับคลาสจริงของ android.jar เช่น `SystemClock`/`Log`) — รัน
บน Mac ได้ผ่านคำสั่งที่ `CONTRIBUTING.md:65-76` ระบุไว้แล้ว:

```bash
cd packages/beacon_kit/example/android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  ./gradlew :app:testDebugUnitTest :beacon_kit_android:testDebugUnitTest
```

**ทุกเทสในรายการด้านล่างเป็น Kotlin unit test ประเภทนี้ทั้งหมด — รันบน Mac ได้โดยไม่ต้อง
มี emulator/อุปกรณ์จริง** (ต่างจากการยืนยันว่า exit-clear "ทำงานจริง" บนเครื่องจริงซึ่ง
ต้องมีรอบเดินแยกต่างหากตามที่ §5 ระบุไว้)

### 6.1 `ProximityGateStore.clearRegion()` — เพิ่มในไฟล์เดิม `ProximityGateStoreTest.kt`

ไฟล์นี้มี `mockContext(prefs)` helper อยู่แล้ว (`ProximityGateStoreTest.kt:67`) และ
`FakeSharedPreferences` รองรับ `load()`/`save()` เต็มรูปแบบอยู่แล้ว — ต่อยอดได้ตรง ๆ
ไม่ต้องเพิ่ม test infrastructure ใหม่:

1. **[บังคับ] `bigc` vs `bigc-test`** — ตั้ง state ของทั้งสอง region (`proximityKeyFor("bigc",
   ...)` และ `proximityKeyFor("bigc-test", ...)`) เรียก `clearRegion("bigc")` แล้วยืนยัน
   ว่า key ของ `"bigc-test"` **ยังอยู่ครบ** (ไม่ถูกลบ) และ key ของ `"bigc"` หายไป และ
   `removedCount == 1` — นี่คือเทสที่พิสูจน์ตรง ๆ ว่า exact-match (ไม่ใช่ prefix) ทำงาน
   ถูกตามที่ §2 อธิบาย
2. **[บังคับ] `regionIdentifier` ที่มี `|` อยู่ข้างใน** — ต่อยอดจาก fixture ที่มีอยู่แล้ว
   ที่ `ProximityGateStoreTest.kt:440-475` (region `"a|b"`) เพิ่ม sibling key ของ region
   `"a"` เข้าไปด้วย เรียก `clearRegion("a|b")` แล้วยืนยันว่า key ของ region `"a"` (ซึ่งเป็น
   คนละ region แม้ชื่อจะเป็นส่วนขึ้นต้นของ `"a|b"`) ไม่ถูกลบ และ key ของ `"a|b"` หายไปครบ
3. **[บังคับ] store ว่าง/คีย์พัง → ไม่ throw** — (ก) เรียก `clearRegion(...)` กับ store
   ที่ไม่เคยมี key ใด ๆ เลย ต้องได้ `removedCount == 0` และ `lastError == null` ไม่มี
   exception (ข) ตั้ง raw JSON ที่มี key รูปร่างพัง (เช่น ใช้ fixture แบบเดียวกับเทสต์
   `countShapeInvalidKeys` ที่มีอยู่แล้วในไฟล์นี้) แล้วเรียก `clearRegion(...)` ต้องไม่
   throw เช่นกัน (อธิบายเหตุผล: key รูปร่างพังถูก `load()` กรองทิ้งไปตั้งแต่ก่อนถึง
   `clearRegion()` อยู่แล้วผ่าน `statesFromJson()`/`isValidKeyShape()` — `clearRegion()`
   จึงไม่มีทางเห็น key พังเลยด้วยซ้ำ เป็นผลพลอยได้จากการสร้างบน `load()`/`save()` เดิม)
4. **[เสริม] ไม่มี commit() เปล่าเมื่อไม่มีอะไรให้ลบ** — เรียก `clearRegion("ไม่มีจริง")`
   กับ store ที่มี key ของ region อื่นอยู่ แล้วยืนยันว่าเนื้อหาที่ `load()` อ่านกลับมาหลัง
   เรียกยังเหมือนเดิมทุกประการ (พิสูจน์ทางอ้อมว่าไม่มีการเขียนทับที่ไม่จำเป็น)

### 6.2 ไฟล์ใหม่ `BackgroundRegionMonitorProximityExitClearTest.kt`

ไม่มีไฟล์เทสเดิมที่ครอบ `reconcile()`/`stop()` แบบ end-to-end (มีแค่
`BackgroundRegionMonitorStaleReasonTest.kt` ซึ่งเทสเฉพาะ pure function `staleReason()`
ล้วน — `BackgroundRegionMonitorStaleReasonTest.kt:22-140` ไม่แตะ `Context`/store เลย —
และ `BackgroundRegionMonitorOnExitAlarmTest.kt` ซึ่งครอบแค่ `onExitAlarm()`) ต้องสร้างไฟล์
ใหม่ตามชื่อ pattern เดิม (`BackgroundRegionMonitor<เรื่อง>Test.kt`) ใช้ `mockContext(prefs)`
pattern เดียวกับ `BackgroundRegionMonitorOnExitAlarmTest.kt:89-94` (stub
`getSharedPreferences(anyString(), anyInt())` ให้คืน `FakeSharedPreferences` ตัวเดียวกัน
ทุกชื่อไฟล์ prefs — ใช้ได้แม้ `ProximityGateStore`/`BackgroundRegionStore` มี `PREFS_NAME`
คนละชื่อกันจริง เพราะทั้งคู่ใช้ constant key คนละชื่อกันอยู่แล้วภายใน `Map` เดียวกัน
ไม่ชนกัน — เป็นทางลัดเดียวกับที่ไฟล์เทสเดิมใช้อยู่แล้ว ไม่ใช่ของใหม่)

5. **[บังคับ] `reconcile()` เรียกผ่านจุดคอขวดเดียวกับ `onExitAlarm`** — ตั้ง region ให้
   `isInside == true` และ stale เกิน K=10 เท่าของ `exitTimeoutSeconds` (ใช้ pattern เวลา
   เดียวกับที่ `BackgroundRegionMonitorStaleReasonTest.kt` ใช้พิสูจน์ boundary ของ
   `staleReason()`) พร้อม pre-populate `ProximityGateStore` ด้วย key ของ region เดียวกัน
   เรียก `BackgroundRegionMonitor.reconcile(context)` แล้วยืนยันว่า
   `ProximityGateStore(context).load()` **ไม่มี** key ของ region นั้นเหลืออยู่อีก — ทำ
   เทสคู่ขนานอีกตัวที่เรียก `onExitAlarm()` แทน (เงื่อนไขให้เข้าสาขา `REASON_ALARM`) แล้ว
   ยืนยันผลเดียวกัน — **สองเทสนี้ต้องยืนยันผลเหมือนกันทุกประการ** เพื่อพิสูจน์ว่าทั้งสอง
   เส้นทางไหลผ่านจุดคอขวดเดียวกัน (`emitExitAndMarkOutside`) ไม่ใช่ implement แยกกันสอง
   ชุดที่บังเอิญให้ผลเหมือนกัน — เช็คเพิ่มว่า `source=` ที่ log ออกมา (mock ผ่าน
   `Mockito.mockStatic(Log::class.java)` แล้วตรวจ argument ที่ส่งเข้า `Log.i`) ตรงกับที่
   มาจริง (`"onExitAlarm"` vs `"reconcile"`) — พิสูจน์ข้อกำหนดของ §4.2 ด้วยในตัว
6. **[เสริม — สำคัญ] สาขาที่ไม่ใช่ exit จริง ต้องไม่ล้าง proximity** — เรียก
   `onExitAlarm()` ในเงื่อนไขที่เข้าสาขา `REASON_STILL_SEEN`/`REASON_NOT_INSIDE`/
   `REASON_NOT_ACTIVE` (ไม่ผ่าน `emitExitAndMarkOutside()` เลย) พร้อม pre-populate
   `ProximityGateStore` เดียวกัน แล้วยืนยันว่า key ของ proximity **ยังอยู่ครบ ไม่ถูกแตะ
   เลย** — ป้องกัน regression ที่ล้าง proximity เกินจำเป็นตอนที่ region ยังไม่ได้ออกจริง
7. **[บังคับ] `stop()` ล้างทั้งหมด** — เรียก `start()` (หรือจำลอง state ที่เทียบเท่า) ให้
   มีทั้ง `BackgroundRegionStore` state และ `ProximityGateStore` state (หลาย region) แล้ว
   เรียก `BackgroundRegionMonitor.stop(context)` ยืนยันว่า `ProximityGateStore(context).load()`
   คืน map ว่างเปล่าทุกกรณี (ไม่ใช่แค่ region เดียว — `stop()` ล้างทุก region ไม่เลือก)
8. **[เสริม] ชั้น 2 พังไม่ทำให้ชั้น 1 พัง (regression ของ §3)** — บังคับให้
   `ProximityGateStore(context).clearRegion(...)` throw จริง (วิธีที่ทำได้ตรงไปตรงมาที่สุด
   คือ mock `Context.getSharedPreferences(...)` ให้ `thenThrow(RuntimeException(...))`
   เฉพาะตอนถูกเรียกด้วยชื่อไฟล์ของ `ProximityGateStore`
   — ต้องแยก stub ตามชื่อไฟล์ prefs ในเทสนี้เทสเดียว ต่างจาก mockContext ทั่วไปของไฟล์นี้
   ที่คืนตัวเดียวกันทุกชื่อ) แล้วเรียก `onExitAlarm()`/`reconcile()` ยืนยันว่า:
   - เหตุการณ์ `state == "exit"` ของชั้น 1 ยังถูกส่งไปที่ `observer` ตามปกติ (ไม่หาย)
   - `BackgroundRegionStore.isInside(regionIdentifier)` พลิกเป็น `false` ตามปกติ (ไม่ค้าง)
   - ไม่มี exception หลุดออกจาก `onExitAlarm()`/`reconcile()` ไปถึงผู้เรียก (ทดสอบด้วยการ
     ไม่ครอบ try/catch ที่ฝั่งเทสเอง — ถ้า assert ผ่านแปลว่าไม่มีอะไรโยนออกมาจริง)
   - มี `Log.w(TAG, "proximityGateStore.clearRegion ล้มเหลว...", throwable)` ถูกเรียกจริง
     (ยืนยันผ่าน `Mockito.mockStatic(Log::class.java)` เหมือนที่ `BeaconScanReceiverProximityTest.kt:144`
     ทำ)

### 6.3 ไม่ต้องแก้ไฟล์เทสของ key-parsing เดิม

`ProximityKeyCodecTest.kt` เทส `proximityKeyPartsOrNull()`/`proximityKeyFor()` ครบอยู่แล้ว
(รวมเคส `"a|b"`, `"bigc-test|..."`, ค่าเกินช่วง uint16 ฯลฯ) — PR A **ไม่แก้ตรรกะถอด key
เลย** (แค่**เรียกใช้**ฟังก์ชันเดิม) จึงไม่ต้องเพิ่มเทสในไฟล์นี้

---

## สรุปไฟล์ที่จะถูกแก้ (สำหรับ flutter-dev รอบ implement จริง — ยังไม่แก้รอบนี้)

- `packages/beacon_kit_android/android/src/main/kotlin/com/bigc/beacon_kit_android/ProximityGateStore.kt`
  — เพิ่ม `clearRegion(regionIdentifier: String): Int`
- `packages/beacon_kit_android/android/src/main/kotlin/com/bigc/beacon_kit_android/BackgroundRegionMonitor.kt`
  — เพิ่ม `TAG` + `Log` import, แก้ `stop()`, เพิ่มพารามิเตอร์ `source` ให้
  `emitExitAndMarkOutside()`, แก้ 3 จุดเรียก (onExitAlarm ×2, reconcile ×1)
- `packages/beacon_kit/example/android/app/src/main/kotlin/com/beaconkit/example/MainActivity.kt`
  — ลบการเรียก `ProximityGateStore(context).clear()` + คอมเมนต์เก่า + annotation
  `proximityStoreCleared=true`
- ไฟล์เทส: `ProximityGateStoreTest.kt` (เพิ่มเคส) + `BackgroundRegionMonitorProximityExitClearTest.kt`
  (ไฟล์ใหม่)
