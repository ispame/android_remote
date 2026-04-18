plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.multiplatform")
    id("org.jetbrains.kotlin.plugin.compose")
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions {
                jvmTarget = "17"
            }
        }
    }
    iosX64()
    iosArm64()
    iosSimulatorArm64()

    sourceSets {
        val commonMain by getting {
            dependencies {
                @OptIn(org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi::class)
                dependencies {
                    implementation(compose.runtime)
                    implementation(compose.foundation)
                    implementation(compose.material3)
                    implementation(compose.material.icons.extended)
                    implementation(compose.ui)
                    implementation(compose.ui.graphics)
                    implementation(compose.components.resources)
                    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
                    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")
                    implementation("io.ktor:ktor-client-core:2.3.7")
                    implementation("io.ktor:ktor-client-websockets:2.3.7")
                    implementation("io.ktor:ktor-client-content-negotiation:2.3.7")
                    implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.7")
                }
            }
        }
        val androidMain by getting {
            dependencies {
                implementation("androidx.core:core-ktx:1.12.0")
                implementation("androidx.activity:activity-compose:1.8.2")
                implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.6.2")
                implementation("androidx.datastore:datastore-preferences:1.0.0")
                implementation("io.ktor:ktor-client-okhttp:2.3.7")
            }
        }
        val iosMain by getting {
            dependencies {
                implementation("io.ktor:ktor-client-darwin:2.3.7")
            }
        }
    }
}

android {
    namespace = "com.openclaw.remote.shared"
    compileSdk = 34
}
