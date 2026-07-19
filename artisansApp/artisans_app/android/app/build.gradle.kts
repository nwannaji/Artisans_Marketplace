plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fixit.ng"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.fixit.ng"
        minSdk = 27
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    // SECURITY: Create a proper release keystore before shipping to production.
    // See: https://docs.flutter.dev/deployment/android#signing-the-app
    // Never ship debug-signed builds to production.
    signingConfigs {
        // TODO: Create a release keystore and configure it here:
        // create("release") {
        //     storeFile = file(System.getenv("KEYSTORE_FILE") ?: "release.keystore")
        //     storePassword = System.getenv("KEYSTORE_PASSWORD")
        //     keyAlias = System.getenv("KEY_ALIAS")
        //     keyPassword = System.getenv("KEY_PASSWORD")
        // }
    }

    buildTypes {
        release {
            // SECURITY: Replace debug signing with a proper release keystore before production!
            // Using debug signing config allows anyone to modify and re-sign the APK.
            signingConfig = signingConfigs.getByName("debug") // change for release build later
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-maps:19.2.0")
}

flutter {
    source = "../.."
}