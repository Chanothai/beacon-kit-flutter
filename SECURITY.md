# Security

## Accepted risk: iBeacon spoof/clone

มาตรฐาน iBeacon เป็น broadcast แบบ plaintext — payload (UUID + major + minor +
txPower) ไม่มี field สำหรับ signature, nonce, หรือกลไก authentication ใด ๆ เลย
อุปกรณ์ BLE ทั่วไปสามารถดักอ่านค่าเหล่านี้แล้ว broadcast ซ้ำ (spoof/clone) ได้ทันที
— **นี่คือคุณสมบัติของมาตรฐาน iBeacon เอง ไม่ใช่ช่องโหว่จากการ implement ของ
`beacon_kit`** (รายละเอียดเต็มอยู่ที่
[ARCHITECTURE.md ADR-5](ARCHITECTURE.md#adr-5-bigc-id-scheme-สำหรับ-multi-vendor-provisioning-เพิ่ม-28-สค-2026))

การใช้ UUID เดียวกันทั้งบริษัทตาม ADR-5 (จำเป็นเพราะเพดาน 20 region ของ iOS)
ทำให้การรั่วของ UUID เดียวนี้กระทบทั้งฟลีตพร้อมกัน — เป็น trade-off ที่ยอมรับไว้
ตั้งแต่ต้น ไม่ใช่ผลข้างเคียงที่พบทีหลัง **คำแนะนำสำหรับ host app:** อย่าใช้ตำแหน่ง
beacon เป็นหลักฐานเดียวสำหรับการตัดสินใจที่มีมูลค่าสูง (เช่น ผูกกับธุรกรรม/สิทธิ
ประโยชน์) ให้ backend ตรวจสอบ context อื่นประกอบเสมอ

## Password ค่าโรงงานของ K9P

อุปกรณ์ K9P ที่ใช้เป็นบีคอนอ้างอิงมีกลไก auth (MD5 challenge-response) ที่ป้องกัน
การเขียนค่าใหม่ผ่าน GATT แต่ **password เริ่มต้นจากโรงงานเป็นค่าเดียวกันทุกเครื่อง**
(`docs/sources/kkm_k9p.md:21`) — **ต้องเปลี่ยน password ก่อนนำอุปกรณ์ไปใช้งานจริง
(pilot/production) เสมอ** เครื่องที่ยังใช้ password ค่าโรงงานเท่ากับไม่มีการป้องกัน
การเขียนค่าใหม่เลยในทางปฏิบัติ

## ข้อมูลตำแหน่ง = PDPA

ข้อมูลที่ SDK ส่งให้ (region ที่อยู่ใกล้, ระยะโดยประมาณ) เข้าข่ายข้อมูลส่วนบุคคล
ตามกฎหมายคุ้มครองข้อมูลส่วนบุคคล — ไม่มีเอกสาร PDPA เฉพาะของโปรเจกต์นี้ในตอนนี้
และไม่ใช่ขอบเขตของ SDK repo นี้ที่จะกำหนดกลไก consent host app ต้องปรึกษาทีม
กฎหมาย/compliance ของบริษัทเองก่อนเก็บหรือส่งข้อมูลตำแหน่งขึ้น server จริง

## ช่องทางรายงานช่องโหว่

**TODO: ทีม BigC ต้องกำหนดช่องทางรายงานช่องโหว่** (ยังไม่กำหนด ณ วันที่เขียน)

## สิ่งที่ SDK ไม่ทำ

- ไม่ส่ง network เอง — `beacon_kit` ไม่มี dependency สำหรับเรียก HTTP/network
  ใด ๆ ทั้งสิ้น
- ไม่ทำ GATT/authentication เอง — `connect()` throw `UnsupportedError` ทันที
  (broadcast-only)
- ไม่เก็บ consent/PDPA ให้ — เป็นหน้าที่ host app ทั้งหมด (ดู
  [`docs/integration-guide.md`](docs/integration-guide.md))
