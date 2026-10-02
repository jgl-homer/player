# Changelog de Epicenter

## 2026-10-02

### Baseline documental

- Se creó `docs/EPICENTER_BASELINE.md` como referencia del estado actual del pipeline Epicenter.
- Se registró el pipeline exacto: `PCM -> Headroom/protección -> Subsonic -> Low-frequency detection -> Envelope follower -> Bass extraction -> Harmonic generation -> Harmonic filtering -> Dynamic gain -> Dry/Wet mix -> Limiter/protection -> Output`.
- Se documentaron controles, límites, estado entre bloques, reinicios, invariantes y formato PCM.
- No se modificaron archivos de código, DSP, audio, UI ni comportamiento.
- No se realizó refactorización ni se alteró la configuración funcional del procesador.

### Alcance de este registro

Este changelog registra exclusivamente la documentación de la baseline. Cualquier cambio posterior al procesamiento Epicenter deberá describirse en una entrada nueva y compararse con `EPICENTER_BASELINE.md`.

