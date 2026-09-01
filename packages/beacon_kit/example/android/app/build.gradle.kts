plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.beaconkit.example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

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
