import groovy.lang.Closure
import org.gradle.api.artifacts.dsl.RepositoryHandler
import org.gradle.api.plugins.ExtensionAware

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.3.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
}

fun installJcenterCompat(repositories: RepositoryHandler) {
    val extensionAware = repositories as? ExtensionAware ?: return
    val extra = extensionAware.extensions.extraProperties
    if (!extra.has("jcenter")) {
        extra.set(
            "jcenter",
            object : Closure<Any?>(repositories, repositories) {
                @Suppress("unused")
                fun doCall(): Any = repositories.mavenCentral()

                @Suppress("unused")
                fun doCall(ignored: Any?): Any = repositories.mavenCentral()
            },
        )
    }
}

gradle.projectsLoaded {
    allprojects {
        installJcenterCompat(repositories)
        installJcenterCompat(buildscript.repositories)
    }
}

include(":app")
