import java.net.HttpURLConnection
import java.net.URI
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Properties
import java.util.zip.ZipFile

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
val skipGodot = project.hasProperty("skipGodot")

val playerIoAar = file("libs/PlayerIO.aar")

val playerIoExpectedVersion = "3.9.0"
val playerIoDownloadPageUrl = "https://playerio.com/download/"
val playerIoSdkUrl =
    "https://playerio.com/download/PlayerIO%20SDK.zip"

val playerIoSdkZip =
    layout.buildDirectory.file(
        "tmp/playerio/PlayerIO-SDK.zip"
    )

fun openPlayerIoConnection(
    url: String
): HttpURLConnection {
    return (
            URI(url)
                .toURL()
                .openConnection() as HttpURLConnection
            ).apply {
            instanceFollowRedirects = true
            connectTimeout = 15_000
            readTimeout = 120_000
            requestMethod = "GET"

            setRequestProperty(
                "User-Agent",
                "OpenPigeon-Gradle"
            )
        }
}

fun verifyPlayerIoAar(
    aarFile: File
) {
    if (!aarFile.isFile) {
        throw GradleException(
            "PlayerIO AAR was not created: ${aarFile.absolutePath}"
        )
    }

    if (aarFile.length() < 1024L) {
        throw GradleException(
            "Downloaded PlayerIO AAR is unexpectedly small " +
                    "(${aarFile.length()} bytes)."
        )
    }

    try {
        ZipFile(aarFile).use { aar ->
            if (aar.getEntry("AndroidManifest.xml") == null) {
                throw GradleException(
                    "PlayerIO.aar does not contain AndroidManifest.xml."
                )
            }

            if (aar.getEntry("classes.jar") == null) {
                throw GradleException(
                    "PlayerIO.aar does not contain classes.jar."
                )
            }
        }
    } catch (error: GradleException) {
        throw error
    } catch (error: Exception) {
        throw GradleException(
            "PlayerIO.aar is not a valid Android AAR.",
            error
        )
    }
}

fun replaceFileAtomically(
    source: File,
    destination: File
) {
    destination.parentFile.mkdirs()

    try {
        Files.move(
            source.toPath(),
            destination.toPath(),
            StandardCopyOption.REPLACE_EXISTING,
            StandardCopyOption.ATOMIC_MOVE
        )
    } catch (_: AtomicMoveNotSupportedException) {
        Files.move(
            source.toPath(),
            destination.toPath(),
            StandardCopyOption.REPLACE_EXISTING
        )
    }
}

