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
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    // Makes the Google Services plugin available but doesn't apply it globally
    id("com.google.gms.google-services") version "4.4.2" apply false
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Ensures :app is evaluated before other subprojects (important for multi-module builds)
subprojects {
    project.evaluationDependsOn(":app")
}

// Define the clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
