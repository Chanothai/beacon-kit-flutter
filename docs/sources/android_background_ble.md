# Sources: Android background BLE scanning

วันที่ค้นคว้า: 1 กันยายน 2026 — ดึงจากหน้าเอกสารทางการของ Android โดยตรง (developer.android.com) ไม่ใช่จากบล็อก, StackOverflow หรือความจำ

ไฟล์นี้มีไว้เพื่อให้ข้ออ้างเชิงสเปกที่กระจายอยู่ในโค้ด (`BackgroundRegionMonitor.kt`, `AndroidManifest.xml`, ADR-14) ตรวจย้อนกลับได้จากแหล่งเดียว **ข้อความในเครื่องหมายคำพูดคือคำต่อคำจากหน้าเอกสาร** ไม่ได้ถอดความ

---

## 1. unfiltered BLE scan ถูกหยุดเมื่อหน้าจอปิด — ✅ ยืนยันแล้ว

> "Start Bluetooth LE scan with default parameters and no filters. The scan results will be delivered through `callback`. **For unfiltered scans, scanning is stopped on screen off to save power. Scanning is resumed when screen is turned on again.** To avoid this, use `startScan(List, ScanSettings, ScanCallback)` with desired `ScanFilter`."

- แหล่ง: `BluetoothLeScanner.startScan(ScanCallback)` — https://developer.android.com/reference/android/bluetooth/le/BluetoothLeScanner#startScan(android.bluetooth.le.ScanCallback)

**สิ่งที่เอกสารบอกจริง ๆ:** ข้อความนี้อยู่ที่ overload ที่ **ไม่มี filter** และเอกสารบอกวิธีเลี่ยงไว้เองว่าให้ใช้ overload ที่ส่ง `ScanFilter` — ไม่ใช่ข้อความที่ครอบคลุมการสแกนทุกแบบ

**ตรงกับโค้ดของเราอย่างไร:** `BackgroundRegionMonitor.startScansOnly` ส่ง `listOf(region.toScanFilter())` เสมอ จึงไม่เข้าเงื่อนไข "unfiltered" ข้อนี้ — แต่ **ห้ามอ่านกลับด้านว่า "มี filter แล้วรับประกันว่าสแกนตอนจอปิด"** เอกสารไม่ได้ระบุเช่นนั้น มันแค่ไม่ได้ระบุว่าจะหยุด

---

## 2. scan mode ถูกบังคับเป็น LOW_POWER เมื่อแอปไม่ได้อยู่ foreground — ✅ ยืนยันแล้ว

> `SCAN_MODE_LOW_POWER` — "Perform Bluetooth LE scan in low power mode. This is the default scan mode as it consumes the least power. **This mode is enforced if the scanning application is not in foreground.**"

> `SCAN_MODE_LOW_LATENCY` — "Scan using highest duty cycle. It's recommended to only use this mode when the application is running in the foreground."

- แหล่ง: `ScanSettings` — https://developer.android.com/reference/android/bluetooth/le/ScanSettings#SCAN_MODE_LOW_POWER

**ตรงกับโค้ดของเราอย่างไร:** `BackgroundRegionMonitor.kt:200-203` ตั้ง `SCAN_MODE_LOW_POWER` ตรง ๆ ซึ่งเป็นการเขียนสิ่งที่ระบบจะบังคับอยู่แล้วให้เห็นชัดในโค้ด ไม่ใช่การยอมแพ้ — ถ้าขอ `LOW_LATENCY` ในเส้นทางเบื้องหลังจะได้ `LOW_POWER` อยู่ดี แต่คนอ่านโค้ดจะเข้าใจผิดว่าได้ความถี่สูง

**สิ่งที่เอกสาร _ไม่ได้_ บอก:** ไม่ได้ระบุว่า "not in foreground" นับจากอะไร (importance level ไหน) และไม่ได้ระบุคาบเวลาจริงของ `LOW_POWER` เป็นตัวเลข — **ห้ามอ้างตัวเลขคาบสแกนจากเอกสารนี้**

---

## 3. `startScan` แบบ `PendingIntent` ใช้กับ process ที่ไม่ได้รันอยู่ได้ — ✅ ยืนยันแล้ว

