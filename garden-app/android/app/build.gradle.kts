import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    // Compose compiler — lo necesita el widget nativo (Jetpack Glance usa Compose).
    id("org.jetbrains.kotlin.plugin.compose")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.garden.bolivia"
    // androidx.browser (dependencia de amplify liveness) exige compileSdk 36 —
    // flutter.compileSdkVersion todavía resuelve a 35 en este canal.
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

    // Widget nativo del home screen (Jetpack Glance, ver android/app/src/main/kotlin/
    // com/garden/bolivia/widget/) — usa Compose por debajo.
    buildFeatures {
        compose = true
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

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Firma de producción — requiere android/key.properties (no versionado, ver .gitignore).
            // Sin ese archivo, cae de nuevo a la firma de debug para que `flutter run --release` siga
            // funcionando en desarrollo, pero un AAB así NUNCA debe subirse a Play Store.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // isMinifyEnabled queda en su default (false) — no lo activamos acá porque
            // no está probado. proguard-rules.pro ya queda listo (regla de
            // flutter_local_notifications/Gson) para el día que se active shrinking,
            // así R8 no rompe la (de)serialización de notificaciones programadas.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // face_liveness_detector y amplify liveness exigen 2.1.5+
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // Widget nativo del home screen — equivalente Android del Live Activity de
    // iOS (ver ios/GardenActivityWidget/). Glance es la API moderna de Google
    // para widgets (Compose por debajo) — reemplaza RemoteViews/AppWidgetProvider
    // clásico, que requeriría mucho más código a mano para el mismo resultado.
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")
}
