apply(from = "namespace_fix.gradle")

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
    configurations.configureEach {
        resolutionStrategy {
            force("androidx.glance:glance:1.1.1")
            force("androidx.glance:glance-appwidget:1.1.1")
            force("androidx.work:work-runtime-ktx:2.9.1")
            force("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
            componentSelection {
                all {
                    if (candidate.group == "androidx.glance" && candidate.version.contains("alpha")) {
                        reject("Avoid Glance alpha builds that require SDK 37 / AGP 9.1")
                    }
                    if (candidate.group == "androidx.compose.remote" && candidate.version.contains("alpha")) {
                        reject("Avoid Compose Remote alpha builds pulled by newer Glance alpha")
                    }
                }
            }
        }
    }
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
