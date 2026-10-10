# Epicenter V2 / V2.1 bass restoration

V2 implementation: 2026-10-07. V2.1 Hybrid Legacy Core: 2026-10-09.
V2.1 branch: `epicenter-v2-hybrid-legacy-core`, based on approved V2 commit
`1fa297e29522bf9e3c9ff6bd17331f9dc9cd2917`. Its PR targets
`epicenter-v2-smart`, not `main`; no merge is part of this work.

This is an original DSP implementation, not AudioControl firmware or a claim of
measured sonic equivalence to its hardware. The older architecture/audit/phase-1
documents describe historical states; this document describes V2.

## V2.1 Hybrid Legacy Core

### Why it changed

V2 SMART was stable and accurate on sustained missing-fundamental fixtures, but
listening exposed the wrong transient behavior for norteña, cumbia, kick and
short electric/bajo sexto notes. Its 96 ms analysis window plus stable-frame
requirement could make a 100-150 ms note finish before useful restoration began.
The phase-continuous sine was also too clean and detached from the program. The
confirmed test result is representative: on a 120 ms 72+108+144 Hz note SMART
reported no measurable in-note restoration, despite working on the sustained
two-second version.

HYBRID is now the default and keeps SMART and full LEGACY as explicit A/B
references. A one-time preference migration selects HYBRID; later user choices
persist. The compact selector exposes HYBRID / SMART / LEGACY without changing
Sweep, Width, Intensity, Volume or Protection.

### Generated-only hybrid path

The dry path remains byte-transparent after OFF settles and remains sample-
transparent at Volume 100 whenever generated/protection paths do not act. The
hybrid never sends ORIGINAL through LEGACY's voice highpass, bass/body/dip
reconstruction, global `tanh`, or DC filter. Only GENERATED contains:

```text
MID bass onset -> limited punch band (70-112 Hz)
LEGACY detector texture -> supervised flipState -> leveling -> controlled tanh
V2 analyzer/tracker -> authorization + expected toggle period + sine anchor
generated PFM/shaping -> musical generated headroom -> ORIGINAL + GENERATED
-> stereo-linked final limiter -> last-defense soft clip
```

The Legacy Core uses the historical detector-band weighting, divide-down sign
texture, envelope leveling and `tanh` density. Saturation is generated-only and
Intensity-dependent. Once pitch is valid, expected half-period timing rejects
early double toggles and forces a late missing toggle, preventing detector noise
from freely steering `flipState`. Before confirmation, two detector crossings
must imply a 54-180 Hz source; this gives useful divide-down attack without
letting a real 40 Hz note immediately create 20 Hz.

### Transient fast path and handoff

The fast path measures rising low-band MID energy, absolute level, MID/SIDE
coherence and bass/program ratio without waiting for the 96 ms pitch window.
Attack is 4 ms nominal. Authorization lasts 60-90 ms according to onset strength
and releases over 72 ms, but live note support can close it earlier as the real
bass decays. Unconfirmed generation therefore cannot remain indefinitely.

An independently band-limited punch layer follows the real 70-112 Hz note and
does not pass through the 27-63 Hz sub shaping. This supplies the initial `PUM`.
The Legacy divide-down texture supplies most confirmed sub character. The sine
remains phase-continuous but is capped at 16% as a pitch anchor. Confirmation
uses V2 harmonic/pitch evidence and two stable hops in HYBRID. A separate hybrid
confidence path can use absolute bass presence for a true <=63 Hz multi-harmonic
candidate under loud centered program, while ambiguous octave-down candidates
above 63 Hz retain a bass/program-ratio voice guard. SMART's original confidence
equation and thresholds remain available unchanged for A/B.

Generated amplitude attack/release is 5/92 ms. The Legacy detector envelope is
4/92 ms and leveling is 6/90 ms. A faster live-note follower prevents confirmed
analysis history from creating the old `pum...WOOOOM` tail after input stops.

### Headroom and protection

HYBRID replaces V2's hard `0.96 - originalPeak` generated allowance with a soft
knee beginning at a combined demand of 0.90 and ending at 1.04. It combines a
decaying peak estimate with a 55 ms RMS estimate, has 5 ms gain-reduction attack,
120 ms recovery, and retains at least 0.32 peak-driven / 0.45 RMS-driven
generated gain. This intentionally lets the final stereo-linked limiter catch
short remaining peaks instead of muting GENERATED throughout modern masters.
SMART retains its original V2 headroom behavior for honest comparison.

The final limiter remains one shared L/R gain, threshold 0.96, immediate sample
attack and 80 ms release. The cubic soft defense is still identity below 0.985
and only exists as the final full-scale guard. Disabling Peak Protection bypasses
that final limiter/defense, not generated-first headroom.

### Short-note and A/B measurements

All values below come from deterministic 48 kHz Float32 stereo JVM fixtures,
not from headphone measurements or a claim of perceived loudness equivalence.
Onset is the first 2 ms generated-RMS window reaching -20 dB relative to the
35-105 ms in-note generated RMS. Tail is generated RMS 150-250 ms after note end.

| Engine | Generated RMS during 120 ms note | Peak | Onset | Late tail | Detected f0 | Max confidence |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| HYBRID | 0.06611 | 0.15412 | 4.13 ms | 0.0000127 | 35.94 Hz | 0.7682 |
| SMART V2 | 0 | 0.02293 whole-run transient | not reached | 0.0000085 | 35.94 Hz | 0.5608 |
| LEGACY | 0.10450 | 0.24983 | 0 ms | 0.01933 | n/a | n/a |