> "Start Bluetooth LE scan using a PendingIntent. The scan results will be delivered via the PendingIntent. **Use this method of scanning if your process is not always running and it should be started when scan results are available.**"

> "An app must have `ACCESS_COARSE_LOCATION` permission in order to get results. An App targeting Android Q or later must have `ACCESS_FINE_LOCATION` permission in order to get results."

> "When the PendingIntent is delivered, the Intent passed to the receiver or activity will contain one or more of the extras `EXTRA_CALLBACK_TYPE`, `EXTRA_ERROR_CODE` [, `EXTRA_LIST_SCAN_RESULT`]"

- แหล่ง: `BluetoothLeScanner.startScan(List, ScanSettings, PendingIntent)` (เพิ่มใน API level 26) — https://developer.android.com/reference/android/bluetooth/le/BluetoothLeScanner#startScan(java.util.List%3Candroid.bluetooth.le.ScanFilter%3E,%20android.bluetooth.le.ScanSettings,%20android.app.PendingIntent)

**สิ่งที่เอกสารบอกจริง ๆ:** บอกว่านี่คือ **จุดประสงค์ที่ออกแบบมา** ของ API นี้ ("if your process is not always running") — ไม่ได้รับประกันว่าทุกเครื่องทุกยี่ห้อจะปลุก process จริง (MIUI/ColorOS มีนโยบายของตัวเอง) การพิสูจน์เรื่องนั้นต้องมาจากการทดสอบบนเครื่องจริง ไม่ใช่จากเอกสารหน้านี้

### ข้อประกอบ: mutability ของ PendingIntent ที่ Android 12 บังคับ

> "**Pending intents mutability** — If your app targets Android 12, you must specify the mutability of each PendingIntent object that your app creates. This additional requirement improves your app's security."

- แหล่ง: Behavior changes: Apps targeting Android 12 — https://developer.android.com/about/versions/12/behavior-changes-12#pending-intent-mutability

> พารามิเตอร์ `intent` ของ `PendingIntent.send(Context, int, Intent, ...)`: "Additional Intent data. See `Intent.fillIn()` for information on how this is applied to the original Intent. Use null to not modify the original Intent. **If flag `FLAG_IMMUTABLE` was set when this pending intent was created, this argument will be ignored.**"

- แหล่ง: `PendingIntent.send` — https://developer.android.com/reference/android/app/PendingIntent#send(android.content.Context,%20int,%20android.content.Intent,%20android.app.PendingIntent.OnFinished,%20android.os.Handler)

สองข้อนี้ประกอบกันเป็นเหตุผลที่ `PendingIntent` ของผลสแกนต้องเป็น `FLAG_MUTABLE`: ระบบส่งผลสแกนกลับมาโดย **เติม extras** ผ่านพารามิเตอร์ `intent` ของ `send()` ถ้าเป็น `FLAG_IMMUTABLE` จะได้ broadcast แต่ **ไม่มีผลสแกนติดมา** ซึ่งเป็นความล้มเหลวแบบเงียบ

---

## 4. คำเตือนเรื่อง `neverForLocation` กับ BLE beacon — ✅ ยืนยันแล้ว

> "**Note: If you include `neverForLocation` in your `android:usesPermissionFlags`, some BLE beacons are filtered from the scan results.**"

> "If your app doesn't use Bluetooth scan results to derive physical location, you can make a strong assertion that your app never uses the Bluetooth permissions to derive physical location."

- แหล่ง: Bluetooth permissions — https://developer.android.com/develop/connectivity/bluetooth/bt-permissions#assert-never-for-location

**ตรงกับโค้ดของเราอย่างไร:** beacon_kit อนุมานว่าผู้ใช้อยู่สาขาไหน = การอนุมานตำแหน่งตรงตัว การประกาศ `neverForLocation` จึงทั้งผิดความจริงและทำให้ beacon บางตัวหายจากผลสแกน — `packages/beacon_kit_android/android/src/main/AndroidManifest.xml:20` จึงประกาศ `BLUETOOTH_SCAN` **โดยไม่มี** `usesPermissionFlags` และมี `ACCESS_FINE_LOCATION` (บรรทัด 27) ตามที่ข้อ 3 ระบุว่าจำเป็นสำหรับแอปที่ target Android Q ขึ้นไป

