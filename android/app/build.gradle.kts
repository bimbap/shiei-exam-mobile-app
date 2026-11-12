import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val releaseStoreFilePath = keystoreProperties.getProperty("storeFile")?.trim().orEmpty()
val releaseStorePassword = keystoreProperties.getProperty("storePassword")?.trim().orEmpty()
val releaseKeyAlias = keystoreProperties.getProperty("keyAlias")?.trim().orEmpty()
val releaseKeyPassword = keystoreProperties.getProperty("keyPassword")?.trim().orEmpty()
val releaseStoreFile = if (releaseStoreFilePath.isNotEmpty()) file(releaseStoreFilePath) else null
val hasValidReleaseKeystore = releaseStoreFile != null &&
    releaseStoreFile.exists() &&
    releaseStorePassword.isNotEmpty() &&
    releaseKeyAlias.isNotEmpty() &&
    releaseKeyPassword.isNotEmpty()

val expectedSigningSha256 = (
    (project.findProperty("releaseSigningSha256") as String?)
        ?: keystoreProperties.getProperty("signingSha256")
        ?: ""
).replace(":", "").trim().uppercase()

val allowDebugReleaseSigning = (project.findProperty("allowDebugReleaseSigning") as String?)
    ?.equals("true", ignoreCase = true) == true

android {
    namespace = "id.shiei.kiosk_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "id.shiei.kiosk_app"
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
        manifestPlaceholders["appName"] = "Shiei Exam"
        buildConfigField("String", "EXPECTED_SIGNING_SHA256", "\"$expectedSigningSha256\"")
    }

    signingConfigs {
        if (hasValidReleaseKeystore) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            manifestPlaceholders["appName"] = "Shiei Exam (Debug)"
        }
        release {
            manifestPlaceholders["appName"] = "Shiei Exam"
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = when {
                hasValidReleaseKeystore -> signingConfigs.getByName("release")
                allowDebugReleaseSigning -> {
                    logger.warn("WARNING: Release APK is temporarily using debug signing (-PallowDebugReleaseSigning=true). Do NOT distribute this APK to students.")
                    signingConfigs.getByName("debug")
                }
                else -> signingConfigs.getByName("debug").also {
                    if (gradle.startParameter.taskNames.any { task -> task.contains("Release", ignoreCase = true) }) {
                        throw GradleException(
                            "Release signing keystore not configured. Create android/key.properties (see android/key.properties.example) " +
                            "or pass -PallowDebugReleaseSigning=true for local non-production testing only."
                        )
                    }
                }
            }
        }
    }

    applicationVariants.all {
        val variant = this
        if (variant.buildType.name == "release") {
            variant.assembleProvider.configure {
                doLast {
                    val apkDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
                    val src = File(apkDir, "app-release.apk")
                    val dst = File(apkDir, "ShieiExam-Android-v${variant.versionName}.apk")
                    if (src.exists()) {
                        src.copyTo(dst, overwrite = true)
                    }
                }
            }
        } else if (variant.buildType.name == "debug") {
            variant.assembleProvider.configure {
                doLast {
                    val apkDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
                    val src = File(apkDir, "app-debug.apk")
                    val dst = File(apkDir, "ShieiExam-Android-v${variant.versionName}.apk")
                    if (src.exists()) {
                        src.copyTo(dst, overwrite = true)
                    }
                }
            }
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
