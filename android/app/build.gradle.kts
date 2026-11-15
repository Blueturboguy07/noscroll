plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Sign in with publik needs the publik app token (pat_) in the build: PUBLIK_APP_TOKEN at build
// time (CI: the repo secret), else publik-app-token.txt at the repo root. The token is public by
// design: it only mints capped keys for this app. Never put a pk_ key here.
val publikAppToken: String = (
    System.getenv("PUBLIK_APP_TOKEN")?.trim()?.takeIf { it.isNotEmpty() }
        ?: rootProject.file("../publik-app-token.txt").takeIf { it.isFile }?.readText()?.trim()
        ?: ""
    ).filter { it.isLetterOrDigit() || it == '_' || it == '-' }

// Sign in with publik gate mode, one setting: "required" (default: the app opens with Sign in with
// publik, with no way past it) or "optional" (the app opens without it; Sign in with publik is on
// the Status screen, and usage counting starts only after sign-in). PUBLIK_GATE_MODE at build
// time, or ./gradlew -PpublikGateMode=optional.
val publikGateMode: String = (System.getenv("PUBLIK_GATE_MODE") ?: findProperty("publikGateMode")?.toString() ?: "required")
    .trim().lowercase().let { if (it == "optional") "optional" else "required" }

android {
    namespace = "app.noscroll"
    compileSdk = 34

    defaultConfig {
        applicationId = "app.noscroll"
        minSdk = 26
        targetSdk = 34
        versionCode = 5
        versionName = "0.1.4"
        buildConfigField("String", "PUBLIK_APP_TOKEN", "\"$publikAppToken\"")
        buildConfigField("String", "PUBLIK_GATE_MODE", "\"$publikGateMode\"")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    buildFeatures { buildConfig = true }

    buildTypes {
        release { isMinifyEnabled = false }
    }
}

// A release build must carry the publik app token (pat_): without it, Sign in with publik cannot work.
// Debug builds keep working without it (the app then asks for a new build).
val checkPublikAppToken by tasks.registering {
    val tokenOk = publikAppToken.startsWith("pat_")
    doLast {
        if (!tokenOk) {
            throw GradleException(
                "This release build has no publik app token (pat_). Set PUBLIK_APP_TOKEN or add publik-app-token.txt at the repo root.",
            )
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach { dependsOn(checkPublikAppToken) }

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // Custom Tabs: the publik sign-in page opens in the browser, over the app.
    implementation("androidx.browser:browser:1.8.0")
    testImplementation("junit:junit:4.13.2")
    // The real org.json for JVM unit tests (android.jar has only stubs).
    testImplementation("org.json:json:20240303")
}
