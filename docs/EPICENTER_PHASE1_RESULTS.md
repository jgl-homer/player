# Epicenter Phase 1 — Resultados de medición

**Fecha:** 2026-10-02  
**Estado:** referencia cuantitativa parcial; no se inició Phase 1 funcional.

## Alcance

No se modificaron `EpicenterDsp.kt`, `EpicenterAudioProcessor.kt`,
`AudioPlayer.java`, Media3, AudioTrack, WMA, UI, dependencias ni la ruta de
audio. No existe en el proyecto un harness que capture simultáneamente el PCM
de entrada y salida del processor sin instrumentar los archivos protegidos.

## Resultados

| Medición | Estado | Resultado |
|---|---|---|
| PCM16 de entrada vs salida en bypass | NO MEDIDO | Requiere capturar ambos buffers dentro del processor. |
| ORIGINAL vs FINAL con Epicenter activo | NO MEDIDO | No hay captura PCM de la salida del processor. |
| GENERATED, f0 y 2f/3f/4f | NO MEDIDO | No hay señal `GENERATED` expuesta ni captura espectral del output. |
| 44.1/48/96 kHz | PARCIALMENTE MEDIDO | La configuración recibida por Epicenter fue observada previamente en runtime; no se capturaron pares ORIGINAL/FINAL. |
| Clipping `-32768`/`32767` | NO MEDIDO | Requiere inspección de buffers de salida. |
| CPU y allocations | NO MEDIDO | No existe medición no invasiva ya conectada al callback. |

## Límite analítico del bypass

La ruta actual convierte cada muestra PCM16 a `Float32` mediante
`sample / 32768f` y vuelve a entero mediante `* 32767f` y truncamiento.
Sobre los 65.536 valores PCM16 posibles, la simulación exacta de esa fórmula
da: 32.751 valores modificados (49,9741 %), error absoluto máximo de 1 unidad
y RMS de error 0,706923 unidades. Esto es un límite analítico de la fórmula,
no una captura del material reproducido ni una afirmación bit-perfect.

## Cierre

La referencia cuantitativa de `ORIGINAL`, `GENERATED` y `FINAL` queda
pendiente hasta disponer de un punto de captura observacional permitido.
No se realizaron cambios funcionales ni se alteraron parámetros del DSP.
