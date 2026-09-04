package com.bigc.beacon_kit_android

import android.content.SharedPreferences

/**
 * ตัวปลอมของ `SharedPreferences` — implement interface ตรง ๆ ด้วย `Map` ในหน่วยความจำ
 *
 * ## ทำไมทำแบบนี้ได้โดยไม่ต้องมี Robolectric
 *
 * `SharedPreferences`/`SharedPreferences.Editor` เป็น **interface** ล้วน ไม่มี
 * method body ให้ stub เลย ปัญหา "เรียกแล้วโยน `RuntimeException(\"Stub!\")`" ของ
 * android.jar เกิดกับ**คลาสที่มี body** เท่านั้น (เช่น `SystemClock`, `PowerManager`)
 * — interface สองตัวนี้จึง implement เองตรง ๆ ได้เหมือน fake ทั่วไปในเทสต์ Java/Kotlin
 * ปกติ ไม่ใช่ของแปลกใหม่เฉพาะ Android
 *
 * ใช้คู่กับ `Context` ที่ mock ด้วย Mockito (เฉพาะ `getSharedPreferences`/
 * `applicationContext`) — ดู `BackgroundRegionMonitorOnExitAlarmTest`
 */
class FakeSharedPreferences : SharedPreferences {

    private val values = mutableMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()

    override fun getString(key: String?, defValue: String?): String? =
        values[key] as? String ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        values[key] as? MutableSet<String> ?: defValues

    override fun getInt(key: String?, defValue: Int): Int = values[key] as? Int ?: defValue

    override fun getLong(key: String?, defValue: Long): Long = values[key] as? Long ?: defValue

    override fun getFloat(key: String?, defValue: Float): Float =
        values[key] as? Float ?: defValue

    override fun getBoolean(key: String?, defValue: Boolean): Boolean =
        values[key] as? Boolean ?: defValue

    override fun contains(key: String?): Boolean = values.containsKey(key)

    override fun edit(): SharedPreferences.Editor = FakeEditor()

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) {
        // ไม่มีเทสต์ไหนในชุดนี้พึ่งการแจ้งเตือนการเปลี่ยนแปลง — ไม่ implement
    }

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) {
        // เช่นเดียวกับข้างบน
    }

    /**
     * บัฟเฟอร์การเปลี่ยนแปลงไว้ก่อน แล้วค่อยเขียนทับ `values` ตอน [commit]/[apply]
     * — ตรงกับความหมายจริงของ `SharedPreferences.Editor` (การเปลี่ยนแปลงยังไม่มีผล
     * จนกว่าจะ commit/apply) `BackgroundRegionStore` ทั้งไฟล์ใช้ `commit()` เท่านั้น
     * (ไม่ใช่ `apply()`) ตามที่คอมเมนต์ของไฟล์นั้นอธิบายเหตุผลไว้แล้ว
     */
    private inner class FakeEditor : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private val removedKeys = mutableSetOf<String>()
        private var clearAllFirst = false

        override fun putString(key: String?, value: String?): SharedPreferences.Editor {
            pending[requireNotNull(key)] = value
            return this
        }

        override fun putStringSet(
            key: String?,
            values: MutableSet<String>?,
        ): SharedPreferences.Editor {
            pending[requireNotNull(key)] = values
            return this
        }

        override fun putInt(key: String?, value: Int): SharedPreferences.Editor {
            pending[requireNotNull(key)] = value
            return this
        }

        override fun putLong(key: String?, value: Long): SharedPreferences.Editor {
            pending[requireNotNull(key)] = value
            return this
        }

        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor {
            pending[requireNotNull(key)] = value
            return this
        }

        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor {
            pending[requireNotNull(key)] = value
            return this
        }

        override fun remove(key: String?): SharedPreferences.Editor {
            removedKeys += requireNotNull(key)
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            clearAllFirst = true
            return this
        }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun apply() {
            if (clearAllFirst) values.clear()
            removedKeys.forEach { values.remove(it) }
            values.putAll(pending)
        }
    }
}
