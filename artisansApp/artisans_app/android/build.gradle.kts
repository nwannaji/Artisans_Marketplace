// android/build.gradle.kts

buildscript {
    val kotlinVersion = "1.8.21"
    val agpVersion = "8.7.3"

    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
        classpath("com.android.tools.build:gradle:$agpVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // Force all subprojects to use the same AGP version
    // This prevents plugin conflicts where subplugins try to download different AGP versions
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "com.android.tools.build") {
                useVersion("8.7.3")
                because("Force all subprojects to use the same AGP version")
            }
        }
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