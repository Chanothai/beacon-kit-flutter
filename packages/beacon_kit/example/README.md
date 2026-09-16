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

## คูลดาวน์แจ้งเตือนความใกล้ (ชั้นที่ 2) — 30 นาทีต่อบีคอน

แอปตัวอย่างนี้กันแจ้งเตือนความใกล้ (proximity, ADR-20/21/22) ซ้ำด้วยคูลดาวน์ **ที่สอง**
อายุ **30 นาทีต่อบีคอน** ซ้อนอยู่เหนือคูลดาวน์เดิม 60 วินาที (ไม่ได้แทนที่) ทั้งฝั่ง
Android (`ExampleProximityWatcher.kt`) และ iOS (`AppDelegate.swift`) — เก็บสถานะไว้คนละ
ไฟล์จากทุก store ที่เส้นทาง "ล้าง state ตอนเงียบ/ออกนอกระยะ" แก้ไข โดยตั้งใจ เพราะปัญหาที่
มันแก้คือ transition แรกหลัง state ถูกล้าง (เช่นตอน `reason=stale`) ถูกนับเป็น "เดินเข้ามา
ใกล้ใหม่" ทำให้ยิงแจ้งเตือนซ้ำถี่กว่าที่ควร (พบจริง 26 ใบใน 64.9 นาทีตอนเครื่องวางนิ่งบน
โต๊ะ) **ค่า 30 นาทีนี้เลือกจากการอ่านข้อมูลรอบทดสอบที่พบปัญหาเท่านั้น ยังไม่ได้ calibrate
กับข้อมูลการกระจายของช่วงเงียบจริง** — รายละเอียดเต็มและเหตุผลอยู่ที่ ADR-25 §2 ใน
`ARCHITECTURE.md`
