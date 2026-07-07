import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}
val hasKeyProperties = keyProperties.containsKey("keyAlias") &&
                       keyProperties.containsKey("keyPassword") &&
                       keyProperties.containsKey("storeFile") &&
                       keyProperties.containsKey("storePassword")

android {
    namespace = "com.theawesomeray.tether"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            if (hasKeyProperties) {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            } else {
                throw org.gradle.api.GradleException("key.properties configuration is missing! Tether release builds must be signed.")
            }
        }
    }

    defaultConfig {
        applicationId = "com.theawesomeray.tether"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Injected via the MAPS_API_KEY env var (see .github/workflows/build-apk.yml).
        // Empty string keeps local `flutter build`/`flutter run` working without the
        // key set — map tiles just won't load locally, which is fine for day-to-day dev.
        manifestPlaceholders["mapsApiKey"] = System.getenv("MAPS_API_KEY") ?: ""
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // ShortcutManagerCompat + Person — used by MainActivity to publish the
    // long-lived conversation shortcut that makes chat notifications land in
    // Android's "Conversations" section (see NotificationService in Dart).
    implementation("androidx.core:core:1.13.1")
}

flutter {
    source = "../.."
}
