plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.kalakchi.ramyar.pos"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Store identity of the app. Keep it in step with the iOS bundle id
        // (com.kalakchi.ramyar.pos) and with linux/CMakeLists.txt on Linux.
        applicationId = "com.kalakchi.ramyar.pos"
        // Values come from the Flutter tool (flutter.minSdkVersion / targetSdk /
        // version from pubspec.yaml) so they can never drift from the project.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Local testing signs with the debug key, so `flutter build apk
            // --release` and `flutter run --release` work on any machine with no
            // keystore. Before publishing to Google Play, generate an upload
            // keystore and point this at a release signingConfig; the
            // key.properties / *.jks files are already git-ignored
            // (see android/.gitignore).
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
