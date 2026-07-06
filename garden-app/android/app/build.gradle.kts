plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.garden.bolivia"
    // flutter_facebook_auth y androidx.browser (dependencia de amplify liveness) exigen
    // compileSdk 36 — flutter.compileSdkVersion todavía resuelve a 35 en este canal.
    compileSdk = 36
    ndkVersion = "30.0.14904198"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.garden.bolivia"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // face_liveness_detector (AWS Amplify) requires API 24+ (posthog-android needs 23+, satisfied)
        targetSdk = flutter.targetSdkVersion
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

flutter {
    source = "../.."
}

dependencies {
    // face_liveness_detector y amplify liveness exigen 2.1.5+
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
