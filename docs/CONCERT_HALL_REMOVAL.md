# Concert Hall removal

Base: `origin/main` at `aa58a48ba1571fa51b183f9e771f82d0354ab17e`.
Branch: `remove-concert-hall`. This prepares the baseline for a later
Epicenter V2; it does not implement V2 or retune the current engine.

## Changes

- `MainActivity.kt`: removed the Concert Hall EnvironmentalReverb,
  Virtualizer, Equalizer and LoudnessEnhancer instances, their session state,
  seven channel handlers and effect creation/configuration/release helpers.
- `audio_provider.dart`: removed AudioPreset, EQ/reverb state and getters,
  presets, wet/dry parameters and Concert Hall methods. Removed only the
  `setBypass` call from the audio-session listener; Epicenter synchronization
  and all five parameter keys remain unchanged.
- Deleted `lib/widgets/concert_hall_modal.dart`, including its private UI
  helpers. No remaining screen/menu imported or opened this modal.
- No Concert Hall preferences or dedicated package dependencies were found.
  Epicenter preferences and dependency versions are unchanged.

## Result

`Source -> Media3/FFmpeg -> PCM -> EpicenterAudioProcessor -> DefaultAudioSink
-> AudioTrack -> Android output`

The app no longer attaches Concert Hall effects to the Android audio session.
The entire `plugins/just_audio_epicenter` tree is unchanged, including PCM
formats, controller, limiter and generic just_audio AudioEffect support.

## Validation

- Global tracked-source search: no Concert Hall runtime references remain.
  Generic just_audio effects/tests/changelog are retained. The queue's
  `Icons.equalizer` is a playback indicator, not an audio effect.
- `git diff --check`: passed. Epicenter plugin, persistence and audio handler
  match the base revision exactly.
- `dart format --output=none lib/providers/audio_provider.dart`: completed;
  retained existing formatting to avoid unrelated whole-file changes.
- `flutter analyze --no-pub lib/providers/audio_provider.dart`: passed.
- `flutter analyze --no-pub`: 27 inherited findings in unchanged files,
  including missing mockito resolution in the plugin's tests.
- `flutter test --no-pub`: blocked by the existing empty `test/widget_test.dart`
  (missing main). `flutter test --no-pub test/widgets/marquee_text_test.dart`:
  all 7 tests passed. No unrelated analyzer/test fixes are included.
- `flutter build apk --release --no-pub`: passed (61.8 MB APK), including
  Android app and local plugin compilation. Compiled MainActivity inspected
  with javap: Concert Hall fields/helpers absent, Epicenter handler retained.
- Device playback checks A-E (OFF/ON, parameter changes, anti-clip and session
  changes) remain unverified: the USB device disconnected during validation.
  Source inspection verifies unchanged Epicenter calls and parameter payloads;
  it is not a listening test. Checks F-G pass by removal of the channel calls,
  handlers and Concert Hall effect constructors.
