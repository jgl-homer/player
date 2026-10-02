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

### Identidad visual

- Se confirmó como logo de referencia actual `assets/icon/14819eb3-6002-4610-a75e-b6de2bb1f148.png`.
- Se documentó que futuras adaptaciones para iconos de Android o iOS deben conservar exactamente la identidad visual y limitarse a composición, escala, padding o formato.
- No se rediseñó, reemplazó ni generó una variante del logo.
