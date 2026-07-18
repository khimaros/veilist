import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// release signing material, from android/key.properties locally or the matching
// env vars in ci. every published apk must carry the SAME key forever: android
// refuses to update an app signed by a different key, and f-droid/izzyondroid
// pin the key per app (see DISTRIBUTION.md). when nothing is configured the
// release build falls back to the debug key - fine for a local install, never
// for a release.
val keyProperties =
    Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }

fun signingSetting(property: String, environment: String): String? =
    (keyProperties.getProperty(property) ?: System.getenv(environment))
        ?.takeIf { it.isNotBlank() }

val releaseStore = signingSetting("storeFile", "VEILIST_KEYSTORE")

android {
    namespace = "com.khimaros.veilist"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.khimaros.veilist"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStore != null) {
            create("release") {
                storeFile = file(releaseStore)
                storePassword = signingSetting("storePassword", "VEILIST_KEYSTORE_PASSWORD")
                keyAlias = signingSetting("keyAlias", "VEILIST_KEY_ALIAS")
                keyPassword = signingSetting("keyPassword", "VEILIST_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // the release key when one is configured, the debug key otherwise so
            // `flutter run --release` still works on a fresh checkout.
            signingConfig =
                signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    // AGP otherwise embeds a google-signed blob listing the app's dependencies.
    // it is opaque, it changes between builds, and f-droid's rebuilder cannot
    // reproduce it, so leave it out.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
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
