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
}
