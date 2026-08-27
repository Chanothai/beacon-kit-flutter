# Sources: KKM K9P (kkm_k9p)

วันที่ค้นคว้า: 27 สิงหาคม 2026 — สรุปย่อจาก "KBeacon K9P Playbook" (เอกสารเต็ม + แหล่งอ้างอิงทั้งหมด: https://claude.ai/code/artifact/cf97993a-78f3-44d3-99cd-d3154dbd251d)

## Dependency & License
- Android: `com.kkmcn.kbeaconlib2:kbeaconlib2` — README repo หลักระบุ `1.3.1`, README demo repo ระบุ `1.3.3` (ไม่ตรงกัน ให้เช็คเวอร์ชันล่าสุดจริงก่อนใช้)
- iOS: CocoaPods `pod 'kbeaconlib2', '1.2.1'`
- License: MIT (Copyright (c) 2021 hogen) — ทั้ง Android และ iOS repo

## GATT UUID (verified — Android + iOS + fetch ตรงด้วยตนเอง)
| Constant | UUID |
|---|---|
| KB_CFG_SERVICE_UUID | 0000FEA0-0000-1000-8000-00805f9b34fb |
| KB_WRITE_CHAR_UUID | 0000FEA1-0000-1000-8000-00805f9b34fb |
| KB_NTF_CHAR_UUID | 0000FEA2-0000-1000-8000-00805f9b34fb |
| KB_IND_CHAR_UUID | 0000FEA3-0000-1000-8000-00805f9b34fb |
| Eddystone service | 0000FEAA-0000-1000-8000-00805f9b34fb |
| KKM manufacturer ID | 0x0A53 |

## Auth flow (verified)
Password 8–16 ตัวอักษร, default จากโรงงาน `"0000000000000000"` (16 เลข 0) — **ต้องเปลี่ยนตอน provision** กลไก: MD5 challenge-response 2 รอบ ผ่าน write/notify characteristic ข้างต้น

## ไม่พบ / ไม่ยืนยัน
- ไม่มีการระบุ "K9P" ตรง ๆ ในซอร์ส SDK — ระบุรุ่นแบบ generic ผ่าน `getModel()` ที่ runtime
- ไม่มีเอกสาร protocol/API reference สาธารณะบน kkmcn.com (ลิงก์ documentation เป็น 404)
- เลขรุ่นย่อยของ chipset nRF52 ไม่ระบุ (แค่ "series")
- URL เซิร์ฟเวอร์เฟิร์มแวร์ยืนยันเฉพาะฝั่ง Android (`download.kkmiot.com`), ฝั่ง iOS ยังไม่ยืนยัน

## แหล่งอ้างอิง
ดูรายการเต็ม (20+ URL รวม raw source file ทุกไฟล์ที่ verified) ในเอกสาร "KBeacon K9P Playbook": https://claude.ai/code/artifact/cf97993a-78f3-44d3-99cd-d3154dbd251d
