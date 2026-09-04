package com.beaconkit.example

import java.util.TimeZone
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * เทสต์รูปแบบบรรทัดของไฟล์หลักฐานฝั่ง Android
 *
 * **คู่แฝดของ `testLogLineHasSixTabSeparatedColumnsInOrder` ใน RunnerTests.swift**
 * — ทั้งสองไฟล์ล็อกรูปแบบเดียวกันไว้คนละฝั่ง ถ้าฝั่งใดฝั่งหนึ่งเปลี่ยนโดยไม่แก้
 * อีกฝั่ง เทสต์จะไม่จับได้ (คนละ test runner) แต่ **ตัวอ่านฝั่ง Dart จะจับได้**
 * เพราะมันอ่านไฟล์จากทั้งสองแพลตฟอร์มด้วยโค้ดชุดเดียว
 * (`example/test/evidence_log_line_test.dart`)
 *
 * เหตุผลที่ต้องล็อก: ไฟล์นี้คือหลักฐานเดียวของรอบทดสอบที่เกิดตอนไม่มีใครดูหน้าจอ
 * ถ้ารูปแบบเพี้ยน ข้อมูลที่เก็บมาทั้งคืนจะอ่านไม่ออก และไม่มีทางเก็บซ้ำได้
 */
class BackgroundEvidenceLogTest {

    private lateinit var originalTimeZone: TimeZone

    @BeforeTest
    fun setUp() {
        originalTimeZone = TimeZone.getDefault()
    }

    @AfterTest
    fun tearDown() {
        TimeZone.setDefault(originalTimeZone)
    }

    @Test
    fun `บรรทัดมี 6 คอลัมน์คั่นด้วย TAB ตามลำดับที่ฝั่ง Dart อ่าน`() {
        val line = BackgroundEvidenceLog.line(
            timestampMillis = 0L,
            processId = "a1b2c3d4",
            event = "enter",
            regionIdentifier = "k9p-default",
            conclusion = "relaunchedFromTerminated",
            rawSignals = "everForeground=false uptime=0.4s",
        )

        val columns = line.split("\t")
        assertEquals(6, columns.size)
        assertEquals("a1b2c3d4", columns[1])
        assertEquals("enter", columns[2])
        assertEquals("k9p-default", columns[3])
        assertEquals("relaunchedFromTerminated", columns[4])
        assertEquals("everForeground=false uptime=0.4s", columns[5])
    }

    /**
     * timestamp ต้องเป็นเวลา **local พร้อม offset** และเป็นปฏิทินเกรกอเรียนเสมอ
     *
     * เครื่องทดสอบเป็น MIUI ซึ่งตั้งปฏิทินพุทธได้ง่ายมาก ถ้าหลุดเป็นปี 2569
     * การเทียบเวลากับ log ฝั่ง iOS จะทำไม่ได้เลย — และจะรู้ตัวตอนวิเคราะห์ผล
     * หลังเก็บข้อมูลเสร็จแล้ว ซึ่งสายเกินไป
     */
    @Test
    fun `timestamp เป็นเวลา local พร้อม offset และเป็นปฏิทินเกรกอเรียน`() {
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Bangkok"))

        val stamp = BackgroundEvidenceLog.iso8601WithOffset(0L)

        assertEquals("1970-01-01T07:00:00.000+07:00", stamp)
    }

    /**
     * ต้องใช้รูปแบบ offset แบบมีทวิภาค (`+07:00`) ให้ตรงกับ `XXXXX` ของ
     * `DateFormatter` ฝั่ง iOS — `DateTime.parse` ฝั่ง Dart อ่านได้ทั้งสองแบบ แต่
     * regex ที่ดึง offset ใน `tool/analyze_region_log.dart` คาดหวังแบบมีทวิภาค
     */
    @Test
    fun `offset ใช้รูปแบบมีทวิภาคเหมือนฝั่ง iOS`() {
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Bangkok"))

        assertTrue(
            BackgroundEvidenceLog.iso8601WithOffset(0L).endsWith("+07:00"),
            "ต้องเป็น +07:00 ไม่ใช่ +0700",
        )
    }

