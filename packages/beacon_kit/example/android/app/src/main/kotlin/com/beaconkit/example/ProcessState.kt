package com.beaconkit.example

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.SystemClock

/**
 * สถานะของ process นี้ตั้งแต่เกิดจนถึงตอนนี้ — **คือสิ่งที่การทดสอบเบื้องหลังต้อง
 * พิสูจน์**
 *
 * เป็นคู่แฝดของตรรกะใน `AppDelegate.currentRunContext()` + `AppRunContext` ฝั่ง
 * iOS โดยตั้งใจ: ค่าใน [conclusion] ใช้คำเดียวกันเป๊ะ (`foreground` /
 * `background` / `relaunchedFromTerminated`) เพื่อให้เทียบผลสองแพลตฟอร์มได้จริง
 *
 * ## ทำไมนับ activity แทนการถาม API สักตัว
 *
 * Android ไม่มี API เดียวที่ตอบว่า "process นี้ถูกระบบสร้างขึ้นมาเองหรือผู้ใช้เปิด"
 * `ActivityManager.RunningAppProcessInfo.importance` บอกได้แค่**ตอนนี้** ไม่ได้บอก
 * ประวัติ — process ที่ผู้ใช้เพิ่งกดปิดหน้าจอไปจะได้ค่าเดียวกับ process ที่ระบบ
 * สร้างขึ้นมาใหม่เพื่อส่ง broadcast
 *
 * สิ่งที่แยกได้แน่นอนคือ: **process ที่ผู้ใช้เปิดเองต้องผ่านการมี `Activity` เสมอ**
 * ถ้าตั้งแต่เกิดมายังไม่เคยมี `Activity` ถูกสร้างเลย แปลว่า process นี้เกิดจาก
 * `BroadcastReceiver`/`Service` ที่ระบบเรียก ไม่ใช่จากผู้ใช้ — ตรรกะเดียวกับ
 * `hasEverBecomeActive` ฝั่ง iOS ทุกประการ
 *
 * ⚠️ **ข้อจำกัดที่ต้องรู้:** สรุปนี้บอกว่า "ผู้ใช้ไม่ได้เปิดแอปใน process นี้"
 * ไม่ได้บอกว่า "แอปเคยถูกฆ่ามาก่อน" — process แรกสุดหลังติดตั้งที่ถูกปลุกด้วย
 * broadcast ก็ให้ค่าเดียวกัน ซึ่งตรงกับความหมายที่เราต้องการพอดี (ระบบเป็นคนปลุก)
 * แต่ห้ามอ่านค่านี้ว่า "ฟื้นจากสถานะถูกฆ่า" โดยไม่ดูบรรทัดก่อนหน้าในไฟล์ประกอบ
 */
class ProcessState : Application.ActivityLifecycleCallbacks {

    /**
     * เวลาที่ process นี้เริ่ม วัดด้วย [SystemClock.elapsedRealtime] ไม่ใช่
     * `System.currentTimeMillis()`
     *
     * ต้องเป็นนาฬิกาที่ไม่กระโดด เพราะเครื่องทดสอบอาจ sync เวลากับเครือข่ายกลาง
     * รอบทดสอบข้ามคืน ถ้าใช้ wall clock อายุ process จะติดลบหรือกระโดดได้
     */
    val processStartedElapsedMillis: Long = SystemClock.elapsedRealtime()

    @Volatile
    var hasEverBeenForeground: Boolean = false
        private set

    /** จำนวน activity ที่อยู่ในสถานะ started ตอนนี้ (0 = ไม่มี UI บนหน้าจอ) */
    @Volatile
    var startedActivityCount: Int = 0
        private set

    @Volatile
    private var resumedActivityCount: Int = 0

    /** สัญญาณดิบ ไม่ใช่ข้อสรุป — เก็บลง log เพื่อให้ตรวจย้อนกลับได้ */
    val rawLifecycleState: String
        get() = when {
            resumedActivityCount > 0 -> "resumed"
            startedActivityCount > 0 -> "started"
            hasEverBeenForeground -> "stopped"
            else -> "noActivityEver"
        }

    /**
     * ข้อสรุปว่ารอบนี้อยู่ในบริบทไหน — **ใช้คำเดียวกับฝั่ง iOS**
     *
     * `relaunchedFromTerminated` คือค่าที่การทดสอบเบื้องหลังต้องเห็นในไฟล์ log
     * จึงจะถือว่าผ่าน: มี event เข้ามาขณะที่ process ยังไม่เคยมี UI เลย
     */
    val conclusion: String
        get() = when {
            resumedActivityCount > 0 -> "foreground"
            hasEverBeenForeground -> "background"
            else -> "relaunchedFromTerminated"
        }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        // นับที่ started/resumed ไม่ใช่ created — created เกิดก่อนหน้าจอขึ้นจริง
    }

    override fun onActivityStarted(activity: Activity) {
        startedActivityCount++
    }

    override fun onActivityResumed(activity: Activity) {
        resumedActivityCount++
        // ตั้งครั้งเดียวแล้วไม่กลับ — ตรงกับ `hasEverBecomeActive` ฝั่ง iOS
        hasEverBeenForeground = true
    }

    override fun onActivityPaused(activity: Activity) {
        if (resumedActivityCount > 0) resumedActivityCount--
    }

    override fun onActivityStopped(activity: Activity) {
        if (startedActivityCount > 0) startedActivityCount--
    }

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

    override fun onActivityDestroyed(activity: Activity) = Unit
}
