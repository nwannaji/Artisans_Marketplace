// android/build.gradle.kts

buildscript {
    val kotlin_version = "1.8.21"// Updated Kotlin version
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version")
        classpath("com.android.tools.build:gradle:8.7.3")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.8.21")
        classpath ("com.google.gms:google-services:4.3.15")

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

// Fix namespace for Flutter plugins that don't specify one (required by AGP 8.x)
subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library")) {
            project.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { ext ->
                if (ext.namespace == null) {
                    ext.namespace = project.group.toString().replace("-", ".")
                }
            }
        }
    }
}

// Ensures :app is evaluated before other subprojects (important for multi-module builds)
subprojects {
    project.evaluationDependsOn(":app")
}

// Define the clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