    /**
     * **เทสต์ที่จับบั๊กจริงได้เมื่อ 1 ก.ย. 2026** — เขตเวลาที่เปลี่ยนระหว่าง process
     * ต้องมีผลกับบรรทัดถัดไปทันที
     *
     * เดิม `SimpleDateFormat` ถูก cache ไว้ใน `ThreadLocal` และจับ default TimeZone
     * ไว้ตั้งแต่ตอน construct → บรรทัดที่เขียนหลังเขตเวลาเปลี่ยนยังใช้ offset เดิม
     * และเธรดต่างกันที่สร้าง formatter คนละเวลาจะให้ offset ไม่ตรงกันในไฟล์เดียวกัน
     *
     * **สองเทสต์ข้างบนจับไม่ได้** เพราะถ้าเครื่องที่รันตั้งเป็น `Asia/Bangkok` อยู่
     * แล้ว (เครื่องพัฒนา) ค่าที่ติดมาตอนสร้างก็บังเอิญถูกเสมอ — และถ้าเป็น UTC
     * (CI runner) ผลจะขึ้นกับว่าเทสต์ตัวไหนรันก่อนจนไป warm formatter ไว้ ซึ่งเป็น
     * ความเปราะที่ตัวเทสต์เองก็ผิดด้วย
     *
     * ตัวนี้ format **สองครั้งในเทสต์เดียว** ภายใต้เขตเวลาคนละอัน จึงไม่ขึ้นกับ
     * ลำดับการรันและไม่ขึ้นกับเขตเวลาของเครื่องที่รัน
     */
    @Test
    fun `เขตเวลาที่เปลี่ยนระหว่าง process มีผลกับบรรทัดถัดไปทันที`() {
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Bangkok"))
        val bangkok = BackgroundEvidenceLog.iso8601WithOffset(0L)

        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        val utc = BackgroundEvidenceLog.iso8601WithOffset(0L)

        assertEquals("1970-01-01T07:00:00.000+07:00", bangkok)
        assertEquals("1970-01-01T00:00:00.000Z", utc)
    }

    @Test
    fun `processId เป็นเลขฐานสิบหกพิมพ์เล็ก 8 ตัว และคงที่ตลอด process`() {
        val first = BackgroundEvidenceLog.processId
        val second = BackgroundEvidenceLog.processId

        assertEquals(first, second, "ถ้าเปลี่ยนกลางคัน การแยก process จะพังทันที")
        assertTrue(
            Regex("^[0-9a-f]{8}$").matches(first),
            "รูปแบบต้องตรงกับที่ตัวอ่านฝั่ง Dart ใช้แยกไฟล์รูปแบบใหม่ ได้ $first",
        )
    }

    /**
     * ค่าที่มี TAB ปนต้องไม่ทำให้คอลัมน์เลื่อน
     *
     * ยังไม่มีผู้เรียกไหนใน repo ส่ง TAB มา แต่ถ้าวันหนึ่งมี ผลจะเป็นไฟล์ที่ยัง
     * "อ่านได้" แต่คอลัมน์เลื่อนไปหมด — ผิดแบบที่มองไม่เห็น ซึ่งแย่กว่าอ่านไม่ออก
     */
    @Test
    fun `TAB ที่ปนมาในค่าถูกแทนด้วยช่องว่าง ไม่ทำให้คอลัมน์เลื่อน`() {
        val line = BackgroundEvidenceLog.line(
            timestampMillis = 0L,
            processId = "a1b2c3d4",
            event = "enter",
            regionIdentifier = "มี\tแท็บ",
            conclusion = "foreground",
            rawSignals = "-",
        )

        assertEquals(6, line.split("\t").size)
    }

    /**
     * **ตัวระบุ process ต้องอยู่ครบทั้งสี่ค่า เรียงเหมือนฝั่ง iOS**
     *
     * คู่แฝดของ `testProcessMarkerHasAllFourKeysInOrder` ใน RunnerTests.swift —
     * ถ้าลำดับหรือชื่อ key ต่างกันแม้แค่ตัวเดียว การ `grep` ไฟล์ของสองแพลตฟอร์ม
     * ด้วยคำสั่งเดียวกันจะได้ผลไม่เท่ากัน ซึ่งทำให้ "เทียบ Android กับ iOS"
     * กลายเป็นการเทียบสิ่งที่วัดคนละวิธี
     */
    @Test
    fun `ตัวระบุ process มีครบสี่ค่าและเรียงตรงกับฝั่ง iOS`() {
        // ตรึง processId/pid ไว้ ไม่อ่านค่าจริง — `android.os.Process.myPid()` เป็น
        // stub ที่โยน `RuntimeException("Stub!")` บน JVM ของ unit test
        val marker = BackgroundEvidenceLog.processMarker(
            uptimeMillis = 1234L,
            receiverEntry = true,
            processId = "a1b2c3d4",
            pid = 4242,
        )

        assertEquals(
            "procUuid=a1b2c3d4 pid=4242 uptimeMs=1234 receiverEntry=true",
            marker,
        )
    }

