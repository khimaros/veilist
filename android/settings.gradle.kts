pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // pinned to AGP 8.x: veilid's plugin uses rust-android-gradle 0.9.6, which
    // relies on a gradle api removed in gradle 9 (paired with AGP 9). AGP 8.9.1
    // runs on gradle 8.11.1 (see gradle-wrapper.properties), where it still
    // exists. 8.9.1 is the floor for mobile_scanner's camerax 1.6.x.
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