---

## 5. Direct Boot: `filesDir` / SharedPreferences เข้าถึงไม่ได้ก่อนปลดล็อกครั้งแรก — ✅ ยืนยันแล้ว (พร้อมข้อยกเว้นที่ต้องรู้)

> "Android 7.0 runs in a secure, Direct Boot mode when the device has been powered on but the user hasn't unlocked the device. To support this, the system provides two storage locations for data:
> **Credential encrypted storage, which is the default storage location and only available after the user has unlocked the device.**
> Device encrypted storage, which is a storage location available both during Direct Boot mode and after the user has unlocked the device."

> "**By default, apps don't run during Direct Boot mode.**"

> "Credential encrypted storage is available after the user has successfully unlocked the device and until the user restarts the device."

- แหล่ง: Support Direct Boot mode — https://developer.android.com/privacy-and-security/direct-boot

> `Context.createDeviceProtectedStorageContext()`: "Return a new Context object for the current Context but whose storage APIs are backed by device-protected storage. On devices with direct boot, data stored in this location is encrypted with a key tied to the physical device, and it can be accessed immediately after the device has booted successfully, **both before and after the user has authenticated with their credentials**"

- แหล่ง: `Context` — https://developer.android.com/reference/android/content/Context#createDeviceProtectedStorageContext()

**ที่ verify ได้จริงคือระดับ "default storage location"** — เอกสารบอกว่า credential-encrypted คือที่เก็บ**โดยปริยาย** และ `createDeviceProtectedStorageContext()` มีไว้เพื่อ**เปลี่ยน** storage API ของ Context ไปใช้อีกที่หนึ่ง สองข้อนี้ประกอบกันแปลว่า `getFilesDir()`/`getSharedPreferences()` ของ Context ปกติอยู่ใน credential-encrypted

⚠️ **สิ่งที่ verify ไม่ได้:** หน้า reference ของ `getFilesDir()` และ `getSharedPreferences()` **ไม่ได้พูดถึงการเข้ารหัสหรือ Direct Boot เลยแม้แต่ประโยคเดียว** — ไม่มีข้อความทางการที่ระบุตรง ๆ ต่อ API ทั้งสองตัว ข้อสรุปข้างบนจึงมาจากการต่อสองประโยคจากคนละหน้า ไม่ใช่จากประโยคเดียวที่ระบุตรง

### ⚠️ ข้อยกเว้นที่เปลี่ยนผลการทดสอบได้ทั้งเคส

> "**If the underlying device does not have the ability to store device-protected and credential-protected data using different keys, then both storage areas will become available at the same time.** They remain as two distinct storage locations on disk, and only the window of availability changes."

- แหล่ง: เดียวกับ `createDeviceProtectedStorageContext()` ข้างบน

แปลว่าบนเครื่องที่**ไม่ได้ใช้ file-based encryption** การเขียน/อ่าน `filesDir` ก่อนปลดล็อก **อาจสำเร็จ** — ห้ามสรุปว่า "เขียนได้ = ปลดล็อกแล้ว" · **ยังไม่ได้ตรวจว่าเครื่องทดสอบใช้ FBE หรือไม่** (ตรวจแบบอ่านอย่างเดียวได้ด้วย `adb shell getprop ro.crypto.type` — `file` = FBE, `block` = FDE) — **ยังไม่ยืนยัน**

## 6. `LOCKED_BOOT_COMPLETED` ต้องมี `directBootAware="true"` — ✅ ยืนยันแล้ว

> `ACTION_LOCKED_BOOT_COMPLETED`: "This broadcast is sent immediately at boot by all devices (regardless of direct boot support) running `Build.VERSION_CODES.N` or higher. Upon receipt of this broadcast, the user is still locked and only device-protected storage can be accessed safely...
> **To receive this broadcast, your receiver component must be marked as being `ComponentInfo.directBootAware`.**"

> `ACTION_BOOT_COMPLETED`: "Upon receipt of this broadcast, the user is unlocked and both device-protected and credential-protected storage can accessed safely."

- แหล่ง: `Intent` — https://developer.android.com/reference/android/content/Intent#ACTION_LOCKED_BOOT_COMPLETED

