# Sources: RSSI → distance — log-distance path loss model

วันที่ค้นคว้า: 8 กันยายน 2026

ไฟล์นี้มีไว้รองรับ ARCHITECTURE.md ADR-19 (`ProximityGate`) — เฉพาะส่วนที่คำนวณ
ระยะทางโดยประมาณจาก `rssi` + `ibeaconTxPower` บนฝั่ง Android (และฝั่ง iOS เมื่อ
`proximity` ของ Apple เป็น `null`) **นี่คือแบบจำลองทางฟิสิกส์วิทยุทั่วไป ไม่ใช่สเปกของ
ยี่ห้อใด** จึงไม่มี GATT UUID/SDK ให้ตรวจแบบไฟล์ `docs/sources/<vendor>.md` อื่น — โครง
ไฟล์นี้จึงต่างจากไฟล์ vendor ปกติ

⚠️ **ข้อจำกัดของการค้นคว้ารอบนี้ที่ต้องบอกตรง ๆ ก่อนอ่านต่อ:** ตำราต้นทาง (Rappaport,
*Wireless Communications: Principles and Practice*) เป็นหนังสือที่ต้องซื้อ/ยืมจาก
ห้องสมุด — พยายามเปิดอ่านฉบับเต็มผ่าน O'Reilly Online Learning, academia.edu, และ
ScienceDirect แล้วทั้งสามแหล่ง **ตอบ HTTP 403 (ต้อง login/สมัครสมาชิก)** จึง **ไม่ได้
อ่านเนื้อหาต้นฉบับของ Rappaport โดยตรง** สิ่งที่ยืนยันได้ในไฟล์นี้มาจากเอกสารการสอน
ระดับมหาวิทยาลัยที่เปิดเผยต่อสาธารณะและ**อ้างอิงกลับไปที่เลขหัวข้อของ Rappaport ตรง ๆ**
(ดูหัวข้อ 1) ซึ่งถือว่าเป็นแหล่งรอง (secondary) ไม่ใช่การอ่านตำราต้นฉบับเอง — ต้องบันทึก
ไว้ตรงนี้เพราะเป็นข้อจำกัดจริงของการค้นคว้ารอบนี้ ไม่ใช่การยืนยันระดับเดียวกับที่ตรวจ
ซอร์สโค้ด SDK ยี่ห้ออื่นได้โดยตรง

---

## 1. สมการ log-distance path loss model — ✅ ยืนยันแล้ว (แหล่งรอง, อ้างเลขหัวข้อของ Rappaport ตรง)

แหล่ง: N. Patwari (University of Utah, ECE 5325/6325 "Wireless Communication Systems",
Lecture 5, Spring 2010) — เอกสารประกอบการสอนที่เปิดเผยสาธารณะ —
https://span.ece.utah.edu/uploads/lecture05.pdf

> "2.1 Log Distance Path Loss — **This is 4.11.3 in Rappaport.** This is synonymous
> with what I call 'power decay' above. Actually, it is the simplest of the models,
> and makes a big step towards better representation of actual large-scale path loss.
> In the log-distance path loss model, we can simply write the received power as a
> modification of (4) as
>
> Pr(dBm) = Π0(dBm) − 10n log10(d/d0)              (6)
>
> where Π0(dBm) is still given by the Friis equation, but now the Lp(dB) term has
> changed to include a factor 10n instead of 20. Typically d0 is taken to be on the
> edge of near-field and far-field, say 1 meter for indoor propagation, and 10-100m
> for outdoor propagation."

> "Power decay: Lp will be proportional to 1/d^n, for some path loss exponent n. In
> free space, it was proportional to 1/d^2, so this just lets n adjust to the
> particular environment. **Typically, n ranges between 1.6 and 6, according to
> Rappaport.** From my experience, I've seen n between 1.7 and 5."

**สิ่งที่ยืนยันได้จากแหล่งนี้:** ตัวสมการ, ชื่อหัวข้อ ("Log Distance Path Loss"), เลข
หัวข้ออ้างอิงตรงในตำรา (4.11.3 สำหรับโมเดลนี้, 4.11.4 สำหรับ multiple breakpoint model),
และช่วงค่า n ที่ระบุว่า Rappaport ให้ไว้ (1.6–6)

