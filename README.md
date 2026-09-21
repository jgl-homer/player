# 🎵 Player

### Advanced Android Music Player • DSP • Epicenter • High-Quality Audio

> **Player** is a Flutter-based music player focused on local audio playback, custom DSP and an **Epicenter / Bass Restoration** engine.

The project is designed around a simple idea:

> **Keep the audio as clean and high-quality as possible while giving the user powerful control over the low end.**

The repository currently contains a custom local `just_audio` implementation under `plugins/just_audio_epicenter`, allowing the playback engine to be extended specifically for this project.

---

## 🚧 Project status

**Status:** Active development

This is a work-in-progress audio player. Some items described in the roadmap are planned rather than fully implemented.

The current repository is a Flutter project with a custom `just_audio` dependency, `audio_service`, `audio_session`, media-library access, metadata handling, local persistence and the custom Epicenter plugin.

---

## ✨ Vision

Player is being built as a serious local music player rather than a basic Flutter audio demo.

The long-term audio chain is:

```text
┌─────────────────────────┐
│       AUDIO FILE        │
│                         │
│ MP3 / FLAC / WAV / WMA  │
│ AAC / OGG / PCM / ...   │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│        DECODER          │
│                         │
│ Native / FFmpeg         │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│          PCM            │
│                         │
│ Preserve source format  │
│ whenever possible       │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│        DSP ENGINE       │
│                         │
│ Epicenter               │
│ Bass Restoration        │
│ EQ                      │
│ Gain                    │
│ Limiter                 │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│      AUDIO OUTPUT       │
│                         │
│ AudioTrack / AAudio     │
│ Android Audio HAL       │
│ USB DAC                 │
└────────────┬────────────┘
             │
             ▼
           🔊 DAC
```

---

# 🔊 Epicenter

The **Epicenter** is a core feature of Player.

It is intended to provide powerful low-frequency processing and bass restoration while remaining part of the main audio-processing chain.

### Processing concept

```text
Original Audio
      │
      ▼
    Decoder
      │
      ▼
      PCM
      │
      ▼
 ┌───────────────┐
 │   EPICENTER   │
 │               │
 │ Bass Restore  │
 │ Bass Process  │
 └───────┬───────┘
         │
         ▼
    Audio Output
```

The Epicenter is **not intended to be removed from the project**. It is one of the defining features of the player.

---

# 🎛️ DSP architecture

The DSP architecture is designed around processing decoded PCM rather than repeatedly converting compressed audio.

The target architecture is:

```text
SOURCE
  │
  ▼
DECODER
  │
  ▼
PCM
  │
  ▼
FLOAT DSP
  │
  ├── Epicenter
  ├── Bass Restoration
  ├── Equalizer
  ├── Gain
  └── Limiter
  │
  ▼
OUTPUT
```

Processing internally in floating point is useful for avoiding unnecessary quantization during DSP operations and for providing headroom for effects such as bass restoration and EQ.

---

# 🎧 High-quality audio

Player is intended to handle high-quality local files such as:

- FLAC
- WAV
- PCM
- MP3
- AAC
- WMA through an additional decoder/backend when implemented
- Other formats supported by the playback backend

A key design goal is:

> **Do not force every file into one fixed sample rate or bit depth when it is not necessary.**

For example:

```text
FLAC 24-bit / 96 kHz
        │
        ▼
      Decoder
        │
        ▼
PCM 24-bit / 96 kHz
        │
        ▼
       DSP
        │
        ▼
Output at 96 kHz
```

Likewise:

```text
WAV 16-bit / 44.1 kHz
        │
        ▼
      Decoder
        │
        ▼
PCM 16-bit / 44.1 kHz
        │
        ▼
       DSP
        │
        ▼
Output at 44.1 kHz
```

The exact physical output still depends on the Android device, audio HAL, DAC and selected output route.

---

# ⚠️ Hi-Res does not automatically mean bit-perfect

There is an important distinction between:

### Source quality

```text
FLAC 24-bit / 96 kHz
```

and:

### Physical output

```text
App
 ↓
Android audio stack
 ↓
Audio HAL
 ↓
DAC
```

