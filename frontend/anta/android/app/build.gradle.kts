import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val allowDebugSigning =
    findProperty("antaAllowDebugSigning")?.toString()?.toBoolean() ?: false

android {
    namespace = "com.alexzamfir.anta"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires Java 8 library desugaring even
        // when nothing is scheduled; the build fails to link without it.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.alexzamfir.anta"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasReleaseKeystore) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild" && !hasReleaseKeystore && !allowDebugSigning) {
        doFirst {
            throw GradleException(
                "Release build refused: android/key.properties is missing, so this APK " +
                    "would be signed with the debug key and could not install over the " +
                    "release-signed app (uninstalling it would wipe its data). Copy " +
                    "android/key.properties and android/app/release-keystore.jks from the " +
                    "machine that has them, or pass -PantaAllowDebugSigning=true " +
                    "(`flutter build apk -PantaAllowDebugSigning=true`, or " +
                    "`release build --allow-debug-signing`) for a throwaway " +
                    "debug-signed build."
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
