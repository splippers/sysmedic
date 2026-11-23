plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "uk.splippers.sysmedic"
    compileSdk = 34
    defaultConfig { applicationId = "uk.splippers.sysmedic"; minSdk = 30; targetSdk = 34; versionCode = 1; versionName = "0.1.0" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")        // sideloaded onto our own phones; replace before any wider distribution
        }
    }
    testOptions { unitTests.isReturnDefaultValues = true }
}
dependencies {
    testImplementation("junit:junit:4.13.2")
}
