import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Properties
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.Sync
import org.gradle.api.tasks.Exec
import org.gradle.kotlin.dsl.named
import org.gradle.kotlin.dsl.register

plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.jetbrainsKotlinAndroid)
    alias(libs.plugins.compose.compiler)
}

fun getGodotExecutable(project: Project): String {
    val localProps = Properties()
    val localPropsFile = project.rootProject.file("local.properties")
    if (localPropsFile.exists()) {
        localPropsFile.inputStream().use { localProps.load(it) }
        val path = localProps.getProperty("godot.path")
        if (!path.isNullOrBlank()) return path
    }
    return "godot"
}

val godotCmd = getGodotExecutable(project)

val props = Properties()
file("$rootDir/config.properties").inputStream().use { props.load(it) }

val godotProjectDir = layout.projectDirectory.dir("src/main/assets")
val generatedGodotRoot = layout.buildDirectory.dir("generated/godotAssets")
val debugGodotAssetsDir = generatedGodotRoot.map { it.dir("debug") }
val releaseGodotAssetsDir = generatedGodotRoot.map { it.dir("release") }
val godotExportZip = layout.buildDirectory.file("intermediates/godot/release/godot_export.zip")

fun releaseDateCode(): Int {
    val datePart = SimpleDateFormat("yyMMdd", Locale.US).format(Date())
    val dailyRelease = (project.findProperty("dailyRelease") as String?) ?: "01"
    return "$datePart$dailyRelease".toInt()
}

android {
    namespace = "com.openbubbles.openpigeon"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.openbubbles.openpigeon"
        minSdk = 26
        versionCode = releaseDateCode()
        targetSdk = 35
        versionName = "1.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        androidResources {
            ignoreAssetsPattern =
                "!.svn:!.git:!.gitignore:!.ds_store:!*.scc:<dir>_*:!CVS:!thumbs.db:!picasa.ini:!*~"
        }

        buildConfigField("String", "PIO_SHARED_SECRET", "\"${props["PIO_SHARED_SECRET"]}\"")
        buildConfigField("String", "PIO_GAME_ID", "\"${props["PIO_GAME_ID"]}\"")

        externalNativeBuild {
            cmake {
                cppFlags += ""
            }
        }
    }

    buildFeatures {
        aidl = true
        viewBinding = true
        buildConfig = true
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.2"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets {
        getByName("main") {
            // Main should not directly package assets anymore.
            assets.setSrcDirs(emptyList<File>())
        }

        getByName("debug") {
            assets.setSrcDirs(listOf(debugGodotAssetsDir))
        }

        getByName("release") {
            assets.setSrcDirs(listOf(releaseGodotAssetsDir))
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.navigation.fragment.ktx)
    implementation(libs.androidx.navigation.ui.ktx)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.ui.graphics.android)
    implementation(libs.androidx.media3.common.ktx)
    implementation(files("libs/PlayerIO.aar"))
    implementation(libs.androidx.ui)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    implementation(libs.godot)
    implementation(libs.androidx.activity.ktx)

    val composeBom = platform("androidx.compose:compose-bom:2025.05.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation(libs.androidx.material3)
    implementation(libs.androidx.ui.tooling.preview)
    debugImplementation(libs.androidx.ui.tooling)

    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.glance.preview)
    implementation(libs.androidx.glance.appwidget.preview)

    implementation(libs.mixpanel.android)
}

/**
 * Runs Godot import so .godot cache exists in the Godot project itself.
 *
 * Note:
 * This task writes into src/main/assets/.godot because Godot expects the project
 * directory layout there. That is not ideal from Gradle’s perspective, but all
 * Android consumers are isolated from it by reading only build/generated/...
 */
val importGodotAssets by tasks.registering(Exec::class) {
    description = "Imports Godot assets so .godot cache exists."
    group = "godot"

    val godotHiddenFolder = godotProjectDir.dir(".godot")

    inputs.files(fileTree(godotProjectDir) {
        exclude(".godot/**")
    }).withPathSensitivity(PathSensitivity.RELATIVE)

    outputs.dir(godotHiddenFolder)

    commandLine(
        godotCmd,
        "--headless",
        "--path",
        godotProjectDir.asFile.absolutePath,
        "--editor",
        "--quit"
    )
}

/**
 * Debug pipeline:
 * import -> sync whole project assets into build/generated/godotAssets/debug
 */
val prepareGodotDebugAssets by tasks.registering(Sync::class) {
    description = "Prepares Godot-backed Android assets for the debug build."
    group = "godot"

    dependsOn(importGodotAssets)

    from(godotProjectDir)
    into(debugGodotAssetsDir)

    includeEmptyDirs = false
}

/**
 * Release pipeline:
 * import -> export pack -> unzip -> overlay extra files
 */
val exportGodotRelease by tasks.registering(Exec::class) {
    description = "Exports the Godot project pack for release."
    group = "godot"

    dependsOn(importGodotAssets)

    inputs.dir(godotProjectDir).withPathSensitivity(PathSensitivity.RELATIVE)
    outputs.file(godotExportZip)

    doFirst {
        godotExportZip.get().asFile.parentFile.mkdirs()
    }

    commandLine(
        godotCmd,
        "--headless",
        "--path",
        godotProjectDir.asFile.absolutePath,
        "--export-pack",
        "Android",
        godotExportZip.get().asFile.absolutePath
    )
}

val prepareGodotReleaseAssets by tasks.registering(Sync::class) {
    description = "Prepares Godot-backed Android assets for the release build."
    group = "godot"

    dependsOn(exportGodotRelease)

    from(zipTree(godotExportZip))
    into(releaseGodotAssetsDir)

    includeEmptyDirs = false

    from(godotProjectDir.dir(".godot/imported")) {
        include("RedCupAlbedo.png-*.s3tc.ctex")
        into(".godot/imported")
    }

    from(godotProjectDir) {
        include("attributions.html")
    }
}

tasks.configureEach {
    when (name) {
        "mergeDebugAssets",
        "compressDebugAssets",
        "generateDebugLintReportModel",
        "lintAnalyzeDebug",
        "lintReportDebug",
        "packageDebug" -> dependsOn(prepareGodotDebugAssets)

        "mergeReleaseAssets",
        "compressReleaseAssets",
        "generateReleaseLintReportModel",
        "generateReleaseLintVitalReportModel", // add this
        "lintAnalyzeRelease",
        "lintVitalAnalyzeRelease",
        "lintVitalReportRelease",
        "packageRelease" -> dependsOn(prepareGodotReleaseAssets)
    }
}