plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.marcocheung.wherecanigo"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.marcocheung.wherecanigo"
        minSdk = 29
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

abstract class PrepareMapAssets : DefaultTask() {
    @get:InputDirectory
    abstract val sourceDirectory: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:Inject
    abstract val fileSystem: FileSystemOperations

    @TaskAction
    fun copyAssets() {
        fileSystem.sync {
            from(sourceDirectory) {
                include("world-countries.geojson", "countries.json", "default_visas_*.json", "airline_destinations.json")
            }
            into(outputDirectory)
        }
    }
}

val bundledMapAssets = tasks.register<PrepareMapAssets>("prepareBundledMapAssets") {
    sourceDirectory.set(rootProject.layout.projectDirectory.dir("../where-can-i-go-ios/whereCanIGo/Resources"))
    outputDirectory.set(layout.buildDirectory.dir("generated/mapAssets"))
}

androidComponents.onVariants { variant ->
    variant.sources.assets?.addGeneratedSourceDirectory(bundledMapAssets, PrepareMapAssets::outputDirectory)
}

dependencies {
    implementation(libs.maplibre.android)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui.tooling.preview)

    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.junit)
}
