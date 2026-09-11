plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/**
 * git short SHA ของ working tree ตอน configure — คู่ขนานกับ build phase
 * "Stamp git SHA" ฝั่ง iOS (`Runner.xcodeproj`) ที่เขียนค่าเดียวกันลง `Info.plist`
 *
 * **ทำไมต้องมี:** ไฟล์หลักฐานฝั่ง Android ไม่มีทางบอกได้เลยว่าบรรทัดไหนมาจากบิลด์ไหน —
 * รอบตรวจ log 11 ก.ย. 2026 ต้องเดาว่า "318 บรรทัดแรกมาจากบิลด์เก่า" จากการสังเกตว่า
 * ยังไม่มีคอลัมน์ `store=` ซึ่งเป็นการอนุมานที่ใช้ได้ครั้งเดียวและจะใช้ไม่ได้อีกเมื่อ
 * ไม่มีฟิลด์ใหม่ให้สังเกต · ฝั่ง iOS มี `build=` ตั้งแต่ ADR-21 แล้ว
 *
 * คืน `"unknown"` เมื่อรันนอก git repo หรือไม่มี `git` — **ห้าม throw**
 * เพราะจะทำให้บิลด์ของคนที่ดาวน์โหลด source เป็น zip พังทั้งที่ไม่เกี่ยวกับแอปเลย
 */
fun gitShortSha(): String = runCatching {
    providers.exec {
        commandLine("git", "rev-parse", "--short", "HEAD")
    }.standardOutput.asText.get().trim()
}.getOrDefault("unknown")

android {
    namespace = "com.beaconkit.example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // ต้องเปิดเองตั้งแต่ AGP 8 — ค่า default เป็น `false` (ก่อนหน้านี้โปรเจกต์นี้
    // ไม่เคยใช้ `BuildConfig` เลยจึงไม่เคยต้องเปิด)
    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.beaconkit.example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // อ่านได้จาก `BuildConfig.GIT_SHORT_SHA` — ใช้ที่บรรทัด `launch` ของ
        // ไฟล์หลักฐานเท่านั้น ไม่ใช่ค่าที่ตรรกะใดพึ่งพา (ดู kdoc ของ `gitShortSha`)
        buildConfigField("String", "GIT_SHORT_SHA", "\"${gitShortSha()}\"")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // NotificationCompat / NotificationManagerCompat สำหรับ notification ที่ยิงจาก
    // โค้ด native ล้วน (ExampleNotifications) — ใช้ compat เพื่อให้พฤติกรรมเหมือนกัน
    // ข้าม API level เหมือนที่ beacon_kit_android ใช้กับ permission
    implementation("androidx.core:core-ktx:1.13.1")

    // ล็อกรูปแบบบรรทัดของไฟล์หลักฐาน (BackgroundEvidenceLogTest) — ไฟล์นั้นคือ
    // หลักฐานเดียวของรอบทดสอบที่เกิดตอนไม่มีใครดูหน้าจอ และเก็บซ้ำไม่ได้
    testImplementation("org.jetbrains.kotlin:kotlin-test")
}

android {
    sourceSets {
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }
    testOptions {
        unitTests {
            all {
                it.useJUnitPlatform()
                it.testLogging {
                    events("passed", "skipped", "failed")
                }
            }
        }
    }
}
