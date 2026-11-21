import groovy.lang.Closure
import javax.inject.Inject
import org.gradle.api.Action
import org.gradle.api.Project
import org.gradle.api.artifacts.dsl.RepositoryHandler
import org.gradle.api.plugins.ExtensionAware
import org.gradle.process.ExecOperations
import org.gradle.process.ExecSpec
import org.gradle.process.JavaExecSpec

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
        // Aliyun mirrors come first: dl.google.com serves 404 for artifact
        // downloads from restricted regions while general Google endpoints
        // stay reachable. Original repos remain as fallback.
        maven("https://maven.aliyun.com/repository/gradle-plugin")
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
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

abstract class LegacyExecOperationsHolder @Inject constructor(
    val execOperations: ExecOperations,
)

fun configureWithClosure(target: Any, configureClosure: Closure<*>) {
    val cloned = configureClosure.clone() as Closure<*>
    cloned.delegate = target
    cloned.resolveStrategy = Closure.DELEGATE_FIRST
    if (cloned.maximumNumberOfParameters == 0) {
        cloned.call()
    } else {
        cloned.call(target)
    }
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

fun installProjectExecCompat(project: Project) {
    val extra = project.extensions.extraProperties
    val execOps = project.objects.newInstance(LegacyExecOperationsHolder::class.java).execOperations
    if (!extra.has("exec")) {
        extra.set(
            "exec",
            object : Closure<Any?>(project, project) {
                @Suppress("unused")
                fun doCall(configureClosure: Closure<*>): Any =
                    execOps.exec { configureWithClosure(this, configureClosure) }

                @Suppress("unused")
                fun doCall(action: Action<in ExecSpec>): Any = execOps.exec(action)
            },
        )
    }
    if (!extra.has("javaexec")) {
        extra.set(
            "javaexec",
            object : Closure<Any?>(project, project) {
                @Suppress("unused")
                fun doCall(configureClosure: Closure<*>): Any =
                    execOps.javaexec { configureWithClosure(this, configureClosure) }

                @Suppress("unused")
                fun doCall(action: Action<in JavaExecSpec>): Any = execOps.javaexec(action)
            },
        )
    }
}

gradle.projectsLoaded {
    allprojects {
        installJcenterCompat(repositories)
        installJcenterCompat(buildscript.repositories)
        installProjectExecCompat(this)
    }
}

include(":app")
