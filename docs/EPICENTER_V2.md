# Epicenter V2: SMART bass restoration

Implementation and offline validation, 2026-10-07. Base: `e895d95` on main,
after the Concert Hall removal. Branch: `epicenter-v2-smart`. No merge requested.

This is an original DSP implementation, not AudioControl firmware or a claim of
measured sonic equivalence to its hardware. The older architecture/audit/phase-1
documents describe historical states; this document describes V2.

## Signal path

```text
decoder -> existing Media3 sink -> EpicenterAudioProcessor
  input ---------------------------------------------------> original
    -> mid/side -> filtered, decimated analysis -> candidates/partials
    -> confidence + tracker -> continuous-phase oscillator -> envelope
    -> evidence-limited SMART / LEGACY generated crossfade
    -> PFM -> Sweep/Width bandpass -> generated lowpass
    -> generated headroom -> original + generated -> linked protection
  -> received PCM encoding -> existing sink / AudioTrack
```

The SMART original path is not EQ'd, reconstructed, DC-filtered or saturated.
At Volume 100, below protection thresholds, output is original plus centered
generated bass. An explicitly lowered Volume still scales the mixed output.
No decoder, WMA conversion, AudioPlayer, sink negotiation, library, metadata,
navigation, artwork or playlist changes are included.

## Analysis and harmonic inference

`BassAnalyzer` analyzes MID = (L+R)/2; SIDE = (L-R)/2 contributes a coherence
penalty. A 25 Hz high-pass and eighth-order 200 Hz Butterworth anti-alias
low-pass precede integer decimation to approximately 2.4 kHz. The audible
signal is never decimated. Keeping the lower analysis skirt permits tracking
an existing 36-40 Hz fundamental instead of incorrectly halving it.

The preallocated ring holds 96 ms. Every approximately 10 ms, bounded
normalized autocorrelation scans lags corresponding to 27-180 Hz. Extending
below the main 50-180 Hz bass region allows missing-fundamental candidates.
Local peaks have parabolic interpolation; at most eight candidates survive.
Hann-windowed Goertzel projections measure f, 2f, 3f and 4f up to 195 Hz.
Scores combine periodicity, harmonic coverage, a small Sweep preference,
continuity and a shortest-supported-period tie break. This is not a fixed
Sweep-frequency oscillator and not a giant full-band FFT.

The critical 72+108+144 Hz signal, with no 36 Hz component, selects about
36 Hz. A pure 72 Hz tone is tracked as 72 Hz and can generate 36 Hz at reduced
strength (0.55 restoration factor). Pure tones are intrinsically ambiguous:
this is conservative octave-down inference, not proof that the recording
originally contained a missing fundamental. An existing strong 40 Hz sine
does not generate 20 Hz. Synthesis targets are confined to 27-63 Hz.

## Confidence and tracking

Confidence combines normalized periodicity, harmonic fit, bass/full-band
energy ratio and MID/SIDE coherence. The energy measurements use 96 ms
envelopes, not an unstable 10 ms energy ratio. Weak/aperiodic input is rejected.
The tracker requires three consistent hops, retains previous/candidate/stable
frequencies, and delays octave changes for twelve qualifying updates.

SMART enters above 0.72 and leaves below 0.50. Confidence smoothing has
30 ms attack and 35 ms release; the synthesis evidence factor becomes zero
below 0.40. A 45 ms pitch glide preserves phase across note and buffer changes.
The bass amplitude envelope uses 12 ms attack / 160 ms release. There is no
phase restart on individual buffers. Silence has zero generated output.

This is a dominant-pitch, heuristic musical detector, not voice separation.
A bass-like sustained male vowel can be indistinguishable from an instrument.
Polyphonic bass, kick/bass interference, formants and pathological noise still
need a real music/voice corpus and listening tests. Passing a vocal proxy is
not a guarantee of zero vocal false positives on all recordings.

## SMART and LEGACY

`EpicenterDsp` defaults to `EpicenterEngine.SMART`. `LegacyEpicenterDsp` retains
the original detector bands, flipState, gate, hold, envelope and synthesis
equations, with fixed internal Balance 82. Its generation loop and computeGate
were compared directly with the base commit and are unchanged for finite input.
Buffers/derived coefficients are reused and reset clears existing filter state.
Invalid samples are sanitized rather than poisoning future output.