A player can preserve 24/96 internally while the Android device later resamples the signal.

Therefore, the project aims to:

- Preserve source parameters whenever possible.
- Avoid unnecessary resampling.
- Use the highest-quality output path available.
- Detect hardware/output capabilities where possible.
- Avoid claiming bit-perfect playback on hardware that does not provide it.

---

# 🧩 Format support strategy

The project can use different decoding paths depending on the format.

```text
                 AUDIO FILE
                     │
          ┌──────────┴──────────┐
          │                     │
   Native/backend          FFmpeg
     decoding             when needed
          │                     │
          └──────────┬──────────┘
                     ▼
                    PCM
                     │
                     ▼
                    DSP
                     │
                     ▼
                  OUTPUT
```

The purpose is not to run every file through FFmpeg just because FFmpeg exists.

Instead:

> **Use the simplest appropriate decoder while preserving the audio path.**

FFmpeg is particularly useful for expanding compatibility to formats that Android/the current backend cannot handle directly, such as WMA.

---

# 📱 Platform

The project is built with:

- **Flutter**
- **Dart**
- **Android**
- iOS
- macOS
- Linux
- Windows
- Web project targets

Android is the primary target for the advanced audio functionality.

---

# 🏗️ Project structure

```text
player/
│
├── android/
│
├── ios/
│
├── linux/
│
├── macos/
│
├── web/
│
├── windows/
│
├── assets/
│   └── icon/
│
├── lib/
│   └── Application source
│
├── plugins/
│   └── just_audio_epicenter/
│       ├── android/
│       ├── ios/
│       ├── macos/
│       ├── web/
│       └── lib/
│
├── test/
│
├── pubspec.yaml
├── pubspec.lock
├── analysis_options.yaml
└── README.md
```

The custom audio plugin is intentionally kept inside the repository:

```text
plugins/just_audio_epicenter/
```

This allows the project to modify the playback layer without depending exclusively on an untouched external package.

---

# 🧰 Main technologies

| Technology | Purpose |
|---|---|
| Flutter | Application framework |
| Dart | Main programming language |
| just_audio (local plugin) | Audio playback foundation |
| just_audio_epicenter | Custom playback/audio integration |
| audio_service | Background audio and media controls |
| audio_session | Audio-session management |
| RxDart | Reactive streams |
| Provider | Application state management |
| on_audio_query | Device music-library access |
| audiotags | Audio metadata |
| SQLite / sqflite | Local persistence |
| SharedPreferences | Preferences |
| Permission Handler | Runtime permissions |
| Home Widget | Home-screen integration |
| Device Preview | UI testing |
| Marquee | Scrolling text |
| Image Picker | Image selection |

---

# 🎵 Music library

Player is designed to work with local music stored on the device.

The application can work with information such as:

- Track title
- Artist
- Album
- Genre
- Duration
- File path
- Artwork
- Available metadata

The project uses:

```text
on_audio_query
audiotags
```

to interact with the local music library and audio metadata.

---

# 🖼️ Artwork

Album artwork is part of the player experience.

The intended structure is:

```text
┌──────────────────────────┐
│                          │
│       ALBUM ART          │
│                          │
└──────────────────────────┘
          │
          ├── Artist
          ├── Album
          └── Track
```

Artwork can come from embedded audio metadata or user-selected images depending on the application flow.

---

# 🔄 Background playback

The project includes `audio_service` for background playback and system media integration.

The architecture is intended to support:

- Background playback
- Screen-off playback
- Notification controls
- System media controls
- External media controls
- Playback state synchronization

---

# 🎚️ Audio processing philosophy

The main rule for the audio engine is:

> **Do not degrade the signal unless there is a technical reason to do so.**

### Preferred

```text
SOURCE
  ↓
DECODE
  ↓
ORIGINAL / APPROPRIATE PCM
  ↓
FLOAT DSP
  ↓
OUTPUT
```

### Avoid

```text
SOURCE
  ↓
FORCE 16-bit / 44.1 kHz
  ↓
DSP
  ↓
OUTPUT
```

