group = "com.bigc.beacon_kit_android"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.bigc.beacon_kit_android"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                // Mockito 5.0.0 (mock maker inline ตั้งแต่ค่าเริ่มต้น) ใช้ Byte
                // Buddy รุ่นที่รองรับทางการถึง Java 20 เท่านั้น — เครื่องพัฒนาที่
                // ตั้ง JAVA_HOME ไปที่ JBR ของ Android Studio รุ่นใหม่รันบน Java 25
                // ซึ่งทำให้ Mockito.mock()/mockStatic() ที่ต้อง instrument bytecode
                // ล้มด้วย "Java 25 is not supported by the current version of Byte
                // Buddy" — ค่านี้คือ flag ที่ error message ของ Mockito เองแนะนำให้
                // ตั้งตรง ๆ ไม่ใช่การเพิ่ม dependency ใหม่หรือเปลี่ยนเวอร์ชัน
                // mockito-core (ยังคง 5.0.0 เท่าเดิม)
                it.systemProperty("net.bytebuddy.experimental", "true")

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // ใช้ ContextCompat / ActivityCompat สำหรับ runtime permission — เรียกผ่าน
    // compat ไม่ใช่ API ของ framework ตรง ๆ เพื่อให้พฤติกรรมเหมือนกันข้าม API level
    implementation("androidx.core:core-ktx:1.13.1")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
