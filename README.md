<div align="center">

<img src="./assets/images/logo-hd.png" width="100%" alt="I.A agent"/>

---

# I.A agent - Android Runbook (Windows)

### Exact Setup + All Hurdles We Passed

[![Flutter](https://img.shields.io/badge/Flutter-3.32.4-02569B?style=for-the-badge&logo=flutter&logoColor=white)](#)
[![Dart](https://img.shields.io/badge/Dart-3.8.1-0175C2?style=for-the-badge&logo=dart&logoColor=white)](#)
[![Android SDK](https://img.shields.io/badge/Android%20SDK-36-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#)
[![NDK](https://img.shields.io/badge/NDK-27.0.12077973-34A853?style=for-the-badge)](#)
[![Min SDK](https://img.shields.io/badge/Min%20SDK-24-F97316?style=for-the-badge)](#)
[![Platform](https://img.shields.io/badge/Platform-Windows%2011-0078D4?style=for-the-badge&logo=windows&logoColor=white)](#)
[![Build](https://img.shields.io/badge/APK-Debug%20Built-16A34A?style=for-the-badge)](#)

<br/>

**Verified build output**: `build/app/outputs/flutter-apk/app-debug.apk`  
**Verified date**: February 24, 2026

</div>

---

## 1. What This README Solves

This project does **not** run on a fresh Windows machine with only `flutter pub get`.

During setup, we hit multiple blockers:
- Missing Android Gradle app file and wrapper in repo.
- Missing model assets required by `pubspec.yaml`.
- Native plugin (`opus_flutter_android`) breaks if paths include spaces.
- `record_android` / `flutter_sound` required higher `minSdk`.
- `flutter_local_notifications` required core library desugaring.

This README gives the exact process so you can run it again reliably.

---

## 2. Critical Rule (Do Not Skip)

Use a **no-space** working path for builds.

This repo folder is currently `D:\buddie app run` (contains spaces), which causes native NDK failures.

Create and use this junction:

```powershell
if (!(Test-Path 'D:\buddie_app_run')) {
  New-Item -ItemType Junction -Path 'D:\buddie_app_run' -Target 'D:\buddie app run' | Out-Null
}
Set-Location D:\buddie_app_run
```

---

## 3. One-Time Machine Setup (Windows)

### 3.1 Install required tools

```powershell
winget install --id Microsoft.OpenJDK.17 -e --accept-package-agreements --accept-source-agreements
winget install --id Google.AndroidStudio -e --accept-package-agreements --accept-source-agreements
winget install --id Google.PlatformTools -e --accept-package-agreements --accept-source-agreements
```

### 3.2 Install Flutter 3.32.4

```powershell
if (!(Test-Path 'C:\src')) { New-Item -ItemType Directory -Path 'C:\src' | Out-Null }
if (!(Test-Path 'C:\src\flutter')) {
  git clone https://github.com/flutter/flutter.git -b 3.32.4 --depth 1 C:\src\flutter
}
```

### 3.3 Create no-space Android SDK root and pub cache

```powershell
if (!(Test-Path 'C:\Android')) { New-Item -ItemType Directory -Path 'C:\Android' | Out-Null }
if (!(Test-Path 'C:\PubCache')) { New-Item -ItemType Directory -Path 'C:\PubCache' | Out-Null }
```

If your SDK is currently under `%LOCALAPPDATA%\Android\Sdk`, copy it:

```powershell
robocopy "$env:LOCALAPPDATA\Android\Sdk" "C:\Android\Sdk" /MIR /R:2 /W:2
```

### 3.4 Persist environment variables

```powershell
[Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot', 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', 'C:\Android\Sdk', 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', 'C:\Android\Sdk', 'User')
[Environment]::SetEnvironmentVariable('PUB_CACHE', 'C:\PubCache', 'User')
```

---

## 4. One-Time Project Setup

Run all commands from:

```powershell
Set-Location D:\buddie_app_run
```

### 4.1 Ensure local Android SDK path

`android/local.properties` must contain:

```properties
sdk.dir=C:\\Android\\Sdk
flutter.sdk=C:\\src\\flutter
```

### 4.2 Install required model assets

These assets are required by `pubspec.yaml` and runtime ASR code.

```powershell
$modelDir = 'C:\src\buddie_model_downloads'
if (!(Test-Path $modelDir)) { New-Item -ItemType Directory -Path $modelDir | Out-Null }

curl.exe -L "https://github.com/Buddie-AI/Buddie/releases/download/asr-models/sherpa-onnx-paraformer-zh-2024-03-09.tar.bz2" -o "$modelDir\sherpa-onnx-paraformer-zh-2024-03-09.tar.bz2"
curl.exe -L "https://github.com/Buddie-AI/Buddie/releases/download/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12.tar.bz2" -o "$modelDir\sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12.tar.bz2"
curl.exe -L "https://github.com/Buddie-AI/Buddie/releases/download/kws-models/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2" -o "$modelDir\sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2"
curl.exe -L "https://github.com/Buddie-AI/Buddie/releases/download/vad-models/silero_vad.onnx" -o ".\assets\silero_vad.onnx"

tar -xjf "$modelDir\sherpa-onnx-paraformer-zh-2024-03-09.tar.bz2" -C ".\assets"
tar -xjf "$modelDir\sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12.tar.bz2" -C ".\assets"
tar -xjf "$modelDir\sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2" -C ".\assets"
```

Expected folders/files:
- `assets/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01/`
- `assets/sherpa-onnx-paraformer-zh-2024-03-09/`
- `assets/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12/`
- `assets/silero_vad.onnx`

### 4.3 Keep these local matrix files

Required by runtime code:
- `assets/idct_weight.json`
- `assets/ipca_weight.json`

Current repo contains placeholders (`[]`) so app can build; replace with real values if your BLE voiceprint flow depends on them.

### 4.4 Patch `opus_flutter_android` in pub cache (required)

This plugin ships with `minSdkVersion 19`, which fails with current NDK.

```powershell
$f = "C:\PubCache\hosted\pub.dev\opus_flutter_android-3.0.1\android\build.gradle"
(Get-Content $f) -replace 'minSdkVersion 19','minSdkVersion 21' | Set-Content $f -Encoding ASCII
```

If the package version changes, update the path accordingly.

---

## 5. Daily Run Commands (Next Time)

Open a new terminal and run:

```powershell
Set-Location D:\buddie_app_run

$env:JAVA_HOME='C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot'
$env:ANDROID_SDK_ROOT='C:\Android\Sdk'
$env:ANDROID_HOME='C:\Android\Sdk'
$env:PUB_CACHE='C:\PubCache'
$env:Path="C:\src\flutter\bin;C:\Android\Sdk\platform-tools;C:\Android\Sdk\cmdline-tools\latest\bin;$env:JAVA_HOME\bin;$env:Path"

flutter pub get
flutter devices
flutter run -d <your_android_device_id>
```

To build APK:

```powershell
flutter build apk --debug
```

Output:
- `build/app/outputs/flutter-apk/app-debug.apk`

---

## 6. Android Config Required in This Repo

`android/app/build.gradle.kts` requires:
- `minSdk = 24`
- `ndkVersion = "27.0.12077973"`
- `isCoreLibraryDesugaringEnabled = true`
- `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`

These are already present in this repo.

---

## 7. Hurdles We Hit and the Fixes

| Hurdle | Symptom | Fix |
|---|---|---|
| Missing Android app Gradle file | `unsupported Gradle project` | Added `android/app/build.gradle.kts` |
| Missing Gradle wrapper files | Build bootstrap failed | Added `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar` |
| Missing model assets | `unable to find directory entry in pubspec.yaml` | Downloaded model archives from Buddie releases and extracted into `assets/` |
| NDK path with spaces | `NDK path cannot contain spaces` | Moved SDK to `C:\Android\Sdk` and used no-space repo junction |
| Pub cache path with spaces | Native plugin path/toolchain issues | Set `PUB_CACHE=C:\PubCache` |
| `record_android` min sdk | Manifest merge error (needs 23) | Project `minSdk` raised |
| `flutter_sound` min sdk | Manifest merge error (needs 24) | Project `minSdk` set to 24 |
| `flutter_local_notifications` | AAR metadata requires desugaring | Enabled core library desugaring + dependency |
| `opus_flutter_android` old min sdk | NDK configure/build failure | Patched plugin `minSdkVersion` from 19 to 21 |

---

## 8. Current Repo State You Should Keep

Do not remove these files:
- `android/app/build.gradle.kts`
- `android/gradlew`
- `android/gradlew.bat`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `assets/silero_vad.onnx`
- `assets/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01/`
- `assets/sherpa-onnx-paraformer-zh-2024-03-09/`
- `assets/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12/`
- `assets/idct_weight.json`
- `assets/ipca_weight.json`

---

## 9. Fast Troubleshooting

### `flutter doctor` says Android Studio version unknown
This environment can still build/run Android as long as toolchain shows green and licenses are accepted.

### Kotlin daemon stack traces appear even when build succeeds
If `Built ... app-debug.apk` appears and APK exists, treat it as success.

### Device not found
Run:

```powershell
adb devices
flutter devices
```

Enable USB debugging on phone and accept RSA prompt.

---

## 10. Original Project Notes

Core app docs still apply:
- `README_ENV_CONFIG.md` for API key env setup
- `env` file for default LLM/ASR keys

---

<div align="center">

**I.A agent Android setup is now reproducible on Windows when following this runbook exactly.**

</div>