> "Apps must register their components with the system before they can run during Direct Boot mode or access device encrypted storage... set the `android:directBootAware` attribute to true in your manifest. **Encryption aware components** can register to receive an `ACTION_LOCKED_BOOT_COMPLETED` broadcast message"

- แหล่ง: https://developer.android.com/privacy-and-security/direct-boot

**เกร็ดที่เกี่ยวกับ force-stop โดยตรง (ทั้งสอง action):** "Starting from Android `Build.VERSION_CODES.VANILLA_ICE_CREAM`, this broadcast is not only sent after the device boots but also delivered to an app when it is removed from the Stopped state, such as the first launch after force-stopping the app." — เครื่องทดสอบเป็น Android 12 จึง**ยังไม่ได้ประโยชน์ข้อนี้**

## 7. นาฬิกาปลุกถูกล้างทิ้งเมื่อรีบูต — ✅ ยืนยันแล้ว

> "Registered alarms are retained while the device is asleep (and can optionally wake the device up if they go off during that time), but **will be cleared if it is turned off and rebooted**."

- แหล่ง: `AlarmManager` — https://developer.android.com/reference/android/app/AlarmManager

> "**By default, all alarms are canceled when a device shuts down.**"

- แหล่ง: Schedule alarms — https://developer.android.com/develop/background-work/services/alarms/schedule

**ผลกับเคส A5 โดยตรง:** นาฬิกาปลุก exit ที่ตั้งไว้ก่อนรีบูต **ไม่รอด** `RegionExitAlarmReceiver` จึงไม่มีทางถูกเรียกหลังรีบูต — ดูผลที่ตามมาใน runbook §5

---

## 8. นาฬิกาปลุก exit ใช้ `setAndAllowWhileIdle` — **เวลาที่ขอเป็นค่าขั้นต่ำ ไม่ใช่ค่าที่รับประกัน** ✅ ยืนยันแล้ว

**API ที่ใช้จริง** (ตรวจจากไฟล์ ไม่ใช่จากความจำ): `BackgroundRegionMonitor.kt:365-369`

```kotlin
alarmManager.setAndAllowWhileIdle(
    AlarmManager.ELAPSED_REALTIME_WAKEUP,
    atElapsedMillis,
    exitAlarmPendingIntent(context, regionIdentifier),
)
```

ไม่ใช่ `setExact`, ไม่ใช่ `setExactAndAllowWhileIdle`, ไม่ใช่ `setWindow`

### เอกสารระบุความแม่นยำไว้อย่างไร

> `setAndAllowWhileIdle`: "**Like `set(int,long,PendingIntent)`**, but this alarm will be allowed to execute even when the system is in low-power idle (a.k.a. doze) modes."

> "To reduce abuse, there are restrictions on how frequently these alarms will go off for a particular application. **Under normal system operation, it will not dispatch these alarms more than about every minute** (at which point every such pending alarm is dispatched); **when in low-power idle modes this duration may be significantly longer, such as 15 minutes.**"

> "Unlike other alarms, **the system is free to reschedule this type of alarm to happen out of order** with any other alarms, even those from the same app... but **may also happen even when not idle**."

> "Regardless of the app's target SDK version, **this call always allows batching** of the alarm."

และเนื่องจากเอกสารระบุว่าเหมือน `set()` ข้อความของ `set()` จึงใช้กับตัวนี้ด้วย:

> "Note: Beginning in API 19, the trigger time passed to this method is treated as **inexact**: **the alarm will not be delivered before this time, but may be deferred and delivered some time later.** The OS will use this policy in order to "batch" alarms together across the entire system, minimizing the number of times the device needs to "wake up" and minimizing battery use."

- แหล่ง: `AlarmManager` — https://developer.android.com/reference/android/app/AlarmManager#setAndAllowWhileIdle(int,%20long,%20android.app.PendingIntent)

### ข้อสรุปที่ต้องบันทึกไว้และห้ามอธิบายให้ฟังดูดีกว่านี้

> **`exitTimeoutSeconds` คือค่า _ขั้นต่ำ_ ไม่ใช่ค่าที่รับประกัน**
>
> เอกสารรับประกันด้านเดียวเท่านั้น: **"will not be delivered before this time"** —
> ไม่มีเพดานบนที่รับประกัน · ตั้ง 30 วินาทีจึงแปลว่า "ไม่เร็วกว่า 30 วินาที"
> ไม่ได้แปลว่า "ประมาณ 30 วินาที"