**สิ่งที่ยัง _ไม่_ ยืนยันจากแหล่งนี้:** ตัวเลขที่แน่นอนของตาราง "path loss exponent ตาม
ประเภทสภาพแวดล้อม" (เช่น free space / in-building line-of-sight / obstructed) ที่มักถูก
อ้างถึงว่าเป็น "Table 4.2" ของ Rappaport — ค้นด้วย web search หลายรอบ (ScienceDirect,
ResearchGate, Google Books snippet) แต่ **ไม่มีแหล่งไหนที่เปิดให้ดูตารางฉบับเต็มพร้อม
ตัวเลขต่อแถวได้จริงในรอบนี้** บันทึกไว้ในหัวข้อ "ไม่พบ/ไม่ยืนยัน" ด้านล่าง — ห้ามเดา
ตัวเลขรายแถวของตารางนี้

**ตัวอย่างค่า n จากการวัดจริงที่แหล่งนี้ทำเอง (ไม่ใช่ของเราเอง แต่แสดงความผันผวนของ n
แม้ในสภาพแวดล้อม "office" คล้ายกัน):**

| การวัด | n ที่ได้ | ส่วนเบี่ยงเบนมาตรฐาน σ (dB) |
|---|---|---|
| 2.4 GHz, office area (รูปที่ 1 ของแหล่ง) | 2.30 | 3.92 |
| 925 MHz, office area (รูปที่ 2 ของแหล่ง) | 2.98 | 7.38 |

การที่สอง office คนละแห่งได้ n ต่างกัน (2.30 vs 2.98) และมี σ สูงถึง ~4–7 dB คือ
หลักฐานตรงจากแหล่งนี้เองว่า **n ไม่ใช่ค่าคงที่สากล ต้อง calibrate ต่อสถานที่จริง**
(ใช้สนับสนุนหัวข้อ 3 ของ ADR-19 เรื่องข้อจำกัดของโมเดล)

---

## 2. สูตรที่ใช้ในวงการ BLE/iBeacon (จัดรูปใหม่ด้วย `TxPower`) — ⚠️ ยืนยันแค่บางส่วน

รูปแบบที่ใช้กันทั่วไปในเอกสาร/paper เรื่อง BLE indoor positioning คือ

```
d = 10 ^ ((TxPower − RSSI) / (10 × n))
```

**สิ่งที่ยืนยันได้:** นี่คือการจัดสมการ (6) ของหัวข้อ 1 ใหม่โดยตรง — ตั้ง `d0 = 1m`
แล้วแทน `Π0(dBm)` (ค่ากำลังรับที่ระยะอ้างอิง) ด้วย `TxPower` (ค่าที่ผู้ผลิต beacon
calibrate ไว้ล่วงหน้าว่า "RSSI ที่ควรวัดได้เมื่ออยู่ห่าง 1 เมตร") แล้วแก้สมการกลับเพื่อ
หา `d` แทนที่จะหา `Pr` — เป็นพีชคณิตตรงไปตรงมาจากสมการ (6) ที่ยืนยันแล้วในหัวข้อ 1
(ตั้ง `RSSI = Pr(dBm)`, `TxPower = Π0(dBm)`, `d0 = 1`, แก้หา `d`)

**สิ่งที่ _ไม่_ ยืนยัน:** คำว่า **"TxPower" ไม่ใช่ศัพท์ที่มาจาก Rappaport** — เอกสารของ
Rappaport (ตามแหล่งรองในหัวข้อ 1) ใช้ `Π0(dBm)` ไม่ใช่ `TxPower` — ศัพท์ `TxPower`
เป็นแบบแผนของวงการ iBeacon/AltBeacon ที่นำโมเดลฟิสิกส์นี้มาปรับใช้ **รอบนี้ยังไม่ได้
ตรวจซอร์สโค้ด AltBeacon หรือเอกสาร iBeacon อย่างเป็นทางการของ Apple เพื่อยืนยันว่าใคร
เป็นคน "บัญญัติ" การจัดรูปสมการนี้ก่อน** จึงบันทึกไว้แค่ว่า **เป็นการจัดรูปสมการที่พบทั่วไป
ในเอกสารวิชาการเรื่อง BLE indoor positioning ที่ค้นเจอ ไม่ใช่สูตรที่มาจากตำราของ
Rappaport ตรง ๆ** — สอดคล้องกับชื่อฟิลด์ `ibeaconTxPower` ที่มีอยู่แล้วในโค้ดของเรา
(`beacon_advertisement.dart:120`, คอมเมนต์ "measured power @ 1m, signed 8-bit dBm")
ซึ่งเป็นชื่อที่มาจากสเปก iBeacon ไม่ใช่จาก Rappaport เช่นกัน