val preparePlayerIoSdk by tasks.registering {
    group = "setup"

    description =
        "Downloads and extracts the PlayerIO Android SDK when PlayerIO.aar is missing."

    outputs.file(playerIoAar)

    doLast {
        if (playerIoAar.exists()) {
            verifyPlayerIoAar(
                playerIoAar
            )

            logger.lifecycle(
                "Using existing PlayerIO SDK: ${playerIoAar.absolutePath}"
            )

            return@doLast
        }

        logger.lifecycle(
            "PlayerIO.aar is not installed. " +
                    "Preparing PlayerIO SDK v$playerIoExpectedVersion..."
        )

        val versionConnection =
            openPlayerIoConnection(
                playerIoDownloadPageUrl
            )

        val downloadPage = try {
            val responseCode =
                versionConnection.responseCode

            if (responseCode !in 200..299) {
                throw GradleException(
                    "Unable to verify the PlayerIO SDK version. " +
                            "playerio.com returned HTTP $responseCode."
                )
            }

            versionConnection
                .inputStream
                .bufferedReader()
                .use {
                    it.readText()
                }
        } finally {
            versionConnection.disconnect()
        }

        if (
            !downloadPage.contains(
                "v$playerIoExpectedVersion"
            )
        ) {
            throw GradleException(
                """
                PlayerIO's download page no longer advertises SDK v$playerIoExpectedVersion.

                OpenPigeon intentionally will not download a different PlayerIO SDK automatically
                because Crazy 8 has been tested against v$playerIoExpectedVersion.

                Check https://playerio.com/download/ and update OpenPigeon's PlayerIO version
                only after the newer SDK has been tested with Crazy 8.
                """.trimIndent()
            )
        }

        val sdkZip =
            playerIoSdkZip
                .get()
                .asFile

        sdkZip.parentFile.mkdirs()

        val partialZip =
            File(
                sdkZip.parentFile,
                "${sdkZip.name}.part"
            )

        partialZip.delete()
        sdkZip.delete()

        logger.lifecycle(
            "Downloading PlayerIO SDK v$playerIoExpectedVersion..."
        )

        val downloadConnection =
            openPlayerIoConnection(
                playerIoSdkUrl
            )

        try {
            val responseCode =
                downloadConnection.responseCode

            if (responseCode !in 200..299) {
                throw GradleException(
                    "PlayerIO SDK download failed with HTTP $responseCode."
                )
            }

            downloadConnection
                .inputStream
                .buffered()
                .use { input ->

                    partialZip
                        .outputStream()
                        .buffered()
                        .use { output ->

                            input.copyTo(
                                output
                            )
                        }
                }
        } catch (error: Exception) {
            partialZip.delete()

            if (error is GradleException) {
                throw error
            }

            throw GradleException(
                "Unable to download the PlayerIO SDK.",
                error
            )
        } finally {
            downloadConnection.disconnect()
        }

        if (
            !partialZip.exists() ||
            partialZip.length() < 1024L
        ) {
            partialZip.delete()

            throw GradleException(
                "PlayerIO SDK download was empty or incomplete."
            )
        }

        replaceFileAtomically(
            partialZip,
            sdkZip
        )

        playerIoAar.parentFile.mkdirs()

        val temporaryAar =
            File(
                playerIoAar.parentFile,
                "${playerIoAar.name}.part"
            )

        temporaryAar.delete()

        try {
            ZipFile(
                sdkZip
            ).use { sdk ->
                val aarEntry =
                    sdk.entries()
                        .asSequence()
                        .firstOrNull { entry ->

                            if (entry.isDirectory) {
                                false
                            } else {
                                val path =
                                    entry.name.replace(
                                        '\\',
                                        '/'
                                    )

                                path == "Android/PlayerIO.aar" ||
                                        path.endsWith(
                                            "/Android/PlayerIO.aar"
                                        )
                            }
                        }
                        ?: throw GradleException(
                            "The PlayerIO SDK ZIP does not contain Android/PlayerIO.aar."
                        )

                sdk.getInputStream(
                    aarEntry
                ).use { input ->

                    temporaryAar
                        .outputStream()
                        .buffered()
                        .use { output ->

                            input.copyTo(
                                output
                            )
                        }
                }
            }

            verifyPlayerIoAar(
                temporaryAar
            )

            replaceFileAtomically(
                temporaryAar,
                playerIoAar
            )

            logger.lifecycle(
                "PlayerIO SDK v$playerIoExpectedVersion installed at " +
                        playerIoAar.absolutePath
            )
        } catch (error: Exception) {
            temporaryAar.delete()

            if (error is GradleException) {
                throw error
            }

            throw GradleException(
                "Unable to extract PlayerIO.aar from the PlayerIO SDK.",
                error
            )
        } finally {
            temporaryAar.delete()
            sdkZip.delete()
        }
    }
}

val playerIoDependency =
    files(
        playerIoAar
    ).builtBy(
        preparePlayerIoSdk
    )

if (!playerIoAar.exists()) {
    logger.lifecycle(
        "PlayerIO.aar is not present yet. " +
                "Gradle will download it automatically when required."
    )
}

val configFile = file("$rootDir/config.properties")
if (!configFile.exists()) {
    throw GradleException(
        """
        Missing required file: config.properties

        Create it in the repository root with your own Player.IO credentials:

          PIO_GAME_ID=your-game-id
          PIO_SHARED_SECRET=your-shared-secret

        Obtain both from your Player.IO dashboard. Do not commit this file.

        See CONTRIBUTING.md.
        """.trimIndent()
    )
}

val props = Properties()
configFile.inputStream().use { props.load(it) }

listOf("PIO_GAME_ID", "PIO_SHARED_SECRET").forEach { key ->
    if (props[key]?.toString().isNullOrBlank()) {
        throw GradleException("config.properties is missing a value for $key. See CONTRIBUTING.md.")
    }
}

val godotProjectDir = layout.projectDirectory.dir("src/main/assets")
val generatedGodotRoot = layout.buildDirectory.dir("generated/godotAssets")
val debugGodotAssetsDir = generatedGodotRoot.map { it.dir("debug") }
val releaseGodotAssetsDir = generatedGodotRoot.map { it.dir("release") }
val godotExportZip = layout.buildDirectory.file("intermediates/godot/release/godot_export.zip")

val androidOnlyAssetDirs = listOf(
    "knockout",
    "golf",
    "shuffle"
)

fun releaseDateCode(): Int {
    val datePart = SimpleDateFormat("yyMMdd", Locale.US).format(Date())
    val dailyRelease = (project.findProperty("dailyRelease") as String?) ?: "01"
    return "$datePart$dailyRelease".toInt()
}