The second approach can unnecessarily discard information from high-resolution sources.

---

# 🚀 Roadmap

## 🔊 Audio engine

- [ ] Complete FFmpeg integration.
- [ ] WMA playback through FFmpeg.
- [ ] Additional format support.
- [ ] Sample-rate detection.
- [ ] Bit-depth detection.
- [ ] Better PCM format management.
- [ ] Float32 internal DSP path.
- [ ] Output sample-rate management.
- [ ] Avoid unnecessary resampling.
- [ ] Clipping protection.
- [ ] DSP headroom management.
- [ ] Device output capability detection.

## 🎛️ Epicenter

- [x] Epicenter integrated into the project.
- [ ] Refine bass restoration algorithm.
- [ ] Adjustable intensity.
- [ ] Better transient handling.
- [ ] Anti-clipping protection.
- [ ] Presets.
- [ ] DSP optimization.
- [ ] Real-time parameter updates.

## 🎵 Player

- [ ] Advanced playlists.
- [ ] Favorites.
- [ ] Recently played.
- [ ] Playback history.
- [ ] Queue management.
- [ ] Gapless playback.
- [ ] Crossfade.
- [ ] ReplayGain.
- [ ] Sleep timer.
- [ ] Advanced equalizer.
- [ ] More library filters.

## 🎧 Hi-Res / output

- [ ] Optimized Android AudioTrack path.
- [ ] AAudio path where appropriate.
- [ ] Output capability detection.
- [ ] Hi-Res output selection.
- [ ] USB DAC support.
- [ ] Exclusive USB output.
- [ ] Sample-rate selection.
- [ ] Buffer-size controls.
- [ ] Detailed output-device information.

---

# 🧪 Audio testing

When testing the audio engine, use files with known properties.

Recommended test set:

```text
test/
├── 16bit_44.1kHz.wav
├── 24bit_44.1kHz.wav
├── 24bit_48kHz.wav
├── 24bit_96kHz.wav
├── 24bit_192kHz.wav
├── FLAC_16_44.1.flac
├── FLAC_24_96.flac
├── MP3_320.mp3
└── WMA_test.wma
```

For each file, verify:

1. Decoder works.
2. Track metadata is correct.
3. Sample rate is detected correctly.
4. Channel count is correct.
5. Bit depth is preserved where supported.
6. DSP does not introduce clipping.
7. Epicenter behaves consistently.
8. Output sample rate is correct for the selected route.
9. No unexpected resampling occurs.
10. No clicks/pops appear during track changes.

---

# 🔬 DSP test flow

A useful validation flow is:

```text
1. DSP OFF
      │
      ▼
Verify clean playback
      │
      ▼
2. Epicenter ON
      │
      ▼
Verify bass processing
      │
      ▼
3. Increase Epicenter
      │
      ▼
Check headroom / clipping
      │
      ▼
4. Change sample rate
      │
      ▼
Verify stable output
```

Particular attention should be paid to low-frequency processing because aggressive bass restoration can create large signal peaks.

---

# 🛡️ Clipping and headroom

Bass restoration can increase peak amplitude substantially.

A future DSP implementation should therefore provide a signal path similar to:

```text
PCM
 │
 ▼
Preamp / Headroom
 │
 ▼
Epicenter
 │
 ▼
EQ
 │
 ▼
Limiter / Protection
 │
 ▼
Output
```

The purpose is to prevent digital clipping while keeping the Epicenter effect strong.

---

# 🧠 Why a custom `just_audio` plugin?

The project uses:

```yaml
just_audio:
  path: plugins/just_audio_epicenter
```

instead of simply depending on a published package.

This makes it possible to experiment with:

- Custom DSP.
- Epicenter processing.
- Playback-engine changes.
- Platform-specific audio output.
- Future decoder integration.
- Low-level audio behavior.

The plugin lives directly inside the repository so changes can be versioned together with the application.

---

# 🛠️ Development setup

## Requirements

Install:

- Flutter SDK
- Dart SDK
- Android Studio
- Android SDK
- Android build tools
- JDK compatible with the installed Flutter/Gradle setup
- Physical Android device or emulator

