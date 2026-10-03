# Epicenter Target Architecture

**Fecha:** 2026-10-02  
**Propósito:** definir la arquitectura futura de Epicenter como sistema de restauración de graves.  
**Estado:** diseño; no implementado.  
**Baseline protegida:** `docs/EPICENTER_BASELINE.md` permanece sin cambios.

## 1. Objetivo

Epicenter debe analizar el audio original y generar una señal adicional relacionada con el contenido de baja frecuencia detectado, sin reemplazar ni alterar innecesariamente la señal original.

La ecuación principal es:

```text
FINAL = ORIGINAL + GENERATED
```

El resultado debe conservar el carácter, voces, medios y transitorios de `ORIGINAL`, mientras `GENERATED` restaura contenido grave que pueda inferirse de forma fiable.

## 2. Principios de diseño

1. `ORIGINAL` es una ruta inmutable desde la entrada hasta la suma final.
    1. `DETECTION` puede analizar y filtrar una copia de trabajo, pero nunca sustituye `ORIGINAL`.
    2. `GENERATED` solo se produce cuando existe evidencia suficiente de contenido grave relacionado.
    3. La generación debe ser dependiente de frecuencia, fase, nivel y envolvente del material real.
    4. `Intensity` controla principalmente la cantidad de `GENERATED`, no el volumen del original.
    5. La protección debe controlar picos sin convertir el sistema en un bass boost ni en un limitador destructivo.
    6. El dominio interno preferido es `Float32`, con headroom explícito.
    7. El sample rate original se conserva siempre que la cadena de salida lo soporte.
    8. No se fuerza Hi-Res cuando `AudioTrack`, HAL o DAC no lo soportan.
    9. El callback de audio no debe depender de allocations, locks ni I/O.

## 3. ORIGINAL path

La ruta original debe conservar una copia intercalada de cada muestra de entrada, en `Float32` normalizado y con headroom interno:

```text
input -> decode -> ORIGINAL_FLOAT
```

`ORIGINAL_FLOAT` no debe pasar por los filtros de extracción, detección o generación. Las operaciones de medición pueden leerlo, pero no modificarlo.

La suma final debe tomar exactamente esa ruta, salvo una protección global posterior:

```text
mix = original[i] + generated[i]
```

**Por qué:** conservar la señal completa evita convertir Epicenter en un ecualizador que reemplaza graves, medios o transitorios por una versión filtrada.

## 4. Detection path

La detección trabaja sobre una copia de `ORIGINAL_FLOAT`. Para estéreo se calcula:

```text
mid  = (left + right) * 0.5
side = (left - right) * 0.5
```

La ruta debe medir simultáneamente:

- energía de baja frecuencia;
    - nivel de banda fundamental;
    - estabilidad de frecuencia;
    - envolvente;
    - relación mid/side;
    - presencia vocal y energía de medios;
    - margen disponible antes de la suma.

La detección no debe escribir en `ORIGINAL_FLOAT`.

## 5. Bass analysis

El análisis debe usar un banco de bandas o filtros de baja frecuencia con frecuencias derivadas de `Sweep`, pero no una única banda fija. Debe estimar:

- fundamental dominante `f0`;
    - energía de `f0`;
    - energía existente en `2f0`, `3f0` y componentes superiores;
    - estabilidad temporal de `f0`;
    - relación entre fundamental, armónicos y ruido;
    - compatibilidad de fase L/R.

La decisión de generar debe incluir histéresis y umbrales temporales para evitar activaciones por golpes aislados, ruido o voces.

## 6. GENERATED path

`GENERATED` debe comenzar en cero por muestra y producirse únicamente desde el análisis de `ORIGINAL_FLOAT`.

```text
ORIGINAL_FLOAT
    -> detection/analysis
    -> target estimation
    -> harmonic synthesis
    -> generated mono/stereo
```

La ruta generada debe tener sus propios filtros, envelopes, ganancia y estado. No debe modificar la ruta original.

## 7. Cómo generar el contenido adicional

La generación propuesta es un restaurador dirigido por modelo, no un boost:

1. Detectar una fundamental grave confiable.
    1. Estimar su envolvente y fase en el dominio mono.
    2. Estimar qué parciales ya existen.
    3. Calcular un objetivo de reconstrucción limitado por la energía original.
    4. Generar solo los parciales faltantes o insuficientes.
    5. Filtrar la señal generada al rango útil.
    6. Aplicar envelope, compuerta, ganancia de intensidad y protección.

El objetivo de `GENERATED` debe ser proporcional a la evidencia de `f0`, no proporcional simplemente al nivel total de la señal.

## 8. Cómo evitar armónicos artificiales

No deben generarse armónicos por una lista fija de osciladores independientes. Cada parcial debe estar vinculado a:

- una `f0` detectada;
    - la fase o signo de la fundamental;
    - la envolvente temporal real;
    - el nivel observado de la fuente;
    - la estabilidad de la estimación.

Si la confianza de `f0` baja, la generación debe atenuarse progresivamente y llegar a cero. La compuerta debe rechazar ruido de banda ancha, transitorios sin tono estable y actividad vocal no compatible con una fundamental grave.

## 9. ORIGINAL + GENERATED

La suma conceptual y de implementación debe ser:

```text
mix = ORIGINAL_FLOAT + GENERATED_FLOAT
```

No debe incluir una segunda copia filtrada de `ORIGINAL` como sustituto. Las rutas de análisis y extracción solo sirven para decidir y dar forma a `GENERATED`.

La suma debe realizarse antes del limiter/headroom final, con medición de pico y margen disponible.

## 10. Headroom

El dominio interno debe reservar headroom para la suma. La entrada debe normalizarse sin amplificarla automáticamente y `GENERATED` debe tener un límite independiente.

El presupuesto de generación debe considerar:

- pico instantáneo de `ORIGINAL`;
    - pico previsto de `GENERATED`;
    - energía acumulada de la suma;
    - margen del output negociado.

**Por qué:** limitar solo después de una suma excesiva puede ocultar clipping mediante distorsión; el sistema debe evitar producir una señal generada desproporcionada.

## 11. Limiter

Debe existir una etapa posterior a `ORIGINAL + GENERATED`, separada de la síntesis:

```text
mix -> peak detection -> gain reduction -> output limiter
```

La primera opción debe ser un limiter suave con attack/look-ahead configurable y release estable. Si el presupuesto realtime no permite look-ahead, debe existir al menos un detector de pico con anticipación de bloque y ganancia suavizada.

El limiter no debe usar `Intensity` para reducir `ORIGINAL`; debe reducir la suma solo cuando sea necesario para proteger la salida.

## 12. FLOAT32 interno

La arquitectura objetivo debe recibir el formato de mayor precisión que la cadena pueda entregar y convertir una sola vez a `Float32` interno:

```text
decoder PCM/float -> FLOAT32 internal -> Epicenter -> negotiated output
```

El `Float32` interno debe conservar headroom y evitar el ciclo actual PCM16 → float → PCM16 dentro del DSP.

La conversión de salida debe ocurrir después de la mezcla y protección, en el formato realmente aceptado por el sink.

## 13. Preservación de sample rate

Epicenter debe recibir el sample rate negociado por el decoder/sink sin forzar 44.1 ni 48 kHz. Los coeficientes se derivan del sample rate real.

Política:

- 44.1 kHz permanece a 44.1 kHz si la salida lo soporta.
    - 48 kHz permanece a 48 kHz si la salida lo soporta.
    - 96 kHz permanece a 96 kHz si la salida lo soporta.
    - 192 kHz permanece a 192 kHz si la salida lo soporta.
    - Si la salida no lo soporta, el resampling debe ocurrir en el punto de negociación definido por Media3/AudioTrack, no mediante una conversión innecesaria dentro de Epicenter.

## 14. Preservación de bit depth

La profundidad del archivo, la profundidad del decoder, la profundidad del DSP y la profundidad del output son conceptos separados:

```text
archivo -> decoder -> FLOAT32 DSP -> sink/output -> hardware
```

El DSP debe trabajar en `Float32` aunque el archivo sea PCM16, pero eso no recupera información ya perdida. Para PCM24, debe evitarse reducir a PCM16 antes del DSP si el decoder y el sink ofrecen una ruta float o de mayor precisión.