Automatic fallback uses only LEGACY's generated branch. It never blends the
old filtered/saturated original path into SMART's dry path. SMART/LEGACY use
sin/cos crossfade weights, 30 ms smoothing and a 0.25 ceiling on fallback.
Both share evidence and restoration gates: low confidence means limited
fallback, and no evidence means no fallback. They cannot both run at maximum.

For full old-engine A/B, instantiate `EpicenterDsp(rate, EpicenterEngine.LEGACY)`
or test `LegacyEpicenterDsp` directly. Full LEGACY deliberately retains its
historical whole-signal shaping; only SMART promises original + generated.
No extra engine-selection control was added to the normal UI.

## Controls and filters

- Sweep: 27-63 Hz, a candidate preference and center of the generated bandpass.
- Width: actual bandpass Q, 2.8 at 0% to 0.7 at 100%; it does not set confidence.
- Intensity: smoothed normalized value squared, primarily scaling GENERATED.
  Zero reaches dry bypass; there is no jump to a large gain at 1%.
- Volume: 30 ms smoothing; explicit global output trim, default 100.
- PFM: generated-only fourth-order Butterworth high-pass at 24 Hz, using two
  second-order sections with Q 0.5411961 / 1.306563. No synthesis targets below
  27 Hz; this is attenuation, not an impossible brick-wall rejection at 20 Hz.
- Lowpass: generated-only, derived from Sweep and Q, constrained to 55-100 Hz.
- Filter control smoothing: 30 ms, coefficient updates at up to 200 Hz.

New/default settings are Sweep 40 Hz, Width 60%, Intensity 65%, Volume 100,
Peak Protection ON. Tuning version 7 migrates known previous defaults once.
Version-6 custom values and stored Volume/Protection are preserved. Historical
rough-test heuristics only apply to versions older than 6. Legacy Balance
preferences remain ignored. Existing controls/API are retained.

## Headroom and final protection

Original peak envelope: immediate attack, 80 ms release. Before mixing,
available headroom is max(0, 0.96 - originalPeak). A generated peak envelope
and gain cap reduce GENERATED first, with immediate reduction / 120 ms recovery.
There is no permanent attenuation of the original merely for enabling SMART.

The final sample-peak limiter uses max(abs(channel)) and one shared gain for
all channels: threshold 0.96 (about -0.355 dBFS), immediate/sample attack,
80 ms release. It is exactly unity after recovery when not needed. It is not
a look-ahead or true-peak limiter and does not guarantee intersample peaks.
The existing switch controls this final protection; generated headroom remains
active even with it off. Integer PCM conversion still clamps to its legal range.

Soft defense is identity below 0.985 and uses a short cubic knee only above
that value. Normal limited samples at or below 0.96 never reach the knee.
SMART does not contain an always-on tanh; historical tanh remains confined
to the LEGACY generator/full A/B engine.

## Bypass, lifecycle and realtime

- Enable/disable crossfade: 25 ms. After OFF settles, AudioProcessor copies
  input bytes directly, including the low bits of PCM32, with no DSP/limiter.
- Steady Intensity 0 also takes the direct copy path.
- Control setters publish immutable snapshots; they never reset DSP on the UI
  thread. Disable resets after the audio-thread fade, without new filter objects.
- Flush/seek/stop reset ring, pitch history, confidence, phase, envelopes,
  filters, legacy state, headroom, limiter and diagnostics.
- `onConfigure` validates but does not mutate the currently draining stream.
  Format changes are applied in `onFlush`, using the committed Media3 format.
- Reusable input/output arrays hold 4096 samples; larger callbacks are chunked.
  Legacy and generated buffers are preallocated to 4096 frames. Larger direct
  offline DSP calls may grow those buffers once, then reuse them; the production
  processor's chunk bound does not require growth.
- The ring, analysis window, Hann weights, candidates and correlation arrays
  are preallocated. There is no recurring FloatArray, ByteBuffer slice, parameter
  object, string, file, DB, network, log or lock in normal callback processing.
- Media3's output ByteBuffer may grow at a new size high-water mark; control
  snapshots allocate on the platform thread and format setup allocates state.
- Debug state is opt-in, audio-thread-owned, updated at 10 Hz without allocation
  or production logging. It is not an unsynchronized UI telemetry API.

## PCM