Check the environment:

```bash
flutter doctor
```

---

# 📥 Clone

```bash
git clone https://github.com/jgl-homer/player.git
cd player
```

Install dependencies:

```bash
flutter pub get
```

---

# ▶️ Run

Connect an Android device with USB debugging enabled and run:

```bash
flutter run
```

---

# 📦 Build APK

Debug:

```bash
flutter build apk --debug
```

Release:

```bash
flutter build apk --release
```

The generated release APK can then be installed on a compatible Android device.

---

# 🧹 Common Flutter maintenance commands

Clean build files:

```bash
flutter clean
```

Restore packages:

```bash
flutter pub get
```

Analyze:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

---

# 🐛 Reporting bugs

When opening an issue, include:

### Device

```text
Brand:
Model:
Android version:
```

### Audio

```text
Format:
Sample rate:
Bit depth:
Channels:
```

### Output

```text
Speaker / Bluetooth / USB DAC / 3.5mm / Other:
```

### Problem

Describe:

- What you expected.
- What happened.
- Whether Epicenter was enabled.
- Whether the problem happens with other files.
- Whether changing the output device changes the behavior.

A good bug report makes audio-engine problems much easier to reproduce.

---

# 🤝 Contributing

Contributions are welcome.

Before making major changes to the audio engine:

1. Explain the intended change.
2. Test with multiple formats.
3. Test with Epicenter disabled.
4. Test with Epicenter enabled.
5. Check for clipping.
6. Check sample-rate behavior.
7. Check background playback.
8. Test on physical hardware when possible.

For DSP changes, include before/after behavior and the test audio characteristics whenever possible.

---

# 📄 License

A project license has not been declared yet.

Until a license is added to the repository, treat the source code as **all rights reserved** and do not assume that it may be redistributed or reused.

---

# 👨‍💻 Author

**jgl-homer**

GitHub:

https://github.com/jgl-homer/player

---

# 🎯 Project goals

Player is being developed around four main goals:

```text
┌─────────────────────────────────────┐
│              PLAYER                 │
├─────────────────────────────────────┤
│                                     │
│  🎧 AUDIO QUALITY                   │
│     Preserve the source whenever    │
│     the platform allows it.         │
│                                     │
│  🔊 EPICENTER                       │
│     Powerful bass restoration and   │
│     low-frequency processing.       │
│                                     │
│  🧠 DSP                             │
│     Flexible real-time processing.  │
│                                     │
│  ⚡ PERFORMANCE                     │
│     Low latency and stable playback │
│     on real Android hardware.       │
│                                     │
└─────────────────────────────────────┘
```

---

# 🎶 Audio pipeline — target architecture

```text
                         PLAYER
                           │
                           ▼
                  ┌─────────────────┐
                  │   AUDIO FILE    │
                  └────────┬────────┘
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
      Native Decoder                 FFmpeg
             │                           │
             └─────────────┬─────────────┘
                           │
                           ▼
                    ┌────────────┐
                    │    PCM     │
                    └─────┬──────┘
                          │
                          ▼
                 ┌────────────────┐
                 │   FLOAT DSP    │
                 │                │
                 │ Epicenter      │
                 │ Bass Restore   │
                 │ EQ             │
                 │ Gain           │
                 │ Limiter        │
                 └───────┬────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │ OUTPUT ROUTE │
                  └──────┬───────┘
                         │
             ┌───────────┼───────────┐
             │           │           │
             ▼           ▼           ▼
          Speaker     Headset     USB DAC
             │           │           │
             └───────────┴───────────┘
                         │
                         ▼
                        🔊
```

---

# ⭐ Final objective

Player aims to become a powerful Android music player centered around:

**local music + high-quality playback + custom DSP + Epicenter.**

The goal is not simply to support more file extensions.

The goal is to build an audio pipeline where:

```text
          QUALITY
             +
           CONTROL
             +
            DSP
             +
          EPICENTER
             ↓
       COMPLETE PLAYER
```

---

### Built with Flutter ❤️

**Designed for audio.  
Built for experimentation.  
Focused on bass.**