La salida debe seleccionarse por capacidades reales, no por asumir que todo dispositivo soporta PCM24.

## 15. FLAC

Para FLAC 16/44.1:

```text
FLAC -> decoder -> FLOAT32 -> Epicenter -> output negociado
```

Debe conservarse 44.1 kHz y la información disponible sin una recuantización intermedia innecesaria.

Para FLAC 24/96 y 24/192, la ruta objetivo es mantener el sample rate y entregar float al DSP. La salida solo debe conservar 96/192 si la cadena AudioTrack/HAL/DAC lo confirma.

## 16. WAV

WAV PCM16, PCM24 y otros formatos soportados deben entrar en la misma política de negociación:

```text
WAV -> decoder -> mayor resolución disponible -> FLOAT32 -> Epicenter
```

No debe añadirse un WAV intermedio PCM16 salvo que el decoder o el dispositivo lo exijan.

## 17. WMA

WMA puede usar FFmpeg cuando Media3 no lo soporte directamente. La ruta objetivo es:

```text
WMA -> FFmpeg decoder -> PCM de mayor resolución disponible -> FLOAT32 -> Epicenter
```

La conversión no debe fijar `pcm_s16le` por conveniencia si existe una salida PCM/floating-point de mayor precisión compatible. Si FFmpeg solo puede producir PCM16 para un WMA concreto, esa limitación debe registrarse como propia del decoder, no ocultarse como capacidad Hi-Res.

## 18. Media3

Media3 debe actuar como negociador de decoder, renderer y sink, no como conversor fijo a PCM16. La integración futura debe:

- inspeccionar el `AudioFormat` real entregado al processor;
    - preservar sample rate cuando sea compatible;
    - seleccionar float o la mayor precisión disponible;
    - evitar offload cuando impida procesar Epicenter;
    - medir el formato negociado por cada renderer.

No debe asumirse que habilitar un renderer FFmpeg garantiza una salida de mayor resolución.

## 19. AudioTrack

`AudioTrack` debe recibir el formato máximo que pueda aceptar de forma real. La arquitectura no debe forzar PCM24, 96 kHz o 192 kHz si `AudioTrack` los rechaza o Android los mezcla a otra tasa.

La implementación futura debe registrar o exponer:

- encoding seleccionado;
    - sample rate seleccionado;
    - canales;
    - modo de transferencia;
    - si hubo fallback.

## 20. Android HAL

El HAL puede convertir, mezclar o limitar la ruta. Epicenter no debe duplicar una conversión que Android ya realizará. La política debe distinguir formato solicitado de formato efectivo.

La auditoría de runtime deberá confirmar el formato de salida en los dispositivos objetivo antes de declarar Hi-Res efectivo.

## 21. DAC

El DAC interno o USB puede tener capacidades distintas. La arquitectura debe tratar el DAC como una capacidad negociada, no como una promesa.

Si el USB DAC acepta 24/96 o 24/192, la ruta debe poder conservarlo. Si el DAC solo acepta 16/48, el sistema debe degradar de forma explícita y controlada, manteniendo el DSP interno en float hasta la última conversión posible.

## 22. Resampling

No debe haber resampling dentro de Epicenter salvo que una decisión futura lo justifique para la estabilidad del algoritmo. Preferencia:

```text
sample rate original -> DSP al mismo sample rate -> output negociado
```

Si Media3/AudioTrack requieren resampling, debe ocurrir una sola vez y documentarse:

- quién lo ejecuta;
    - sample rate origen;
    - sample rate destino;
    - motivo;
    - calidad del conversor.

## 23. Bypass

El bypass debe cumplir:

```text
OUTPUT = ORIGINAL
```

Idealmente debe ser bit-perfect cuando el formato de la cadena lo permita. No debe pasar por `GENERATED`, filtros de extracción, limiter innecesario ni recuantización adicional.

Al activar/desactivar, el cambio debe ser libre de clicks mediante un crossfade o rampa de ganancia muy corta, sin modificar permanentemente `ORIGINAL`.

## 24. Intensity

`Intensity` debe controlar principalmente:

- ganancia máxima de `GENERATED`;
    - cantidad de parciales restaurados;
    - umbral de confianza mínimo;
    - profundidad de compuerta;
    - tiempo de release de la generación.

No debe aumentar directamente el nivel de `ORIGINAL`. Con `Intensity = 0`, `GENERATED = 0` y el resultado debe ser `ORIGINAL`.

## 25. Sweep

`Sweep` debe controlar el rango de búsqueda o centro preferente de la fundamental grave, no aplicar un boost fijo.

Debe afectar:

- frecuencias candidatas de `f0`;
    - filtros de análisis;
    - límites de parciales generados;
    - tiempos o resolución de seguimiento si es necesario.

El cambio debe interpolarse o suavizarse para evitar saltos de coeficientes y transitorios.

## 26. Width

`Width` debe controlar la extensión de la región analizada/generada y la relación mid/side, no alterar arbitrariamente el volumen del original.

En estéreo:

- el análisis fundamental debe priorizar `mid`;
    - la energía `side` debe limitar la generación mono compartida;
    - la generación debe reducirse si L/R son incompatibles en fase;
    - `Width` puede permitir una distribución estéreo controlada, pero no inventar anchura en el subgrave.

## 27. Balance

`Balance` debe controlar la distribución o cantidad de `GENERATED` entre regiones de baja frecuencia y no modificar el balance físico L/R salvo que se defina explícitamente.

Decisión recomendada:

- mantener `ORIGINAL` intacto;
    - usar `Balance` como peso de generación entre fundamental y parciales/low-mid;
    - si se requiere balance L/R, crear otro control separado.

## 28. Volume

`Volume` debe escalar la salida de Epicenter o la mezcla según el contrato existente, pero no debe usarse para destruir headroom del original.

La política recomendada es:

1. `ORIGINAL` entra con ganancia unitaria;
    1. `GENERATED` se calcula con su propio presupuesto;
    2. `Volume` controla la salida global solo si el API actual lo exige;
    3. el limiter protege el resultado final.

Debe mantenerse separado del volumen general de Media3 para evitar doble escalado inesperado.

## 29. Reset/state

El estado debe incluir:

- filtros de análisis;
    - estimación de `f0`;
    - fase;
    - envelopes;
    - compuertas;
    - detector de picos;
    - ganancia del limiter;
    - crossfade de bypass;
    - buffers reutilizables.

`reset` y `flush` deben reiniciar el estado de forma segura, preferiblemente en el hilo de audio o mediante un mensaje atómico consumido por él. Las transiciones no deben dejar un bloque parcialmente reiniciado.

## 30. Realtime/thread safety

El callback de audio no debe:

- asignar arrays por bloque;
    - ejecutar I/O;
    - escribir logs;
    - esperar locks;
    - crear objetos;
    - consultar APIs de Android;
    - realizar operaciones impredecibles.

Los parámetros deben publicarse mediante un snapshot atómico o una estructura inmutable intercambiada entre hilos. El callback debe leer una configuración coherente para todo el bloque.

## 31. Performance

La ruta debe:

- preasignar `ORIGINAL`, `GENERATED`, análisis y buffers de salida;
    - reutilizar estados por canal;
    - evitar `FloatArray` por callback;
    - actualizar coeficientes solo cuando cambien parámetros;
    - suavizar parámetros sin recalcular estructuras;
    - limitar el número de `tanh` y operaciones costosas;
    - medir CPU en 44.1/48/96/192 kHz y mono/estéreo.

La prioridad es calidad de `GENERATED`, pero debe existir un presupuesto de CPU que impida glitches.

## 32. Compatibilidad

La arquitectura debe conservar:

- PCM16 como fallback;
    - mono y estéreo;
    - reproducción de formatos soportados por Media3;
    - WMA mediante fallback cuando sea necesario;
    - dispositivos sin salida Hi-Res;
    - rutas donde Android reduzca sample rate o bit depth.

El fallback debe degradar la resolución, no cambiar la semántica `ORIGINAL + GENERATED`.

## 33. Riesgos