    /**
     * `uptimeMs` ต้องเป็น **จำนวนเต็มมิลลิวินาที** ไม่ใช่วินาทีทศนิยม
     *
     * ช่วงที่ต้องแยกให้ออกคือหลักร้อยมิลลิวินาที: event ที่มาถึงทันทีหลัง process
     * เกิดคือหลักฐานว่า process ถูกสร้างขึ้นมาเพื่อ event นั้น ถ้าปัดเป็น `0.4s`
     * เหมือนรูปแบบเดิม ความต่างระหว่าง 350 ms กับ 449 ms จะหายไป
     */
    @Test
    fun `uptimeMs เป็นจำนวนเต็มมิลลิวินาที ไม่ใช่วินาทีทศนิยม`() {
        val marker = BackgroundEvidenceLog.processMarker(
            uptimeMillis = 350L,
            receiverEntry = false,
            processId = "a1b2c3d4",
            pid = 4242,
        )

        assertTrue(
            Regex(" uptimeMs=350 ").containsMatchIn(marker),
            "ต้องเป็น uptimeMs=350 ไม่ใช่ 0.4s หรือ 350.0 ได้ $marker",
        )
        assertTrue(
            marker.endsWith("receiverEntry=false"),
            "receiverEntry ต้องเป็นค่าสุดท้ายเหมือนฝั่ง iOS ได้ $marker",
        )
    }

    /**
     * `procUuid` ในสัญญาณดิบต้อง **เป็นค่าเดียวกับคอลัมน์ที่ 2 เสมอ**
     *
     * ทั้งสองที่ตั้งใจให้ซ้ำกัน (คอลัมน์ที่ 2 ไว้ให้คนอ่าน / key ไว้ให้เครื่องอ่าน
     * คู่กับ pid+uptimeMs) — แต่ "ซ้ำกัน" มีค่าก็ต่อเมื่อ **ขัดแย้งกันไม่ได้**
     * ถ้าวันหนึ่งสองที่มาจากคนละแหล่ง ไฟล์หลักฐานจะมีสองคำตอบสำหรับคำถามเดียว
     */
    @Test
    fun `procUuid ในสัญญาณดิบตรงกับคอลัมน์ที่ 2 เสมอ`() {
        val line = BackgroundEvidenceLog.line(
            timestampMillis = 0L,
            event = "enter",
            regionIdentifier = "k9p-default",
            conclusion = "relaunchedFromTerminated",
            rawSignals = BackgroundEvidenceLog.processMarker(
                uptimeMillis = 0L,
                receiverEntry = true,
                pid = 4242,
            ),
        )

        val columns = line.split("\t")
        val fromRawSignals = Regex("procUuid=([0-9a-f]{8})").find(columns[5])?.groupValues?.get(1)

        assertEquals(columns[1], fromRawSignals)
    }

    /**
     * บรรทัด `exit` ต้องบอกได้เองว่า "30 วินาทีที่ขอไป กลายเป็นเท่าไรจริง"
     *
     * ล็อกชื่อ key และลำดับไว้ เพราะผู้ทดสอบอ่านค่าพวกนี้ด้วยตาบนหน้าจอมือถือ
     * ระหว่างเก็บข้อมูล และ `grep` จากไฟล์ดิบทีหลัง
     */
    @Test
    fun `บรรทัด exit มีเวลาของนาฬิกาปลุกครบสามค่าเรียงตามที่ตกลง`() {
        val field = BackgroundEvidenceLog.exitTimingField(
            sinceLastSeenMillis = 30_412L,
            scheduledAtElapsedMillis = 1_788_153L,
            firedAtElapsedMillis = 1_790_935L,
        )

        assertEquals(
            "sinceLastSeenMs=30412 scheduledAtElapsed=1788153 firedAtElapsed=1790935",
            field,
        )
    }

    /**
     * **`n/a` ห้ามกลายเป็น `0`** — สาขาที่เทียบเวลาข้ามรอบบูตไม่ได้ส่ง `null` มา
     * ถ้าเรนเดอร์เป็น 0 บรรทัดนั้นจะอ่านได้ว่า "นาฬิกาปลุกดังตรงเวลาเป๊ะและเพิ่ง
     * เห็น beacon เมื่อ 0 ms ที่แล้ว" ซึ่งเป็นตัวเลขที่ดูสมเหตุสมผลแต่ไม่จริงเลย
     * — อันตรายกว่าช่องว่าง เพราะไม่มีอะไรฟ้อง
     */
    @Test
    fun `ค่าที่ไม่มีถูกเขียนเป็น n over a ไม่ใช่ศูนย์`() {
        val field = BackgroundEvidenceLog.exitTimingField(
            sinceLastSeenMillis = null,
            scheduledAtElapsedMillis = null,
            firedAtElapsedMillis = null,
        )

        assertEquals(
            "sinceLastSeenMs=n/a scheduledAtElapsed=n/a firedAtElapsed=n/a",
            field,
        )
        assertTrue("0" !in field, "ห้ามมีเลขศูนย์ปลอมในฟิลด์ที่ไม่มีค่า ได้ $field")
    }