**ตัวอย่าง paper ที่ใช้สูตรรูปแบบเดียวกันนี้กับ BLE/beacon โดยตรง (พบผ่าน web search,
ยังไม่ได้เปิดอ่านฉบับเต็ม — บันทึกไว้เป็นหลักฐานว่ารูปแบบสมการนี้เป็นที่ยอมรับในวงการ
ไม่ใช่สิ่งที่เราคิดขึ้นเอง):**
- "Indoor Location Estimation of Wireless Devices Using the Log-Distance Path Loss
  Model" — IEEE Xplore, https://ieeexplore.ieee.org/document/8650295 (เปิดอ่านได้แค่
  บทคัดย่อ, ตัวบทความปิด)
- "Smart Parking System Based on Bluetooth Low Energy Beacons with Particle
  Filtering" — arXiv, https://arxiv.org/pdf/2001.07266 (พยายามดึงเนื้อหาเต็มแล้วแต่
  ไฟล์เป็น PDF ที่ประกอบด้วยรูปภาพ/สตรีมอัดข้อมูลเป็นส่วนใหญ่ ดึงข้อความสมการไม่สำเร็จ
  ในรอบนี้ — เห็นแค่ชื่อเรื่องและบทคัดย่อจาก search)

---

## 3. ทำไมแยกแยะระยะใกล้ได้ดีกว่าระยะไกล — คำนวณจากสมการที่ยืนยันแล้วในหัวข้อ 1 (ไม่ใช่ผลทดสอบ)

⚠️ ตัวเลขในหัวข้อนี้เป็น **ผลคำนวณทางคณิตศาสตร์จากสมการ (6) ที่ยืนยันแหล่งที่มาแล้ว**
ไม่ใช่ผลวัดจากอุปกรณ์จริงของเรา และไม่ใช่สถานะการทดสอบ — ไม่ละเมิดกฎ CONTRIBUTING ข้อ 4
เรื่องห้ามรายงานสถานะทดสอบใน ADR/docs เพราะไม่มีการอ้างว่า "verified"/"observed" ใด ๆ
นี่คือคณิตศาสตร์ล้วน ๆ ที่ตรวจทานซ้ำได้ด้วยเครื่องคิดเลข

จากสมการ (6): ผลต่างของ RSSI ระหว่างระยะ d1 กับ d2 คือ `ΔRSSI = 10n × log10(d2/d1)`
(ไม่ขึ้นกับ `Π0`/`TxPower` เลย เพราะตัดกันหมดเมื่อลบสมการสองสมการที่ `d0` เดียวกัน)

| คู่ระยะ | log10(d2/d1) | ΔRSSI เมื่อ n=2 (dB) | เทียบกับ σ ที่วัดได้จริงในหัวข้อ 1 (~4–7 dB) |
|---|---|---|---|
| 0.5m → 3m | log10(6) ≈ 0.778 | **≈ 15.6 dB** | มากกว่า σ เกิน 2 เท่า — สัญญาณต่างกันชัดเจนพอจะแยกได้ |
| 3m → 10m | log10(3.33) ≈ 0.523 | **≈ 10.5 dB** | มากกว่า σ แต่ไม่มาก — พอแยกได้แต่ก้ำกึ่งกว่าคู่บน |
| 9m → 11m | log10(1.222) ≈ 0.087 | **≈ 1.7 dB** | **น้อยกว่า σ ที่วัดได้จริง** — จมอยู่ใต้ noise ของสัญญาณเอง แยกไม่ได้ |

**ข้อสรุปเชิงคณิตศาสตร์ (ไม่ใช่ข้อสรุปเชิงประสบการณ์):** เพราะโมเดลเป็นความสัมพันธ์แบบ
**ลอการิทึม** ผลต่าง RSSI ระหว่างสองระยะที่ *อัตราส่วน* ต่างกันมาก (0.5m→3m คือ 6 เท่า)
จะมากกว่าสองระยะที่ *ผลต่างสัมบูรณ์* เท่ากันแต่อัตราส่วนใกล้ 1 (9m→11m คือแค่ 1.22 เท่า)
เสมอ — นี่คือเหตุผลเชิงโครงสร้างที่ BLE proximity แยกระยะใกล้ได้ดีกว่าระยะไกลโดยธรรมชาติ
ของโมเดลเอง ไม่ใช่เพราะฮาร์ดแวร์ตัวใดตัวหนึ่งดีหรือแย่กว่ากัน — และเป็นเหตุผลที่ทำให้การ
ขาย "แยกได้ละเอียดระดับเมตรที่ระยะไกล" เป็นการขายเกินจริงตามโครงสร้างของฟิสิกส์เอง