| Riesgo | Mitigación de diseño |
| --- | --- |
| `GENERATED` colorea demasiado | Preservar `ORIGINAL`, limitar por confianza y energía |
| Armónicos artificiales | Vincular parciales a `f0`, fase y envelope real |
| Clipping | Presupuesto de headroom, detector de pico y limiter posterior |
| Clicks por cambios | Suavizado de parámetros y crossfade de bypass |
| Fase L/R inconsistente | Análisis mid/side y generación mono coherente |
| Falsos positivos por voces | Detector de confianza, energía diferencial y rechazo de banda ancha |
| GC en audio | Buffers y objetos preasignados |
| Carrera de parámetros/reset | Snapshot atómico y reset consumido por audio |
| Resampling doble | Una política explícita de negociación |
| Prometer Hi-Res no soportado | Inspección runtime de AudioTrack/HAL/DAC |
| WMA degradado | Seleccionar la salida FFmpeg de mayor precisión disponible |
| Alto coste a 192 kHz | Medición, filtros eficientes y presupuesto de CPU |

## 34. Plan de implementación por fases

### Fase 0 — Contratos y medición

- Definir formatos de entrada/salida y capacidades objetivo.
    - Instrumentar pruebas de formato negociado sin cambiar el comportamiento.
    - Crear corpus de FLAC/WAV 16/44.1, 24/96, 24/192 y WMA.
    - Definir métricas de conservación de `ORIGINAL`, nivel de `GENERATED`, pico y CPU.

### Fase 1 — Separación interna de rutas

- Introducir buffers `ORIGINAL_FLOAT` y `GENERATED_FLOAT`.
    - Mantener el algoritmo actual detrás de una ruta de compatibilidad.
    - Verificar que bypass produzca exactamente `ORIGINAL` en el dominio disponible.

### Fase 2 — Dominio FLOAT32

- Cambiar el contrato del processor para aceptar float o la mayor precisión negociada.
    - Mantener PCM16 como fallback.
    - Eliminar conversiones PCM16 intermedias cuando no sean necesarias.

### Fase 3 — Restauración `ORIGINAL + GENERATED`

- Separar detección, análisis, síntesis y mezcla.
    - Mantener `ORIGINAL` sin filtros de extracción.
    - Implementar generación dependiente de `f0`, envelope, fase y parciales existentes.

### Fase 4 — Headroom y limiter

- Añadir presupuesto de generación.
    - Implementar protección posterior a la suma.
    - Validar que `Intensity = 0` no modifique `ORIGINAL`.

### Fase 5 — Realtime y estado

- Eliminar allocations del callback.
    - Introducir snapshots atómicos de parámetros.
    - Hacer reset/flush seguro y transiciones libres de clicks.

### Fase 6 — Negociación de salida

- Medir decoder, Media3, AudioTrack, HAL y DAC.
    - Preservar sample rate/bit depth cuando sea posible.
    - Resamplear una sola vez solo cuando sea necesario.

### Fase 7 — Validación perceptual y de compatibilidad

- Comparar `ORIGINAL`, `GENERATED` y `FINAL` por separado.
    - Medir THD, picos, respuesta de frecuencia, fase y CPU.
    - Probar mono, estéreo, 44.1/48/96/192 kHz, WMA y dispositivos sin Hi-Res.

### Archivos que previsiblemente deberán modificarse durante la implementación

Estos archivos no se modifican en esta fase, pero son los puntos previstos:

- `plugins/just_audio_epicenter/android/src/main/kotlin/com/ryanheise/just_audio/EpicenterDsp.kt`
    - `plugins/just_audio_epicenter/android/src/main/kotlin/com/ryanheise/just_audio/EpicenterAudioProcessor.kt`
    - `plugins/just_audio_epicenter/android/src/main/java/com/ryanheise/just_audio/AudioPlayer.java`
    - `android/app/src/main/kotlin/com/jglhomer/player/MainActivity.kt`, solo si cambia el contrato de controles o estado
    - `android/app/build.gradle.kts`, solo si cambia la ruta decoder/formato
    - pruebas del plugin y pruebas de audio nuevas

No deben modificarse durante esta fase de diseño:

- `docs/EPICENTER_BASELINE.md`;
    - assets y logo;
    - UI no relacionada;
    - dependencias, salvo una decisión posterior respaldada por pruebas.