ตัวเลขที่เอกสาร**ระบุเอง**ว่าเป็นเพดานของความถี่ในการส่ง (ไม่ใช่ความคลาดเคลื่อนของ
นาฬิกาปลุกแต่ละอัน): **~1 นาที** ตอนระบบทำงานปกติ · **~15 นาที** ตอนอยู่ใน low-power idle

**ตรงกับข้อมูลจริงจากสนาม (1 ก.ย. 2026):** exit หน่วง 22 วินาที กับ 3 นาที 15 วินาที
โดยที่ `exitTimeoutSeconds=30` เท่ากันทั้งคู่ — ทั้งสองค่าอยู่ในสิ่งที่เอกสารอนุญาต
ให้เกิดได้ · **แต่ตัวเลขสองตัวนั้นเพียงอย่างเดียวยังแยกไม่ได้** ว่าเป็นการเลื่อนของ
นาฬิกาปลุก หรือมีผลสแกนเข้ามาเลื่อนหน้าต่างออกไป จึงเป็นที่มาของฟิลด์
`sinceLastSeenMs` / `scheduledAtElapsed` / `firedAtElapsed` ในบรรทัด `exit`
(ดู runbook §0.2)

### ทางเลือกที่ **ไม่** เลือก และเหตุผล

| API | ทำไมไม่ใช้ |
|---|---|
| `setExactAndAllowWhileIdle` | "apps targeting SDK level 31 or higher need to request the `SCHEDULE_EXACT_ALARM` permission to use this API, unless the app is exempt from battery restrictions" — และเอกสารเองระบุว่า "the OS will allow itself more flexibility for scheduling these alarms than regular exact alarms" จึง**ไม่ได้แม่นจริงตอน idle** อยู่ดี |
| `setWindow` | "Starting with API level S, apps should not pass in a window of less than 10 minutes... the app should expect any window smaller than 10 minutes to get elongated to 10 minutes" — หน้าต่าง 30 วินาทีที่เราต้องการจะถูกยืดเป็น 10 นาที |
| `set` | ไม่ทำงานตอน Doze ซึ่งเป็นเคสหลักที่ต้องการวัด |

**ยังไม่ยืนยัน:** ไม่มีเอกสารทางการที่ระบุความคลาดเคลื่อน **สูงสุด** ของ
`setAndAllowWhileIdle` เป็นตัวเลข — ตัวเลข 1 นาที / 15 นาทีข้างบนเป็น *ความถี่ในการ
dispatch* ที่เอกสารระบุ ไม่ใช่การรับประกันว่านาฬิกาปลุกอันหนึ่งจะช้าได้ไม่เกินเท่าไร
**หาแหล่งอ้างอิงสำหรับเพดานบนไม่ได้**

---

## 9. `BluetoothAdapter.ACTION_STATE_CHANGED` ประกาศใน manifest **แล้วไม่ได้รับ** บน API 26+ — ✅ ยืนยันแล้ว

*(ค้นเพิ่ม 2 กันยายน 2026 — คำถามที่ `prototype/visit_filter/SENSING.md` ค้างไว้ก่อนเริ่ม port)*

**คำถาม:** ถ้าประกาศ `<receiver>` ที่กรอง `android.bluetooth.adapter.action.STATE_CHANGED`
ไว้ใน manifest จะได้รับ broadcast ตอนผู้ใช้เปิด/ปิด Bluetooth หรือไม่ — เพราะถ้าได้
เราจะรู้ **เวลาที่เริ่มตาบอดจริง** แทนที่จะต้องเดาจากการ poll ตอนถูกปลุก

**คำตอบ: ไม่ได้รับ**

ข้อจำกัดของ Android 8.0:

> "Apps that target Android 8.0 or higher can no longer register broadcast receivers
> for implicit broadcasts in their manifest unless the broadcast is restricted to that
> app specifically. An *implicit broadcast* is a broadcast that does not target a
> specific component within an app."
> — https://developer.android.com/about/versions/oreo/background

หน้ารายการข้อยกเว้นระบุขอบเขตของตัวเองไว้ว่า:

