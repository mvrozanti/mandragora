plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlinx.kover")
}

val desktopIp: String = System.getenv("MANDRAGORA_DESKTOP_IP") ?: "100.115.80.79"
val buildMinute: Int = (System.currentTimeMillis() / 60_000L).toInt()
val gitLabel: String = runCatching {
    providers.exec { commandLine("git", "describe", "--always", "--dirty") }.standardOutput.asText.get().trim()
}.getOrDefault("").ifEmpty { "local" }

android {
    namespace = "ac.mvr.phone"
    compileSdk = 35
    buildToolsVersion = "35.0.0"

    defaultConfig {
        applicationId = "ac.mvr.phone"
        minSdk = 29
        targetSdk = 35
        versionCode = buildMinute
        versionName = gitLabel
        buildConfigField("String", "DESKTOP_IP", "\"$desktopIp\"")
        buildConfigField("int", "BRIDGE_PORT", "6688")
    }

    signingConfigs {
        val keystore = System.getenv("PHONE_KEYSTORE")
        if (keystore != null) {
            create("release") {
                storeFile = file(keystore)
                storePassword = System.getenv("PHONE_KEYSTORE_PASS")
                keyAlias = System.getenv("PHONE_KEY_ALIAS") ?: "mandragora"
                keyPassword = System.getenv("PHONE_KEYSTORE_PASS")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }

    lint {
        baseline = file("lint-baseline.xml")
        abortOnError = true
        warningsAsErrors = true
        checkReleaseBuilds = false
        disable += setOf("GradleDependency", "NewerVersionAvailable", "AndroidGradlePluginVersion", "OldTargetApi")
    }
}

kover {
    reports {
        filters {
            includes {
                packages("ac.mvr.phone.logic")
            }
        }
        variant("debug") {
            verify {
                rule {
                    minBound(80)
                }
            }
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.animation:animation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-session:1.5.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
    testImplementation("junit:junit:4.13.2")
}
