# LEGACY / SMART characterization

Analysis only: no production DSP equations, thresholds, preferences or phone
installation changed. Existing selector changes remain untouched and uncommitted.

## Method

`EpicenterComparisonTest` processes 48 kHz stereo PCM in 480-frame blocks for
three seconds and measures the final two seconds. It compares complete LEGACY
and SMART output using identical inputs and parameters. Six synthetic cases are
run with defaults (40 Hz / Width 60 / Intensity 65) and with an exploratory
32 Hz / Width 67 / Intensity 67 setting. The latter is NOT a readback of the
user's settings: which control their 67% referred to remains unconfirmed.

The reference signal contains 72, 108 and 144 Hz at amplitudes .16, .14 and .12;
there is no input component at 36 Hz. `sub36` is the peak sinusoidal amplitude of
the output-minus-input projection at 36 Hz, not an RMS, loudness score or total
generated-bass measurement. LEGACY's nonlinear processing can also contribute
to that projection. `deltaRms` includes all original-path processing in LEGACY
and must not be labeled restoration strength.

## Measured results at defaults

| Input | LEGACY sub36 | SMART sub36 | SMART mean confidence | SMART mean generated gain |
| --- | ---: | ---: | ---: | ---: |
| Reference harmonics | .09840 | .24902 | .98964 | 1.00000 |
| Reference x .35 + centered 1 kHz at .40 | .00334 | 0 | 0 | 1.00000 |
| Reference x .65 + 83 Hz at .16 + 117 Hz at .12 | .0000073 | 0 | 0 | 1.00000 |
| Reference x .35 + opposite-polarity 1 kHz at .40 | .10913 | .08216 | .95593 | 1.00000 |
| Reference x 2.45 | .17772 | .02976 | .98964 | .04712 |

Both centered-mid and additional-bass cases gave exactly zero steady-state
output-minus-input RMS in SMART. For a preexisting pure 40 Hz tone, SMART also
gave zero difference, intentionally avoiding reconstruction of existing bass;
LEGACY changed it (delta RMS .08367). The 32/67/67 parameter set showed the same
qualitative outcomes. For reference harmonics SMART produced .25348 at 36 Hz,
so 32 Hz does not inherently prevent restoration.

The opposite-polarity-mid test isolates the analysis dependency on stereo
placement. It is a synthetic contrast, not representative evidence of any song.
The mixed-bass case also disrupted LEGACY's 36 Hz output: its audible changes
cannot automatically be interpreted as correct missing-fundamental recovery.

## LEGACY behavior

- Positive detector zero crossings toggle `flipState`, producing an octave-down
  waveform subsequently shaped by envelopes, filters and saturation.
- It does not require SMART's pitch confidence or three stable analysis frames.
- Detector release is 95 ms, synth-level release 180 ms and gate release 240 ms.
  Gate hold is 25-70 ms depending on intensity (55.15 ms at Intensity 67).
  These are envelope time constants/hold, not measured total audible tail time.
- Its original path is not dry: a highpass, bass lowpass, body band and dip band
  are recombined, followed by continuous `tanh` and an 18 Hz DC highpass.
  This continuous saturation is separate from the optional final .96 peak
  protector. It was left intact as part of the preserved engine.
- Internal balance remains fixed at 82; intensity normalization includes .75.
- Sweep is a historical multi-filter mapping, not a literal lowpass cutoff or
  a direct 32 Hz center as in SMART's output shaping. At Sweep 32 / Width 67:
  detector bands are about 56.39 / 76.39 / 102.08 Hz, synthesis highpass 22.83 Hz,
  synthesis lowpass 61.70 Hz, sub output lowpass 64.70 Hz and crossover 125.10 Hz.
  These are nominal individual filter frequencies, not the combined response.

Long envelope releases and original-path coloration are plausible contributors
to a sustained/dragging impression, not proof of the cause heard by this user.

## Why SMART can be effectively silent

1. Confidence multiplies periodicity, harmonic fit, mid/side coherence and a
   bass-to-full-mid-energy guard. Strong centered midrange can reduce confidence
   to zero even when the missing-bass harmonics remain present.
2. The oscillator requires confidence above .72 plus three stable frames.
   Below .50 it deactivates; below .40 the final evidence multiplier is zero.
3. The LEGACY fallback is generated-only, weighted at most .25, and subjected
   to the SAME evidence and restoration multipliers. It cannot rescue a
   detection rejection. The full LEGACY original-path processing is absent.
4. Intensity is squared in SMART (.67 becomes .4489); the fallback's own
   generation already scales with intensity. Equal UI values do not imply
   equal gain between the engines.
5. Generated-first headroom compares a decaying original peak against .96.
   In the hot-reference test its mean generated gain fell to .04712 while
   confidence remained .98964. This is separate from the confidence problem.
   This headroom stage runs even with the final peak-protection toggle off.

## Validation and limits

- `:just_audio:testDebugUnitTest --offline --console=plain --max-workers=2`:
  PASS, 20 tests, zero failures/errors (13 DSP, 6 processor, 1 comparison).
- No changes in `LegacyEpicenterDsp.kt`, `EpicenterDsp.kt` or `BassAnalyzer.kt`.
- Tests and this report are the only additions in this analysis follow-up.
- No APK rebuild or install: production code was not changed in this follow-up.
- No listening test, song-specific measurement, or headphone response
  measurement was performed. A named song/time segment is still needed to
  connect these confirmed mechanisms to the user's particular observation.

Before tuning, preserve LEGACY and use the actual failing fragment to evaluate
SMART's confidence/fallback interaction separately from generated-first
headroom. Raising global intensity or removing rejection safeguards blindly
could amplify noise or unwanted material without solving the detection issue.