---

## ไม่พบ / ไม่ยืนยัน

- **เนื้อหาต้นฉบับของ Rappaport โดยตรง** — ทุกแหล่งที่ลองเปิด (O'Reilly Online
  Learning, academia.edu PDF, ScienceDirect) ตอบ HTTP 403 หรือให้ไฟล์ที่ดึงข้อความ
  ไม่ได้ (PDF แบบ image/compressed stream) — สิ่งที่ยืนยันได้ทั้งหมดในไฟล์นี้มาจาก
  แหล่งรอง (เอกสารการสอนของมหาวิทยาลัย) ที่อ้างเลขหัวข้อของ Rappaport ตรง ๆ เท่านั้น
- **ตาราง "path loss exponent ตามประเภทสภาพแวดล้อม" ฉบับเต็มของ Rappaport (มักถูก
  อ้างถึงในชื่อ "Table 4.2")** — หาแหล่งที่เปิดให้ดูตัวเลขครบทุกแถวไม่ได้ในรอบนี้ —
  **ห้ามใช้ตัวเลขต่อแถวของตารางนี้จนกว่าจะเปิดตำราจริงได้** (ยืนยันได้แค่ช่วงกว้าง 1.6–6
  จากแหล่งรองในหัวข้อ 1)
- **ที่มาที่แน่ชัดของการจัดรูปสมการด้วย `TxPower` ในวงการ iBeacon/AltBeacon** — ยังไม่ได้
  ตรวจซอร์ส AltBeacon หรือสเปก iBeacon ของ Apple โดยตรงในรอบนี้ (ดูหัวข้อ 2)
- **ค่า n เฉพาะของสภาพแวดล้อมร้านค้าปลีก (ชั้นวางของโลหะ, คนเดินพลุกพล่าน)** — ไม่มี
  paper ใดที่ค้นเจอในรอบนี้ระบุค่าเฉพาะเจาะจงสำหรับสภาพแวดล้อม retail/superstore —
  ต้องวัดเองในสาขาจริงตามที่ ADR-19 ระบุ ห้ามสมมติค่าจาก environment อื่น (office/
  factory) มาใช้แทน

## แหล่งอ้างอิงทั้งหมดที่เปิดดูจริง

- N. Patwari, ECE 5325/6325 Lecture 5 (University of Utah, เปิดเผยสาธารณะ) —
  https://span.ece.utah.edu/uploads/lecture05.pdf (อ้าง Rappaport §4.11.3, §4.11.4 ตรง)
- (พยายามเปิดแต่ถูกบล็อก 403 — บันทึกไว้เพื่อไม่ให้มีใครลองซ้ำโดยคิดว่ายังไม่เคยลอง)
  https://www.oreilly.com/library/view/wireless-communications-principles/0130422320/ch04.html ,
  https://www.academia.edu/44010551/Rappaport_Wireless_Communications_Principles_and_Practice_ISBN ,
  https://www.sciencedirect.com/topics/computer-science/path-loss-model
- อ้างอิง citation entry (ไม่ใช่เนื้อหาเต็ม): Rappaport, T.S. (2002) *Wireless
  Communications: Principles and Practice*, 2nd Edition, Prentice-Hall, Upper Saddle
  River — พบรายการอ้างอิงที่ระบุช่วงหน้า 161–166 สำหรับเนื้อหา propagation/path loss
  ของบทที่ 4 ผ่าน https://www.scirp.org/reference/referencespapers?referenceid=1687444
  (หน้านี้ล่มระหว่างพยายามเปิดซ้ำเพื่อยืนยัน — บันทึกเป็นข้อมูลที่เจอจาก search snippet
  เท่านั้น ยังไม่ได้เปิดหน้าเต็มยืนยัน)
- ตัวอย่าง paper วงการ BLE ที่ใช้สูตรรูปแบบเดียวกัน (เห็นแค่บทคัดย่อ) —
  https://ieeexplore.ieee.org/document/8650295 ,
  https://arxiv.org/pdf/2001.07266
