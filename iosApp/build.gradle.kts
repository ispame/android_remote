plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.multiplatform")
}

kotlin {
    iosX64()
    iosArm64()
    iosSimulatorArm64()

    sourceSets {
        val iosMain by getting {
            dependencies {
                implementation(project(":shared"))
            }
        }
    }
}