    /** `0` ที่เป็นค่าจริงต้องเขียนเป็น `0` ไม่ใช่ `n/a` — คนละความหมายกัน */
    @Test
    fun `ศูนย์ที่เป็นค่าจริงไม่ถูกกลืนเป็น n over a`() {
        val field = BackgroundEvidenceLog.exitTimingField(
            sinceLastSeenMillis = 0L,
            scheduledAtElapsedMillis = 0L,
            firedAtElapsedMillis = 0L,
        )

        assertEquals(
            "sinceLastSeenMs=0 scheduledAtElapsed=0 firedAtElapsed=0",
            field,
        )
    }

    /**
     * ฟิลด์นี้ถูกต่อท้ายคอลัมน์สัญญาณดิบ จึงต้องไม่ทำให้จำนวนคอลัมน์เปลี่ยน
     */
    @Test
    fun `ฟิลด์เวลาของนาฬิกาปลุกไม่ทำให้คอลัมน์เลื่อน`() {
        val line = BackgroundEvidenceLog.line(
            timestampMillis = 0L,
            processId = "a1b2c3d4",
            event = "exit",
            regionIdentifier = "k9p-default",
            conclusion = "relaunchedFromTerminated",
            rawSignals = "everForeground=false " + BackgroundEvidenceLog.exitTimingField(
                sinceLastSeenMillis = 30_412L,
                scheduledAtElapsedMillis = 1_788_153L,
                firedAtElapsedMillis = 1_790_935L,
            ),
        )

        val columns = line.split("\t")
        assertEquals(6, columns.size)
        assertTrue(columns[5].endsWith("firedAtElapsed=1790935"), "ได้ ${columns[5]}")
    }

    @Test
    fun `ค่า default ของ processId ถูกใช้เมื่อผู้เรียกไม่ส่งมา`() {
        val line = BackgroundEvidenceLog.line(
            timestampMillis = 0L,
            event = "launch",
            regionIdentifier = "-",
            conclusion = "foreground",
            rawSignals = "-",
        )

        assertEquals(BackgroundEvidenceLog.processId, line.split("\t")[1])
    }

    /**
     * `restoredRegions=[]` ต้องแปลว่า **"อ่านได้และว่าง"** เท่านั้น
     *
     * ถ้าความล้มเหลวของฝั่งอ่านหลุดออกมาเป็น `[]` ได้ ตารางแปลผลใน
     * `docs/test-checklists/android_background_runbook.md` จะชี้ไปที่สาเหตุเดียว
     * ("มีโค้ดล้างสถานะทิ้ง") ทั้งที่สาเหตุจริงอาจเป็นค่าที่เก็บไว้เสียหาย —
     * แก้คนละทางโดยสิ้นเชิง และเป็นความล้มเหลวเงียบที่กินเวลาไปทั้งรอบทดสอบ
     */
    @Test
    fun `restoredRegions ว่างกับอ่านไม่ได้ ต้องเขียนออกมาคนละแบบ`() {
        assertEquals(
            "restoredRegions=[k9p-default]",
            BackgroundEvidenceLog.restoredRegionsField(listOf("k9p-default"), readError = null),
        )
        assertEquals(
            "restoredRegions=[]",
            BackgroundEvidenceLog.restoredRegionsField(emptyList(), readError = null),
        )
        assertEquals(
            "restoredRegions=<read-failed:invalid-json>",
            BackgroundEvidenceLog.restoredRegionsField(emptyList(), readError = "invalid-json"),
        )
    }

    /**
     * `exitReasonField` (ADR-17 หัวข้อ 4) — ล็อกรูปแบบ `exitReason=<ค่า>` ตรงๆ
     * เพราะเป็น pure function เดียวที่ตัดสินว่าบรรทัด exit หนึ่งมาจากนาฬิกาปลุก
     * ปกติหรือมาจาก `reconcile()` ที่กู้สถานะ `inside` ที่ค้าง
     */
    @Test
    fun `exitReasonField เขียนออกมาตรงตัว`() {
        assertEquals("exitReason=alarm", BackgroundEvidenceLog.exitReasonField("alarm"))
        assertEquals(
            "exitReason=staleReconcile",
            BackgroundEvidenceLog.exitReasonField("staleReconcile"),
        )
        assertEquals(
            "exitReason=staleBootMismatch",
            BackgroundEvidenceLog.exitReasonField("staleBootMismatch"),
        )
    }

