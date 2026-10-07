import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.jglhomer.player"
    compileSdk = 36

    // Fix Bug #2 (paso 1): Fijar versión NDK explícita para que audiotags
    // (libaudiotags.so) compile correctamente en todas las ABIs.
    // Si flutter.ndkVersion no empaqueta tu ABI, este valor fuerza la versión LTS.
    ndkVersion = "27.0.12077973"

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.jglhomer.player"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Fix Bug #2 (paso 2): Empaquetar libaudiotags.so para todas las
        // arquitecturas relevantes. Sin este bloque, Gradle puede omitir la
        // ABI del dispositivo de prueba y dlopen falla con "not found".
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Fix Bug #2 (paso 3): Asegurar que las librerías .so NO sean excluidas
    // ni comprimidas dentro del APK — requerido para dlopen en tiempo de ejecución.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation(files("libs/decoder_ffmpeg-release.aar"))
    implementation("dev.ffmpegkit-maintained:ffmpeg-kit-full:8.1.7")
    implementation("com.arthenica:smart-exception-java:0.2.1")
    implementation("androidx.core:core:1.13.1")
    implementation("androidx.media3:media3-common:1.4.1")
    implementation("androidx.media3:media3-exoplayer:1.4.1")
    // Fix Bug #3: DocumentFile necesario para operaciones SAF en SD Card
    implementation("androidx.documentfile:documentfile:1.0.1")
}
