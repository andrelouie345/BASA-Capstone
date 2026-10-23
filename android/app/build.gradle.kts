plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.basa_capstone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two apps from one codebase (tutor build split, 2026-10-22): build with
    // --flavor admin -t lib/main.dart, or --flavor tutor -t lib/main_tutor.dart.
    // Different application ids, so both install side by side with their own data.
    flavorDimensions += "variant"
    productFlavors {
        create("admin") {
            dimension = "variant"
            applicationId = "enn5.basa.admin"
            manifestPlaceholders["appName"] = "BASA"
        }
        create("tutor") {
            dimension = "variant"
            applicationId = "enn5.basa.tutor"
            manifestPlaceholders["appName"] = "BASA Tutor"
        }
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
