plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // NOTE: com.google.gms.google-services is applied at the BOTTOM of this file,
    // not in the plugins block. This matches Google's ordering recommendation so
    // the plugin can see AGP's processed build variants and inject resources.
}

android {
    namespace = "com.majumaink.cinesphere"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (java.time backport).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.majumaink.cinesphere"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // flutter_local_notifications needs the java.time backport on older API levels.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // NotificationCompat for the download keep-alive foreground service.
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}

// Apply Google Services plugin LAST so it can read all AGP-processed variants
// and merge google-services.json → R.string.default_web_client_id,
// R.integer.google_play_services_version, and Firebase options resources.
// Plugin is declared in settings.gradle.kts plugins { id(...) version apply false }.
apply(plugin = "com.google.gms.google-services")