    /**
     * `deferReasonField` (ADR-17 หัวข้อ 6) — ล็อกรูปแบบ `reason=<ค่า>` ตรงๆ
     * เพราะเป็น pure function เดียวที่อธิบายว่าทำไม onExitAlarm ถึงเลื่อน
     * นาฬิกาปลุกแทนการประกาศ exit
     */
    @Test
    fun `deferReasonField เขียนออกมาตรงตัว`() {
        assertEquals("reason=stillSeen", BackgroundEvidenceLog.deferReasonField("stillSeen"))
        assertEquals("reason=notInside", BackgroundEvidenceLog.deferReasonField("notInside"))
        assertEquals("reason=notActive", BackgroundEvidenceLog.deferReasonField("notActive"))
    }

    /**
     * เหตุผลที่มีช่องว่าง (ข้อความของข้อยกเว้น) ต้องไม่ทำให้คอลัมน์สัญญาณดิบ
     * กลายเป็นหลาย key — ตัวอ่านคั่นค่าด้วยช่องว่าง
     */
    @Test
    fun `เหตุผลของ read-failed ไม่มีช่องว่างปน`() {
        val field = BackgroundEvidenceLog.restoredRegionsField(
            identifiers = emptyList(),
            readError = "IOException: Permission denied",
        )

        assertEquals("restoredRegions=<read-failed:IOException:_Permission_denied>", field)
        assertTrue(!field.substringAfter('=').contains(' '))
    }

    /**
     * `standbyBucketNameForRawBucket` (ADR-17 หัวข้อ 6) — แมปเลขดิบของ
     * `UsageStatsManager.getAppStandbyBucket()` เป็นชื่อ
     *
     * ครบทั้ง 7 bucket ตามที่ยืนยันจากซอร์สจริง (`UsageStatsManager.java:124-175`,
     * commit `e989d68`): `10`/`20`/`30`/`40`/`45` เรียกผ่านชื่อ constant ปกติได้
     * (public API) ส่วน `5`/`50` (`exempted`/`never`) ต้องเทียบด้วยเลขดิบเพราะ
     * `STANDBY_BUCKET_EXEMPTED`/`STANDBY_BUCKET_NEVER` เป็น `@hide @SystemApi`
     * เรียกผ่านชื่อไม่ได้จริง (ตรวจแล้วว่าคอมไพล์ไม่ผ่านถ้าอ้างชื่อตรงๆ)
     */
    @Test
    fun `standbyBucketNameForRawBucket แมปทั้งเจ็ดค่าที่รู้จัก`() {
        assertEquals("exempted", BackgroundEvidenceLog.standbyBucketNameForRawBucket(5))
        assertEquals("active", BackgroundEvidenceLog.standbyBucketNameForRawBucket(10))
        assertEquals("workingSet", BackgroundEvidenceLog.standbyBucketNameForRawBucket(20))
        assertEquals("frequent", BackgroundEvidenceLog.standbyBucketNameForRawBucket(30))
        assertEquals("rare", BackgroundEvidenceLog.standbyBucketNameForRawBucket(40))
        assertEquals("restricted", BackgroundEvidenceLog.standbyBucketNameForRawBucket(45))
        assertEquals("never", BackgroundEvidenceLog.standbyBucketNameForRawBucket(50))
    }

    /**
     * ค่าที่ไม่รู้จัก (เช่น bucket ใหม่ที่ Android เวอร์ชันถัดไปอาจเพิ่มมา) ต้อง
     * ไม่ทำให้เทสต์/แอปพัง — คืนชื่อที่ยังบอกเลขดิบไว้ให้สืบย้อนได้ ไม่ใช่โยน
     * exception หรือคืนค่าที่ดูเหมือนหนึ่งใน 7 บัคเก็ตที่รู้จัก
     */
    @Test
    fun `standbyBucketNameForRawBucket ค่าที่ไม่รู้จักไม่ทำให้พัง และบอกเลขดิบไว้`() {
        assertEquals("other(999)", BackgroundEvidenceLog.standbyBucketNameForRawBucket(999))
        assertEquals("other(-1)", BackgroundEvidenceLog.standbyBucketNameForRawBucket(-1))
        assertEquals("other(0)", BackgroundEvidenceLog.standbyBucketNameForRawBucket(0))
    }
}
