# example

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## คูลดาวน์แจ้งเตือนความใกล้ (ชั้นที่ 2) — ค่าสินค้า 24 ชั่วโมง · example ตั้ง 30 นาที

> ⚠️ **แก้ 17 ก.ย. 2026 (ADR-25 §8):** หัวข้อนี้เคยชื่อ "— 30 นาทีต่อบีคอน" ซึ่งทำให้
> เข้าใจผิดว่า 30 นาทีเป็นค่าเดียวที่มี · ของจริงตอนนี้ **ค่าเริ่มต้นของสินค้าคือ
> 24 ชั่วโมง** (`ExampleProximityWatcher.DEFAULT_LONG_COOLDOWN_MILLIS` /
> `AppDelegate.productDefaultLongCooldownSeconds`) ส่วน **30 นาทีเป็นค่าที่ example
> override ไว้เพื่อการทดสอบ** ณ จุดประกอบ (`ExampleApplication.onCreate()` /
> `AppDelegate.didFinishLaunchingWithOptions`) เพื่อให้เห็นใบที่สองระหว่างรอบทดสอบ
> ภาคสนามได้จริงโดยไม่ต้องรอทั้งวัน — **ถ้าคุณนำโค้ดนี้ไปใช้ต่อ ให้ลบ override นั้นออก
> แล้วจะได้ค่าสินค้า 24 ชั่วโมงอัตโนมัติ**
>
> **ทำไมค่าสินค้าถึงยาวถึง 24 ชั่วโมง:** คูลดาวน์ต้องยาวกว่าการมาร้านหนึ่งครั้ง เพราะ
> สัญญาณ `exit` เชื่อเวลาไม่ได้ทั้งสองแพลตฟอร์ม (ADR-14 §4 · ADR-15 · ADR-11 หัวข้อ 2)
> ถ้าคูลดาวน์สั้นกว่าเวลาที่ลูกค้าอยู่ในร้าน ลูกค้าจะโดนเด้งซ้ำระหว่างเดินอยู่ในร้าน
> เดียวกัน · **ข้อแลกเปลี่ยนที่ยอมรับไว้:** ลูกค้าที่มาร้านสองครั้งจริงในวันเดียวกัน
> จะไม่ได้แจ้งเตือนครั้งที่สอง (ADR-25 §8.5 เขียนข้อเสียไว้ครบ)

## notification ชั้นที่ 1 (`enter`/`exit`) — **ปิดโดยค่าเริ่มต้น** (เพิ่ม 17 ก.ย. 2026)

แอปตัวอย่างนี้ **ไม่ยิงแจ้งเตือนตอนเข้า/ออก region อีกต่อไป** (ADR-25 §9) — เปิดกลับได้
ด้วย flag เดียวต่อแพลตฟอร์ม: `LAYER1_NOTIFICATIONS_ENABLED` (`ExampleApplication.kt`)
หรือ `layer1NotificationsEnabled` (`AppDelegate.swift`)

**เหตุผล — ตัวเลขจากไฟล์หลักฐานจริง** (`docs/test-data/2026-09-17_android_cooldown_desk_redmi.log`):
รอบวางเครื่องนิ่งบนโต๊ะ 4 ชม. 36 นาที ชั้นที่ 1 ยิงจริง **72 ใบ** โดย**ไม่มีใบไหนถูกกันเลย**
(ชั้นที่ 1 ไม่มีคูลดาวน์ใด ๆ) เทียบกับชั้นที่ 2 ที่เหลือ 18 ใบเพราะมีคูลดาวน์

⚠️ **บรรทัดหลักฐานยังถูกเขียนเสมอ** ด้วย `posted=false reason=disabled` — **ไม่ใช่เงียบ
หายไปทั้งบรรทัด** เพราะ "ไม่มีบรรทัด" ต้องไม่ถูกอ่านเป็นหลักฐานว่าเงื่อนไขไม่เคยเข้า
(ADR-20 §12.2/§12.5.3) · สถานะการทดสอบอยู่ที่ `docs/test-checklists/android_background_scanning.md`
ข้อ 14 และ `docs/test-checklists/ios_broadcast_scanning.md` ข้อ 22.1

## รายละเอียดคูลดาวน์ชั้นที่ 2

แอปตัวอย่างนี้กันแจ้งเตือนความใกล้ (proximity, ADR-20/21/22) ซ้ำด้วยคูลดาวน์ **ที่สอง**
อายุ **30 นาทีต่อบีคอน** ซ้อนอยู่เหนือคูลดาวน์เดิม 60 วินาที (ไม่ได้แทนที่) ทั้งฝั่ง
Android (`ExampleProximityWatcher.kt`) และ iOS (`AppDelegate.swift`) — เก็บสถานะไว้คนละ
ไฟล์จากทุก store ที่เส้นทาง "ล้าง state ตอนเงียบ/ออกนอกระยะ" แก้ไข โดยตั้งใจ เพราะปัญหาที่
มันแก้คือ transition แรกหลัง state ถูกล้าง (เช่นตอน `reason=stale`) ถูกนับเป็น "เดินเข้ามา
ใกล้ใหม่" ทำให้ยิงแจ้งเตือนซ้ำถี่กว่าที่ควร (พบจริง 26 ใบใน 64.9 นาทีตอนเครื่องวางนิ่งบน
โต๊ะ) **ค่า 30 นาทีนี้เลือกจากการอ่านข้อมูลรอบทดสอบที่พบปัญหาเท่านั้น ยังไม่ได้ calibrate
กับข้อมูลการกระจายของช่วงเงียบจริง** — รายละเอียดเต็มและเหตุผลอยู่ที่ ADR-25 §2 ใน
`ARCHITECTURE.md` (⚠️ ย่อหน้านี้เป็นบันทึกเหตุผลของ **ค่า 30 นาที** ตอนที่มันยังเป็นค่า
เดียวที่มี — ยังใช้อ่านประวัติได้ แต่การตัดสินปัจจุบันเรื่องค่าสินค้า 24 ชั่วโมงอยู่ที่
**ADR-25 §8** และการกระจายของช่วงเงียบจริงที่ย่อหน้านี้บอกว่า "ยังไม่มี" ตอนนี้**มีแล้ว**
ที่ **ADR-20 §12.6.2** — 60-94 วินาที จาก 59 บรรทัด `reason=stale`)
