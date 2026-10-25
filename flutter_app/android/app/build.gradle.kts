plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}
val workspace = rootProject.projectDir.parentFile.parentFile
val signingPasswordFile = workspace.resolve(".tools/signing/password.txt")
val signingKey = workspace.resolve(".tools/signing/development.jks")
val hasLocalSigning = signingPasswordFile.exists() && signingKey.exists()
val signingPassword = if (hasLocalSigning) signingPasswordFile.readText().trim() else ""
android {
    namespace = "com.qinglong.mobile"
    compileSdk = 36
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.qinglong.mobile"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (hasLocalSigning) create("existing") {
            storeFile = workspace.resolve(".tools/signing/development.jks")
            storePassword = signingPassword
            keyAlias = "qinglong-development"
            keyPassword = signingPassword
        }
    }
    buildTypes {
        // All variants must cover-install without changing the app identity.
        debug { if (hasLocalSigning) signingConfig = signingConfigs.getByName("existing") }
        getByName("profile") { if (hasLocalSigning) signingConfig = signingConfigs.getByName("existing") }
        release {
            if (hasLocalSigning) signingConfig = signingConfigs.getByName("existing")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}
flutter { source = "../.." }
dependencies { implementation("com.cronutils:cron-utils:9.2.1") }
