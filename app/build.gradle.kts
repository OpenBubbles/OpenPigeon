import java.util.Properties

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

android {
    namespace = "com.openbubbles.openpigeon"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.openbubbles.openpigeon"
        minSdk = 26
        versionCode = 1
        targetSdk = 35
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        androidResources {
            ignoreAssetsPattern = "!.svn:!.git:!.gitignore:!.ds_store:!*.scc:<dir>_*:!CVS:!thumbs.db:!picasa.ini:!*~"
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
        getByName("release") {
            assets.setSrcDirs(files(project.layout.buildDirectory.dir("generated/release_assets")))
        }
        getByName("debug") {
            assets.setSrcDirs(files( project.layout.projectDirectory.dir("src/main/assets")))
        }
        getByName("main") {
            assets.setSrcDirs(files())
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
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    implementation(libs.godot)
    implementation(libs.androidx.activity.ktx)

    val composeBom = platform("androidx.compose:compose-bom:2025.05.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    // Choose one of the following:
    // Material Design 3
    implementation(libs.androidx.material3)

    implementation(libs.androidx.ui.tooling.preview)
    debugImplementation(libs.androidx.ui.tooling)

    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.glance.preview)
    implementation(libs.androidx.glance.appwidget.preview)

    implementation(libs.mixpanel.android)
}

tasks.register<Exec>("importGodotAssets") {
    description = "Imports Godot assets to ensure .godot cache exists (Fixes Grey Screen)."
    group = "godot"

    val projectPath = project.layout.projectDirectory.dir("src/main/assets")
    val godotHiddenFolder = projectPath.dir(".godot")

    inputs.files(fileTree(projectPath).matching { exclude(".godot/**") })
    outputs.dir(godotHiddenFolder)

    commandLine(godotCmd, "--headless", "--path", projectPath, "--editor", "--quit")
}

tasks.register<Exec>("exportGodotRelease") {
    description = "Exports the Godot project for release."
    group = "godot"

    dependsOn("importGodotAssets")

    workingDir = rootProject.projectDir
    val projectPath = project.layout.projectDirectory.dir("src/main/assets")
    val exportZipPath = project.layout.buildDirectory.file("godot_export.zip")

    inputs.dir(projectPath).withPathSensitivity(PathSensitivity.RELATIVE)
    outputs.file(exportZipPath)

    commandLine(godotCmd, "--headless", "--path", projectPath, "--export-pack", "Android", exportZipPath.get().asFile.absolutePath)

    doFirst {
        exportZipPath.get().asFile.parentFile.mkdirs()
    }
}

tasks.register<Copy>("unzipGodotRelease") {
    description = "Unzips the exported Godot project for the release build."
    group = "godot"

    dependsOn("exportGodotRelease")

    val exportZipPath = tasks.named<Exec>("exportGodotRelease").get().outputs.files.singleFile

    from(zipTree(exportZipPath))
    into(project.layout.buildDirectory.dir("generated/release_assets"))
}

tasks.register<Copy>("copyMissingAssets") {
    description = "Copy missing texture from original assets folder."
    group = "godot"

    dependsOn("unzipGodotRelease")

    from(project.layout.projectDirectory.dir("src/main/assets/.godot/imported")) {
        include("RedCupAlbedo.png-*.s3tc.ctex")
    }
    into(project.layout.buildDirectory.dir("generated/release_assets/.godot/imported"))
}

tasks.register<Copy>("copyOtherAssets") {
    description = "Copies the other misc assets files to the build directory."
    group = "godot"

    dependsOn("copyMissingAssets")

    from(project.layout.projectDirectory.dir("src/main/assets")) {
        include("attributions.html")
    }
    into(project.layout.buildDirectory.dir("generated/release_assets"))
}

tasks.whenTaskAdded {
    if (name == "preReleaseBuild") {
        dependsOn(tasks.named("importGodotAssets"))
    }
}

tasks.whenTaskAdded {
    if (name == "mergeReleaseAssets" || name.startsWith("lintVital") || name.startsWith("generateReleaseLint")) {
        dependsOn(tasks.named<Copy>("copyOtherAssets"))
    }
}