> "As part of the Android 8.0 (API level 26) background execution limits, apps that
> target the API level 26 or higher can't register broadcast receivers for implicit
> broadcasts in their manifest unless the broadcast is sent specifically to them.
> However, several broadcasts are exempted from these limitations. **Apps can continue
> to register listeners for the following broadcasts, no matter what API level the apps
> target.**"
> — https://developer.android.com/develop/background-work/background-tasks/broadcasts/broadcast-exceptions

**ดึงรายการข้อยกเว้นทั้งหน้ามาไล่ดูทีละข้อแล้ว — Bluetooth มีอยู่แค่สี่ตัวนี้:**

> "`BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED`,
> `BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED`, `ACTION_ACL_CONNECTED`,
> `ACTION_ACL_DISCONNECTED` — User experience is not likely to suffer if apps receive
> broadcasts for these Bluetooth events."

**`android.bluetooth.adapter.action.STATE_CHANGED` ไม่ปรากฏในหน้ารายการข้อยกเว้นเลย**
มันจึงเป็น implicit broadcast ธรรมดาที่ตกอยู่ใต้ข้อจำกัด → **ตัวรับที่ประกาศใน
manifest จะไม่ถูกเรียก**

ทางเลือกเดียวที่เอกสารให้ไว้คือลงทะเบียนตอนรัน:

> "Apps can use `Context.registerReceiver()` at runtime to register a receiver for any
> broadcast, whether implicit or explicit."
> — https://developer.android.com/about/versions/oreo/background

⚠️ **ซึ่งใช้กับเคสของเราไม่ได้** — `registerReceiver()` ผูกกับ `Context` ที่มีชีวิต
ตัวรับหายไปพร้อม process และ ADR-14 ทั้งฉบับตั้งอยู่บนข้อเท็จจริงว่าเราไม่มี process
ที่มีชีวิตอยู่แล้ว

**`targetSdk` ของ example app มาจาก `flutter.targetSdkVersion`**
(`packages/beacon_kit/example/android/app/build.gradle.kts:23`) ซึ่งเป็นค่าที่สูงกว่า
26 มากอยู่แล้ว และ Play Store ก็บังคับค่าขั้นต่ำที่สูงกว่านั้น — **ไม่มีทางหลบข้อจำกัด
นี้ด้วยการลด targetSdk**

### ผลพลอยได้: ยืนยันสมมติฐานเดิมของ ADR-14 ที่ยังไม่เคยตรวจ

ตัวรับที่ `AndroidManifest.xml:83-91` ประกาศไว้แล้วสามตัว — หน้าเดียวกันนี้ยืนยันว่า
**ใช้ได้จริงทั้งสามตัว**:

> "`ACTION_LOCKED_BOOT_COMPLETED`, `ACTION_BOOT_COMPLETED` — Exempted because these
> broadcasts are sent only once, at first boot, and many apps need to receive these
> broadcasts, such as to schedule jobs and alarms."

และ `MY_PACKAGE_REPLACED` ไม่ได้อยู่ในรายการข้อยกเว้น แต่ได้รับด้วยเหตุผลคนละอย่าง:

> "`ACTION_MY_PACKAGE_REPLACED` is also an implicit broadcast, but since it is sent
> only to the app whose package was replaced it will be delivered to manifest-registered
> receivers."
> — https://developer.android.com/about/versions/oreo/background

*(หมายเหตุ: `LOCKED_BOOT_COMPLETED` ได้รับการยกเว้นจากข้อจำกัด implicit broadcast ก็จริง
แต่ยัง **ไม่ถูกส่งมา** เพราะตัวรับของเราไม่ได้ประกาศ `directBootAware` — คนละข้อจำกัดกัน
ดูข้อ 6 และ runbook §5)*

---

## หาแหล่งอ้างอิงไม่ได้ / ยังไม่ยืนยัน

รายการนี้ **ไม่ใช่** ข้ออ้างที่เราใช้อยู่ แต่เป็นสิ่งที่ถูกถามถึงบ่อยและยังไม่มีเอกสารทางการรองรับ — บันทึกไว้เพื่อไม่ให้มีใครเติมเข้ามาโดยคิดว่าเคยตรวจแล้ว

