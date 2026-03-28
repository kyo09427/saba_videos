plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.saba_videos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // リリース署名設定（環境変数から読み込む）
    signingConfigs {
        create("release") {
            val keystorePath = System.getenv("KEYSTORE_PATH")
            val storePass = System.getenv("STORE_PASSWORD")
            val keyAliasName = System.getenv("KEY_ALIAS")
            val keyPass = System.getenv("KEY_PASSWORD")

            if (keystorePath != null && storePass != null && keyAliasName != null && keyPass != null) {
                storeFile = file(keystorePath)
                storePassword = storePass
                keyAlias = keyAliasName
                keyPassword = keyPass
            }
        }
    }

    defaultConfig {
        applicationId = "com.example.saba_videos"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 環境変数が設定されている場合はリリース署名、なければデバッグ署名（ローカル開発用）
            val hasReleaseConfig = System.getenv("KEYSTORE_PATH") != null
            signingConfig = if (hasReleaseConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
        }
    }
}

flutter {
    source = "../.."
}