PCM16, packed signed PCM24, PCM32 and FLOAT remain accepted and are written in
the received encoding and sample rate. PCM24 sign extension is tested at
negative full-scale and -1 LSB. DSP remains Float32; active PCM32 processing
cannot retain all 32 integer bits, but unchanged samples retain their original
bytes and steady OFF never requantizes. Non-finite active FLOAT input is sanitized.
No claims are made about the actual DAC resolution: the unchanged Media3 sink
still decides its intermediate/output format and has float output disabled.

## Reproducible validation

From this checkout:

```powershell
cd android
.\gradlew.bat :just_audio:testDebugUnitTest --console=plain --max-workers=2
cd ..
flutter test --no-pub test/services/epicenter_persistence_test.dart test/widgets/marquee_text_test.dart
flutter analyze --no-pub lib/services/state_persistence.dart test/services/epicenter_persistence_test.dart
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

18 JVM tests pass: missing fundamental across four rates, pure 72, existing
40, silence/noise/vocal proxy/L=-R, note changes/octave lock, monotonic intensity,
dry path, real bandwidth, generated-first headroom, linked limiting, parameter
and enable transitions, partition independence/reset, NaN/Inf, PCM endpoints,
processor lifecycle and bit-identical bypass. Flutter's four new preference
tests plus seven existing marquee tests pass. Changed Dart files analyze cleanly.
Android plugin compilation and the debug APK build succeed.

Representative missing-fundamental results (Float32 stereo, 2 seconds):

| Rate | Detected f0 | Smoothed target | Confidence | Generated peak | Output peak | Limiter gain |
| --- | --- | --- | --- | --- | --- | --- |
| 44100 | 35.9989 | 36.0009 | 0.9782 | 0.2513 | 0.5531 | 1.0 |
| 48000 | 35.9995 | 36.0001 | 0.9836 | 0.2519 | 0.5730 | 1.0 |
| 96000 | 35.9995 | 36.0012 | 0.9837 | 0.2519 | 0.5744 | 1.0 |
| 192000 | 35.9995 | 36.0013 | 0.9838 | 0.2518 | 0.5739 | 1.0 |

Noise (seeded, 4 s), silence and L=-R have confidence/generated output zero
in the reported final window; whole-test delta RMS is also asserted. The 1 kHz
dry-path test matches original within 1e-7. Headroom stress has input peak
0.93933, output peak 0.95603 and limiter gain 1.0. The parameter/toggle test's
largest adjacent generated-sample change is approximately 0.001275.

Desktop JVM performance, 512 stereo frames at 48 kHz: a warmed run measured
p50 0.230 ms / p95 0.349 ms / p99 0.497 ms against a 10.667 ms callback budget.
Thread-allocation readings across three 1000-callback passes were [0, 800, 0]
bytes, with zero in the final warmed pass. Small nonrecurring thread/instrument
allocations are reported, not silently attributed to the DSP or to arrays.
Static buffer-bound inspection and the warmed test show no recurring FloatArray
allocation. These are host JVM observations, NOT Android CPU/GC guarantees.

### Inherited Flutter failures, left unchanged

- Full `flutter analyze`: 27 pre-existing findings in unchanged files, including
  missing `package:mockito/mockito.dart` and the resulting non-class mixin error
  in `plugins/just_audio_epicenter/test/just_audio_test.dart`, plus old lint warnings.
- Full `flutter test`: empty tracked `test/widget_test.dart` has no `main` and
  fails to load. The valid tests run separately pass. No exclusions, dependency
  changes or unrelated fixes were used to conceal these baseline failures.

## Remaining validation and limits

No phone install, Bluetooth listening, car-audio A/B, electrical DAC capture,
real voice/music corpus, Android GC/underrun profiling or true-peak measurement
was performed for V2. Do not equate the debug build with perceptual acceptance.
Analysis adds roughly a 96 ms observation window plus stability/attack time
to GENERATED; dry audio has no added look-ahead delay. Very short bass notes
may get less restoration. Multichannel output keeps original channels but
analysis uses the first two; this is not a surround-channel-layout processor.

Public behavior reference only:
[AudioControl manual](https://www.audiocontrol.com/downloads/car/current/epicenter/epicenter-user-manual.pdf).
Standard pitch-method background:
[McLeod and Wyvill, A Smarter Way to Find Pitch](https://citeseerx.ist.psu.edu/document?doi=60dd4c01f687858a5fbf6c021920c56247bcf2db&repid=rep1&type=pdf).
The implementation here uses bounded normalized correlation plus its own
harmonic scoring; it does not reproduce either a hardware firmware or an exact
implementation of that paper.
