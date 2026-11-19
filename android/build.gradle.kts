allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
subprojects {
    plugins.withId("com.android.library") {
        val androidExtension = extensions.findByName("android") ?: return@withId
        val getNamespace = androidExtension.javaClass.methods.firstOrNull {
            it.name == "getNamespace" && it.parameterCount == 0
        }
        val setNamespace = androidExtension.javaClass.methods.firstOrNull {
            it.name == "setNamespace" && it.parameterCount == 1
        }
        val currentNamespace = getNamespace?.invoke(androidExtension) as? String
        if (currentNamespace.isNullOrBlank()) {
            val sanitizedName = project.name.replace('-', '_')
            setNamespace?.invoke(androidExtension, "dev.landa.thirdparty.$sanitizedName")
        }

        fun ensureMinCompileSdk(dslExtension: Any) {
            val appAndroid = rootProject.findProject(":app")?.extensions?.findByName("android")
            val appCompileSdk = appAndroid?.javaClass?.methods
                ?.firstOrNull { it.name == "getCompileSdk" && it.parameterCount == 0 }
                ?.invoke(appAndroid) as? Int
            val targetCompileSdk = maxOf(appCompileSdk ?: 36, 34)

            val getCompileSdk = dslExtension.javaClass.methods.firstOrNull {
                it.name == "getCompileSdk" && it.parameterCount == 0
            }
            val currentCompileSdk = getCompileSdk?.invoke(dslExtension) as? Int
            if (currentCompileSdk == null || currentCompileSdk < targetCompileSdk) {
                val setCompileSdk = dslExtension.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdk" &&
                        it.parameterCount == 1 &&
                        (it.parameterTypes[0] == Int::class.javaObjectType ||
                            it.parameterTypes[0] == Int::class.javaPrimitiveType)
                }
                if (setCompileSdk != null) {
                    setCompileSdk.invoke(dslExtension, targetCompileSdk)
                } else {
                    val compileSdkVersionMethod = dslExtension.javaClass.methods.firstOrNull {
                        it.name == "compileSdkVersion" &&
                            it.parameterCount == 1 &&
                            (it.parameterTypes[0] == Int::class.javaPrimitiveType ||
                                it.parameterTypes[0] == Int::class.javaObjectType)
                    }
                    compileSdkVersionMethod?.invoke(dslExtension, targetCompileSdk)
                }
            }
        }

        val androidComponents = extensions.findByName("androidComponents")
        val finalizeDslAction = androidComponents?.javaClass?.methods?.firstOrNull {
            it.name == "finalizeDsl" &&
                it.parameterCount == 1 &&
                it.parameterTypes[0] == org.gradle.api.Action::class.java
        }
        val finalizeDslFn = androidComponents?.javaClass?.methods?.firstOrNull {
            it.name == "finalizeDsl" &&
                it.parameterCount == 1 &&
                it.parameterTypes[0] == Function1::class.java
        }
        when {
            finalizeDslAction != null -> {
                finalizeDslAction.invoke(
                    androidComponents,
                    object : org.gradle.api.Action<Any> {
                        override fun execute(dsl: Any) {
                            ensureMinCompileSdk(dsl)
                        }
                    },
                )
            }
            finalizeDslFn != null -> {
                val callback: (Any) -> Unit = { dsl -> ensureMinCompileSdk(dsl) }
                finalizeDslFn.invoke(androidComponents, callback)
            }
            else -> {
                afterEvaluate {
                    ensureMinCompileSdk(androidExtension)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
