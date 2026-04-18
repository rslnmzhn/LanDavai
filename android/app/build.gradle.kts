import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

fun readSigningValue(propertyName: String, environmentName: String): String? {
    val propertyValue = keystoreProperties
        .getProperty(propertyName)
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
    val environmentValue = providers.environmentVariable(environmentName)
        .orNull
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
    return propertyValue ?: environmentValue
}

val releaseStoreFilePath = readSigningValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = readSigningValue(
    "storePassword",
    "ANDROID_KEYSTORE_PASSWORD",
)
val releaseKeyAlias = readSigningValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = readSigningValue("keyPassword", "ANDROID_KEY_PASSWORD")

val hasReleaseSigning = listOf(
    releaseStoreFilePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

val requestedTaskNames = gradle.startParameter.taskNames.map { it.lowercase() }
val requiresReleaseSigning = requestedTaskNames.any { taskName ->
    taskName.contains("release")
}

android {
    namespace = "com.example.landa"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    defaultConfig {
        // Keep the release package identity stable so signed updates install
        // over previous release builds instead of looking like a new app.
        applicationId = "com.example.landa"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = false
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }

        getByName("profile") {
            applicationIdSuffix = ".profile"
            versionNameSuffix = "-profile"
        }

        getByName("release") {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

if (requiresReleaseSigning && !hasReleaseSigning) {
    throw GradleException(
        "Release builds must use a stable non-debug signing key. " +
            "Configure android/key.properties or ANDROID_KEYSTORE_* environment variables.",
    )
}

flutter {
    source = "../.."
}
