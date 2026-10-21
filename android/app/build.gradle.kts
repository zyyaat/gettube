plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Stable release signing (fixes "App not installed" on updates):
// CI injects KEYSTORE_* env vars from GitHub Secrets — ONE fixed keystore
// uploaded once — so every build signs with the SAME key and installs over
// previous versions. Locally (no env vars) we fall back to the debug key
// so `flutter run --release` keeps working.
val keystorePath = System.getenv("KEYSTORE_PATH")
val keystorePass = System.getenv("KEYSTORE_PASSWORD")
val keystoreAlias = System.getenv("KEY_ALIAS") ?: "gettube"
val keyPass = System.getenv("KEY_PASSWORD")

android {
    namespace = "com.gettubeapp.gettube"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (java.time backport)
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.gettubeapp.gettube"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Package ONLY armeabi-v7a (arm32): ffmpeg AARs otherwise bundle
        // arm64-v8a + x86_64 too, adding ~41 MB of dead weight.
        // arm64 devices run the v7a APK natively through backward compatibility.
        ndk {
            abiFilters += listOf("armeabi-v7a")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePath != null && keystorePass != null) {
                storeFile = file(keystorePath)
                storePassword = keystorePass
                keyAlias = keystoreAlias
                keyPassword = keyPass ?: keystorePass
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePath != null && keystorePass != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            // Hard-exclude non-arm32 native libs. ffmpeg AARs bundle every ABI
            // and ndk.abiFilters alone did not strip them (AGP 8 + Flutter DSL),
            // so drop them explicitly at packaging time (~41 MB saved).
            excludes += setOf(
                "lib/arm64-v8a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