The repeated fixture uses five 120 ms notes at 36/42/39/46/34 Hz with 80 ms
gaps. In-note generated RMS measured 0.0564-0.0878. The final 20 ms of each gap
measured 0.00735-0.02966, below 42% of its preceding note. The independent late
tail test measured 0.0000127. This is an objective improvement over V2 timing,
not a declaration that HYBRID wins the listening test.

The mastered fixture retained generated RMS 0.12263, minimum headroom gain
0.99746, output peak 0.96 and maximum limiter reduction 0.02719. Existing 40 Hz,
synthetic male voice, seeded noise and L=-R rejection tests pass. The V2 missing
fundamental test still resolves approximately 36 Hz at 44.1/48/96/192 kHz.

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

`EpicenterDsp` defaults to `EpicenterEngine.HYBRID`. `LegacyEpicenterDsp` retains
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
The settings page and quick Epicenter panel expose HYBRID / SMART / LEGACY selection.
The quick panel also shows the actual Epicenter enabled switch, so editing an
Intensity slider while the effect is OFF is no longer ambiguous. Selection is
stored independently as `epicenter_engine`, reapplied on audio-session changes,
and does not change Intensity, Sweep, Width, Volume or Protection.

Both engines are prepared on format setup. Switching fades the active engine
to dry for 25 ms, selects/resets the other on the audio thread, then fades in
for 25 ms (plus up to a processing chunk boundary). No processor is allocated
on selection. Full LEGACY is selected explicitly; SMART's automatic generated
fallback is unchanged. A processor test checks actual output differences,
transition continuity, selection across flush and byte-transparent OFF.
The selector handles native-call failures and prevents overlapping UI requests.
The selector switches among three preallocated processors only after the active
one reaches dry bypass. SMART and full LEGACY equations remain available as
separate processors; HYBRID does not mutate either reference engine.

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

New/default settings are HYBRID, Sweep 40 Hz, Width 60%, Intensity 65%, Volume 100,
Peak Protection ON. Tuning version 7 migrates known previous defaults once.
Version-6 custom values and stored Volume/Protection are preserved. Historical
rough-test heuristics only apply to versions older than 6. Legacy Balance
preferences remain ignored. Existing controls/API are retained.

## Headroom and final protection

In SMART, the original peak envelope has immediate attack and 80 ms release. Before mixing,
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
flutter test --no-pub test/widgets/epicenter_engine_selector_test.dart test/services/epicenter_persistence_test.dart test/widgets/marquee_text_test.dart
flutter analyze --no-pub lib/providers/audio_provider.dart lib/services/state_persistence.dart lib/screens/tabs/settings_tab.dart lib/widgets/options_menu.dart lib/widgets/epicenter_engine_selector.dart test/widgets/epicenter_engine_selector_test.dart test/services/epicenter_persistence_test.dart
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

25 JVM tests pass: missing fundamental across four rates, pure 72, existing
40, silence/noise/vocal proxy/L=-R, note changes/octave lock, monotonic intensity,
dry path, real bandwidth, generated-first headroom, linked limiting, parameter
and enable transitions, partition independence/reset, NaN/Inf, PCM endpoints,
processor lifecycle and bit-identical bypass. Fifteen selected Flutter tests
(persistence, selector and existing marquee coverage) pass. Changed Dart files analyze cleanly.
Android plugin compilation and the debug APK build succeed.

Representative missing-fundamental results (Float32 stereo, 2 seconds):

| Rate | Detected f0 | Smoothed target | Confidence | Generated peak | Output peak | Limiter gain |
| --- | --- | --- | --- | --- | --- | --- |
| 44100 | 35.9989 | 36.0009 | 0.99996 | 0.2367 | 0.5619 | 1.0 |
| 48000 | 35.9995 | 36.0004 | 0.99996 | 0.2388 | 0.5635 | 1.0 |
| 96000 | 35.9995 | 36.0045 | 0.99991 | 0.2402 | 0.5644 | 1.0 |
| 192000 | 35.9995 | 36.0124 | 0.99983 | 0.2431 | 0.5662 | 1.0 |

Noise (seeded, 4 s), silence and L=-R have confidence/generated output zero
in the reported final window; whole-test delta RMS is also asserted. The 1 kHz
dry-path test matches original within 1e-7. The hot-input stress reaches exactly
the 0.96 limiter threshold without clipping. The parameter/toggle test's largest
adjacent generated-sample change is approximately 0.001565.

Desktop JVM performance, 512 stereo frames at 48 kHz: a warmed run measured
p50 0.355 ms / p95 0.475 ms / p99 0.527 ms against a 10.667 ms callback budget.
Thread-allocation readings across three 1000-callback passes were [0, 0, 0]
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

No Bluetooth listening, car-audio A/B, electrical DAC capture, real voice/music
corpus, Android GC/underrun profiling or true-peak measurement was performed by
the automated V2.1 work. Do not equate tests/build/install with perceptual
acceptance. SMART analysis adds roughly a 96 ms observation window plus
stability/attack time; HYBRID's transient path has no analysis-window lookahead.
Dry audio has no added look-ahead delay. Multichannel output keeps original channels but
analysis uses the first two; this is not a surround-channel-layout processor.

Public behavior reference only:
[AudioControl manual](https://www.audiocontrol.com/downloads/car/current/epicenter/epicenter-user-manual.pdf).
Standard pitch-method background:
[McLeod and Wyvill, A Smarter Way to Find Pitch](https://citeseerx.ist.psu.edu/document?doi=60dd4c01f687858a5fbf6c021920c56247bcf2db&repid=rep1&type=pdf).
The implementation here uses bounded normalized correlation plus its own
harmonic scoring; it does not reproduce either a hardware firmware or an exact
implementation of that paper.