android {
    namespace = "com.openbubbles.openpigeon"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.openbubbles.openpigeon"
        minSdk = 26
        versionCode = releaseDateCode()
        targetSdk = 36
        versionName = "1.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        androidResources {
            ignoreAssetsPattern =
                "!.svn:!.git:!.gitignore:!.ds_store:!*.scc:<dir>_*:!CVS:!thumbs.db:!picasa.ini:!*~:!~*"
        }

        buildConfigField("String", "PIO_SHARED_SECRET", "\"${props["PIO_SHARED_SECRET"]}\"")
        buildConfigField("String", "PIO_GAME_ID", "\"${props["PIO_GAME_ID"]}\"")

        externalNativeBuild {
            cmake {
                cppFlags += ""
                arguments += "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON"
            }
        }
    }

    buildFeatures {
        aidl = true
        viewBinding = true
        buildConfig = true
        compose = true
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

    packaging {
        jniLibs {
            useLegacyPackaging = false
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
    implementation(libs.androidx.media3.common.ktx)
    implementation(playerIoDependency)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    implementation(libs.godot)
    implementation(libs.androidx.activity.ktx)

    val composeBom = platform("androidx.compose:compose-bom:2025.05.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)
    implementation("androidx.compose.runtime:runtime")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test:runner:1.5.2")
    androidTestImplementation("androidx.test:rules:1.5.0")

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
 * directory layout there. That is not ideal from Gradle's perspective, but all
 * Android consumers are isolated from it by reading only build/generated/...
 *
 * .import and .uid files are declared as outputs rather than inputs because the
 * Godot editor rewrites them during import. Treating them as inputs made this
 * task dirty its own inputs, so it could never be UP-TO-DATE.
 */
val importGodotAssets by tasks.registering(Exec::class) {
    description = "Imports Godot assets so .godot cache exists."
    group = "godot"

    val godotHiddenFolder = godotProjectDir.dir(".godot")

    inputs.files(fileTree(godotProjectDir) {
        exclude(".godot/**")
        exclude("addons/**/bin/~*")
        exclude("**/*.import")
        exclude("**/*.uid")
        exclude("**/*.tmp")
    }).withPathSensitivity(PathSensitivity.RELATIVE)

    outputs.dir(godotHiddenFolder)
    outputs.files(fileTree(godotProjectDir) {
        include("**/*.import")
        include("**/*.uid")
    })

    doFirst {
        fileTree(godotProjectDir) {
            include("addons/**/bin/~*")
            include("**/*.tmp")
        }.forEach { file ->
            if (file.exists() && !file.delete()) {
                logger.warn("Unable to delete temporary Godot file: ${file.absolutePath}. It may be in use.")
            }
        }
    }

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

    from(godotProjectDir) {
        exclude("addons/**/bin/~*")
        exclude("addons/**/bin/*.dll")
        exclude("addons/**/bin/*.dylib")
        exclude("addons/**/bin/*.exe")
        exclude("addons/**/bin/*.pdb")
        exclude("addons/**/bin/*windows*")
        exclude("addons/**/bin/*macos*")
        exclude("addons/**/bin/*linux*")
        exclude("**/*.tmp")
        exclude(".godot/editor/**")
        exclude(".godot/shader_cache/**")
        exclude(".godot/exported/**")
        exclude("addons/**/bin/*.wasm")
        exclude("addons/**/bin/*.exp")
        exclude("addons/**/bin/*.lib")
        exclude("addons/**/bin/*ios*")
        exclude(".godot/imported/**/*.s3tc.ctex")
    }

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

    inputs.files(fileTree(godotProjectDir) {
        exclude("addons/**/bin/~*")
    }).withPathSensitivity(PathSensitivity.RELATIVE)
    outputs.file(godotExportZip)

    doFirst {
        godotExportZip.get().asFile.parentFile.mkdirs()
    }

    commandLine(
        godotCmd,
        "--headless",
        "--verbose",
        "--path",
        godotProjectDir.asFile.absolutePath,
        "--export-pack",
        "Android",              // <-- must match a preset NAME in export_presets.cfg
        godotExportZip.get().asFile.absolutePath,
        "--quit"
    )
}

val prepareGodotReleaseAssets by tasks.registering(Sync::class) {
    description = "Prepares Godot-backed Android assets for the release build."
    group = "godot"

    dependsOn(exportGodotRelease)

    from(zipTree(godotExportZip))
    into(releaseGodotAssetsDir)

    includeEmptyDirs = false

    doFirst {
        delete(releaseGodotAssetsDir.get().asFile)
    }

    from(godotProjectDir) {
        include("attributions.html")
        include("global/gp_wg_*.txt")
    }

    androidOnlyAssetDirs.forEach { assetDir ->
        from(godotProjectDir.dir(assetDir)) {
            into(assetDir)
            exclude(".gdignore")
        }
    }

    from(godotProjectDir) {
        include("global/settings.png")
    }
}

tasks.configureEach {
    if (skipGodot) return@configureEach
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
        "generateReleaseLintVitalReportModel",
        "lintAnalyzeRelease",
        "lintVitalAnalyzeRelease",
        "lintVitalReportRelease",
        "packageRelease" -> dependsOn(prepareGodotReleaseAssets)
    }
}