- **"filtered scan ทำงานต่อได้ตอนหน้าจอปิด"** — เอกสารระบุแค่ว่า *unfiltered* จะหยุด (ข้อ 1) ไม่ได้ระบุยืนยันฝั่งตรงข้าม หาแหล่งอ้างอิงไม่ได้
- **ตัวเลขคาบสแกนจริงของแต่ละ `SCAN_MODE`** (เช่น "LOW_POWER = สแกน 0.5 วิ ทุก 5 วิ") — ไม่มีในเอกสารทางการ ตัวเลขที่พบทั่วไปบนอินเทอร์เน็ตมาจากการอ่านซอร์ส AOSP ซึ่งเปลี่ยนได้ตามเวอร์ชันและผู้ผลิต หาแหล่งอ้างอิงทางการไม่ได้
- **พฤติกรรมของ OEM ไทยที่พบบ่อย (MIUI / ColorOS / One UI) เรื่องการฆ่า process เบื้องหลัง** — ไม่มีเอกสารทางการจาก Google และเอกสารของผู้ผลิตไม่ระบุรายละเอียดระดับนี้ หาแหล่งอ้างอิงไม่ได้ ต้องพิสูจน์ด้วยการทดสอบบนเครื่องจริงเท่านั้น
- **`importance` ที่ระบบจัดให้ process ขณะที่ `BroadcastReceiver.onReceive()` กำลังทำงาน** — เอกสารของ `ActivityManager.RunningAppProcessInfo` อธิบาย `IMPORTANCE_SERVICE` ว่า "This process contains **services** that should remain running" และ `IMPORTANCE_FOREGROUND` ว่า "This process is running the foreground UI" — **ไม่มีค่าคงที่ตัวไหนที่เอกสารระบุว่าใช้กับ broadcast receiver** จึง **หาแหล่งอ้างอิงไม่ได้** ว่า process ที่ถูกสร้างมาเพื่อ `onReceive` จะได้ค่าอะไร → **ห้ามใช้ `importance=` เป็นเกณฑ์ผ่าน/ไม่ผ่าน** เก็บเป็นสัญญาณดิบเท่านั้น (https://developer.android.com/reference/android/app/ActivityManager.RunningAppProcessInfo)
- **เครื่องทดสอบใช้ file-based encryption หรือไม่** — ยังไม่ได้ตรวจ ดูข้อ 5
- **`PendingIntent` scan รอดข้ามการรีบูตหรือไม่** — เอกสาร `BluetoothLeScanner` ไม่ระบุ ข้อสรุปที่ ADR-14 ใช้ ("ไม่รอด") มาจากการทดสอบบนเครื่องจริง ไม่ใช่จากเอกสาร
- **ข้อความคำต่อคำของ `BluetoothAdapter.ACTION_STATE_CHANGED` และ `isEnabled()`** — พยายามดึงหน้า `https://developer.android.com/reference/android/bluetooth/BluetoothAdapter` (ทั้งรุ่น Java และ Kotlin) แล้ว **ได้แต่หน้าสารบัญ ไม่ได้เนื้อหาของสมาชิกคลาส** จึง **ยังไม่ได้ยืนยันคำต่อคำ** · ข้อสรุปในข้อ 9 ไม่ได้พึ่งข้อความจากหน้านี้เลย (พึ่งหน้ารายการข้อยกเว้นกับหน้า background execution limits) แต่ถ้าจะอ้างรายละเอียดของ constant นี้ต้องไปดึงมาก่อน
- **`LocationManager.isLocationEnabled()` มีตั้งแต่ API ไหน และต้องมีสิทธิ์อะไร** — `SENSING.md` เสนอให้ใช้ตรวจว่า location service ปิดอยู่หรือไม่ **ยังไม่ได้ยืนยันกับเอกสาร**
- **เมื่อ Bluetooth ถูกปิด ระบบยกเลิกการลงทะเบียน `startScan(..., PendingIntent)` ทิ้งหรือแค่หยุดส่งผล** — ต่างกันมากสำหรับเรา (ถ้ายกเลิกทิ้ง ต้องลงทะเบียนใหม่เองตอน Bluetooth กลับมา ไม่ใช่แค่รอ) **หาแหล่งอ้างอิงไม่ได้**
