import java.util.Properties

/**
 * Nov 19 — the Maps key, read from local.properties and never from the
 * repository.
 *
 * Mirrors the discipline in RexSearch.swift exactly, and for the same reason.
 * A debug build uses the development project's key; when none is configured it
 * gets an empty string and the map fails loudly rather than quietly billing
 * the production project. "A loud, free failure beats a silent, billable
 * success" is the iOS note, and it holds here.
 *
 * local.properties is gitignored, which matters more on Android than it might:
 * this repository is public, and a Maps key committed to it would be scraped
 * within the hour. The key is also restricted to the package and signing
 * certificate in the Cloud console, so a leaked one is useless to anybody
 * else — belt and braces, because the console restriction is the only one of
 * the two that survives a mistake here.
 */
fun mapsKey(project: org.gradle.api.Project): String {
    val f = project.rootProject.file("local.properties")
    if (!f.exists()) return ""
    return Properties().apply { f.inputStream().use { load(it) } }
        .getProperty("MAPS_API_KEY_DEBUG")
        .orEmpty()
        .trim()
}

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.kathrynfinnis.rex"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.kathrynfinnis.rex"
        // 26 rather than 24: it is where adaptive icons and the modern
        // notification APIs start, and it already covers ~97% of devices.
        minSdk = 26
        // Nov 4 — 36, not 35. Google Play's deadline for new apps and updates
        // to target Android 16 passed on 31 August 2026, so an upload built
        // against 35 is rejected at the door.
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        // The manifest reads the key through this placeholder; the screen
        // reads the same value through BuildConfig so it can say something
        // useful when there isn't one, instead of showing a grey rectangle.
        manifestPlaceholders["MAPS_API_KEY"] = mapsKey(project)
        buildConfigField("String", "MAPS_API_KEY", "\"${mapsKey(project)}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    debugImplementation(libs.androidx.ui.tooling)

    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.postgrest)
    implementation(libs.supabase.auth)
    implementation(libs.supabase.storage)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.coil.compose)
    implementation(libs.maps.compose)
}
