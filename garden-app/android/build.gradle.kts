buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Algunos plugins (ej. flutter_facebook_auth) no fijan su propio JVM target y
// terminan tomando el default de Gradle (21 para Kotlin, 1.8 para Java vía
// javac), lo que rompe compileReleaseKotlin con "Inconsistent JVM-target
// compatibility". Forzamos JVM 11 en todos los subproyectos — mismo valor
// que ya usa :app — para que coincidan entre sí.
subprojects {
    project.evaluationDependsOn(":app")
    // :app ya fija esto explícitamente en su propio build.gradle.kts, y para
    // cuando este bloque le toca (evaluationDependsOn de otro subproyecto ya
    // lo evaluó antes), afterEvaluate en :app revienta con "already evaluated".
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_11
                    targetCompatibility = JavaVersion.VERSION_11
                }
            }
            tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
