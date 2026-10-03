# Audio Engine Audit — Epicenter Focus

**Fecha de auditoría:** 2026-10-02  
**Baseline de referencia:** `6f0c55f8321eeaace3ee2b5bda52c0f9801e3f91`  
**Alcance:** inspección estática del repositorio. No se modificó código, DSP, audio, Media3, UI, dependencias ni configuración.

## 1. Objetivo

El objetivo prioritario del motor no es reproducir Hi-Res de forma aislada. Es proporcionar a Epicenter el camino de mayor calidad disponible para restaurar graves:

```text
ORIGINAL -> análisis Epicenter -> ORIGINAL + GENERATED -> mezcla/protección -> salida
```

La auditoría distingue:

- resolución del archivo;
- formato que entrega el decoder;
- formato que recibe Epicenter;
- formato solicitado al sink/output;
- formato que finalmente puede soportar el dispositivo.

El repositorio permite comprobar con precisión la entrada del `AudioProcessor` y la conversión WMA explícita. No permite determinar estáticamente el formato final real del `AudioTrack`, HAL o DAC para un dispositivo concreto.

## 2. Ruta actual completa

### Archivos y clases relevantes

- `plugins/just_audio_epicenter/android/src/main/java/com/ryanheise/just_audio/AudioPlayer.java`
  - `decodeAudioSource()`
  - `prepareWmaUri()`
  - `convertWmaToWav()`
  - `ensurePlayerInitialized()`
  - `getEpicenterAudioProcessors()`
- `plugins/just_audio_epicenter/android/src/main/kotlin/com/ryanheise/just_audio/EpicenterAudioProcessor.kt`
  - `onConfigure()`
  - `queueInput()`
- `plugins/just_audio_epicenter/android/src/main/kotlin/com/ryanheise/just_audio/EpicenterDsp.kt`
  - `processInterleaved()`
- `android/app/build.gradle.kts`
  - AAR local `decoder_ffmpeg-release.aar`
  - FFmpegKit

### Ruta comprobada

```text
Archivo/URI
  -> ProgressiveMediaSource + DefaultExtractorsFactory
  -> Media3 renderer/decoder
  -> PCM entregado al DefaultAudioSink
  -> EpicenterAudioProcessor
  -> EpicenterDsp
  -> AudioProcessor output buffer
  -> DefaultAudioSink
  -> AudioTrack de Android
  -> Android Audio HAL
  -> DAC interno o USB
```

Para WMA local, antes de Media3 ocurre además:

```text
WMA -> FFmpegKit -> WAV PCM signed 16-bit little-endian -> Media3
```

El `DefaultAudioSink` se construye con:

```java
.setAudioProcessors(getEpicenterAudioProcessors())
.setEnableFloatOutput(false)
```

El renderer FFmpeg se habilita mediante `EXTENSION_RENDERER_MODE_ON`, pero el código auditado no demuestra que FFmpeg sea seleccionado para cada extensión ni que su PCM interno conserve la resolución original.

## 3. Formato que recibe Epicenter

Archivo: `EpicenterAudioProcessor.kt`, método `onConfigure()`.

Epicenter acepta exclusivamente:

```text
C.ENCODING_PCM_16BIT
```

Si Media3 entrega otro encoding, se lanza `UnhandledAudioFormatException`.

El formato que recibe efectivamente el DSP es:

```text
PCM signed 16-bit intercalado, little-endian
```

`onConfigure()` conserva el sample rate y el número de canales recibidos y crea:

```kotlin
EpicenterDsp(inputAudioFormat.sampleRate)
```

No existe una ruta de entrada PCM float para Epicenter.

## 4. Sample Rate que recibe Epicenter

Epicenter recibe `inputAudioFormat.sampleRate` del `AudioProcessor`; no fija 44.1 kHz ni 48 kHz en su propio código.

La tabla siguiente describe el comportamiento verificable:

| Archivo/stream de origen | Sample rate que puede recibir Epicenter | ¿Garantizado por este repositorio? |
|---|---:|---|
| 44.1 kHz | 44.1 kHz si Media3 conserva ese formato hasta el sink | No se fuerza ni se prueba aquí |
| 48 kHz | 48 kHz si Media3 conserva ese formato hasta el sink | No se fuerza ni se prueba aquí |
| 96 kHz | 96 kHz si decoder, sink y dispositivo lo aceptan | No se garantiza |
| 192 kHz | 192 kHz si decoder, sink y dispositivo lo aceptan | No se garantiza |

El DSP calcula sus coeficientes a partir del sample rate recibido. No hay una tabla de conversión ni un `AudioProcessor` de resampling explícito en el código del proyecto.

## 5. Bit Depth que recibe Epicenter

Epicenter recibe 16 bits por muestra. La ruta exacta es:

```text
ByteBuffer PCM16 -> short -> FloatArray normalizado -> EpicenterDsp
```

El `EpicenterDsp` opera internamente con `Float` de Kotlin, pero esos floats son derivados de PCM16 y no contienen más resolución que la fuente PCM16 recibida.

La salida del procesador vuelve a ser PCM16. No existe una ruta actual:

```text
PCM24 -> float de alta resolución -> PCM24
```

## 6. Conversión PCM

### Conversión int16 -> float32

En `EpicenterAudioProcessor.queueInput()`:

```kotlin
input[i] = inSlice.short.toFloat() / 32768f
```

Esto convierte PCM signed 16-bit a `Float`.

### Conversión float32 -> int16

En la misma clase:

```kotlin
val intSample = (sample.coerceIn(-1f, 1f) * 32767f)
    .toInt()
    .coerceIn(-32768, 32767)
```

La muestra se escribe en little-endian.

### 16-bit -> 24-bit

No se encontró conversión 16-bit → 24-bit.

### 24-bit -> 16-bit

No hay una línea explícita con ese nombre, pero el efecto de la arquitectura es que cualquier audio que llegue a Epicenter como PCM de mayor resolución debe ser reducido al encoding PCM16 antes o al entrar en `EpicenterAudioProcessor`, porque `onConfigure()` rechaza otros encodings. El sink además tiene `setEnableFloatOutput(false)`.

En WMA la reducción sí es explícita:

```java
-acodec pcm_s16le
```

### Otras conversiones

- WAV WMA intermedio: WMA → WAV PCM signed 16-bit.
- Epicenter: PCM16 → float → PCM16 por bloque.
- El bypass también recodifica PCM16 → float → PCM16; no es copia binaria.
- No hay dithering configurado en el código auditado.

## 7. FLAC

### FLAC 16/44.1

Ruta esperada:

```text
FLAC 16/44.1 -> extractor/decoder Media3 -> PCM -> Epicenter
```

Si Media3 entrega PCM16 a este sink, Epicenter recibe PCM16 a 44.1 kHz. El código no contiene un resampler que obligue a 48 kHz.

### FLAC 24/96 y 24/192

El archivo puede declarar 24 bits y 96/192 kHz, pero el repositorio no contiene una ruta de preservación de PCM24 hacia Epicenter. Epicenter solo acepta PCM16. Por tanto:

- el sample rate podría conservarse si decoder, sink y dispositivo lo aceptan;
- la profundidad no se conserva hasta Epicenter;
- el punto exacto de reducción a PCM16 está dentro de la cadena Media3/AudioSink o del renderer antes de `onConfigure()`, no en un archivo propio del proyecto;
- no se puede afirmar estáticamente que 96/192 llegue al sink real de cada dispositivo.

## 8. WAV

### WAV 24/96 y WAV 24/192

`ProgressiveMediaSource` usa `DefaultExtractorsFactory`; no hay una conversión WAV explícita en el código del proyecto. Sin embargo, la entrada del `AudioProcessor` sigue siendo exclusivamente PCM16.

Resultado verificable:

```text
WAV PCM24 -> Media3/renderer/sink -> PCM16 requerido por Epicenter
```

El repositorio no muestra una ruta PCM24→PCM24 ni PCM float→PCM float.

### WAV PCM16

Puede llegar a Epicenter como PCM16, sujeto a que Media3 configure el mismo sample rate para el sink. No existe un resampler propio que fuerce 44.1 o 48 kHz.

## 9. WMA

Para archivos locales cuyo path termina en `.wma`, `AudioPlayer.prepareWmaUri()` llama a `convertWmaToWav()`.

FFmpegKit ejecuta:

```text
-y -i input.wma -vn -acodec pcm_s16le output.wav
```

Consecuencias:

- WMA se decodifica mediante FFmpegKit, no directamente como WMA dentro de Media3 en esa ruta local.
- La salida intermedia es PCM signed 16-bit little-endian en un WAV.
- No se especifica `-ar`; el código no fuerza 44.1, 48, 96 ni 192 kHz.
- No se especifica el número de canales; FFmpeg conserva su comportamiento por defecto para esa conversión.
- El archivo se almacena en cache y se reutiliza por ruta, tamaño y fecha de modificación.

Por tanto, WMA pierde la posibilidad de entregar PCM de mayor profundidad a Epicenter porque la conversión fuerza `pcm_s16le`. Si la conversión falla, se conserva la URI original y Media3 intenta reproducirla; el formato resultante en ese caso no queda determinado por este repositorio.

## 10. Low-Frequency Detection

Archivo: `EpicenterDsp.kt`, método `processInterleaved()`.

La detección recibe la señal PCM16 ya convertida a float y usa los dos primeros canales:

```text
mono = (left + right) / 2
diff = (left - right) / 2
```

La señal mono pasa por bandas pasantes alrededor de 60, 80 y 110 Hz, además de un pasa-bajos de 120 Hz. La actividad se pondera y se sigue mediante `detectorEnv`.

La compuerta también utiliza:

- energía mono (`monoEnv`);
- energía diferencial (`diffEnv`);
- relación diferencial/mono;
- actividad del detector.

Esto es restauración/generación dependiente de análisis, no un simple aumento de una banda fija.

La precisión del detector está limitada por la cuantización PCM16 antes de llegar al DSP. El float interno evita operaciones enteras durante el cálculo, pero no recupera información descartada antes.

## 11. Bass Extraction

Por canal, `EpicenterDsp` usa:

- `voiceHighpass`: ruta de presencia vocal;
- `bassLowpass`: programa de graves original;
- `lowMidBody`: cuerpo low-mid;
- `lowMidDip`: reducción selectiva low-mid;
- `subLowpass`: filtrado de la señal generada.

El programa de graves se forma con:

```text
bassProgram * bassProgramAmount
+ body * lowMidBodyAmount * protección vocal
- dip * lowMidDipAmount
```

La extracción no conserva una copia bit-perfect del espectro completo. Conserva una ruta filtrada (`voicePath`) y reconstruye una mezcla tonal de graves/low-mid.

## 12. GENERATED / Harmonic Generation

La señal `GENERATED` se genera en `EpicenterDsp.processInterleaved()` antes del bucle por canales.

### Entrada utilizada

La entrada es la señal mono derivada de los primeros dos canales, ya normalizada desde PCM16. El detector de graves produce una envolvente.

### Generación

La señal generada se construye mediante un estado `flipState` que cambia en cruces positivos del detector:

```text
rawHalf = flipState * detectorEnv
```

Después se aplican:

- pasa-altos de síntesis;
- pasa-bajos de síntesis;
- envelope de nivel;
- compuerta con retención;
- saturación suave;
- cantidad dependiente de `intensity`.

### Filtrado y control

La señal resultante se filtra de nuevo por `subLowpass` en cada canal y se reduce cuando la presencia vocal exige protección.

No es una síntesis armónica de precisión basada en preservar una copia original y añadir parciales medidos; es una señal adicional derivada de la envolvente detectora y de la conmutación de fase.

## 13. ORIGINAL

La arquitectura actual no conserva una copia completa y directa de `ORIGINAL` hasta la suma final.

La ruta que representa parte de la señal original es:

```text
voicePath = voiceHighpass(input)
```

Luego se añade un programa de graves y low-mid también filtrado. La salida no es simplemente el original sin tocar más la señal generada.

Esto es relevante para el objetivo:

```text
FINAL = ORIGINAL + GENERATED
```

El código actual implementa más bien:

```text
FINAL = filtrado_de_original + graves_filtrados + GENERATED
```

Por ello, la implementación actual no cumple literalmente con conservar `ORIGINAL` completo.

## 14. ORIGINAL + GENERATED

La suma real por canal es:

```kotlin
var mixed = voicePath + shapedBassProgram + generatedSub
```

Donde `generatedSub` es la señal adicional y `shapedBassProgram` contiene graves/low-mid derivados de la entrada. La suma pasa por:

1. ganancia de volumen;
2. factor de protección vocal;
3. saturación `tanh`;
4. pasa-altos final de 18 Hz;
5. cuantización PCM16.

### Discrepancia con la arquitectura objetivo

No existe un mezclador explícito con dos entradas `ORIGINAL` y `GENERATED`. Hay varias rutas procesadas de la entrada y una señal generada. Esto puede comportarse como restauración de graves, pero no es una suma transparente `ORIGINAL + GENERATED`.

## 15. Limiter / Headroom

Existe headroom lógico en la intensidad:

```text
intensity / 100 * 0.75
```

La protección de `GENERATED` usa `tanh`. La mezcla total también usa `tanh`:

```text
tanh(mixed * 0.94) / tanh(0.94)
```

La salida PCM vuelve a limitarse a `[-1, 1]` y luego a rango int16.

No existe un limiter true-peak, look-ahead, oversampling o medición de pico/RMS en el código de Epicenter. La protección es saturación suave más clamp de cuantización.

## 16. Media3

La versión configurada en el plugin es Media3 `1.4.1`.

`AudioPlayer` crea un `DefaultRenderersFactory` personalizado y un `DefaultAudioSink` con el `EpicenterAudioProcessor`.

Se habilita:

```java
EXTENSION_RENDERER_MODE_ON
```

También se configuran preferencias de audio offload desde `androidAudioOffloadPreferences`. El repositorio no contiene una prueba que demuestre si el dispositivo final acepta offload cuando hay un `AudioProcessor` personalizado.

Media3 decide el formato PCM intermedio según decoder, renderer, sink y capacidades. El punto comprobable del proyecto es que Epicenter exige PCM16 y el sink tiene float output deshabilitado.

## 17. AudioTrack

El proyecto no crea `AudioTrack` directamente. `DefaultAudioSink` de Media3 lo crea y lo configura internamente.

El código propio solicita:

```java
.setEnableFloatOutput(false)
```

Esto impide que el sink seleccione su ruta de salida float como preferencia. El encoding, sample rate, canales, tamaño de buffer y modo final de `AudioTrack` dependen de Media3 y del dispositivo.

No hay una llamada propia a:

```text
AudioTrack.Builder
AudioTrack.write()
```

en el código auditado.

## 18. Android Audio Output

La ruta posterior a Media3 es gestionada por Android:

```text
DefaultAudioSink -> AudioTrack -> AudioFlinger/HAL -> DAC
```

El repositorio no configura directamente el HAL ni puede garantizar el formato físico del DAC. El formato solicitado al sink no equivale automáticamente al formato que el hardware acepta.

No se fuerza 96 kHz o 192 kHz desde el código auditado.

## 19. DAC / USB DAC

No se encontró código específico para seleccionar, consultar o forzar un DAC interno o USB DAC.

La capacidad real depende de:

- dispositivo Android;
- versión del sistema;
- ruta de AudioFlinger;
- mixer policy;
- audio effects;
- USB audio policy;
- DAC conectado;
- formato aceptado por el `AudioTrack`.

El repositorio por sí solo no permite confirmar la resolución real en el DAC. Debe medirse en runtime con información del dispositivo y una prueba de señal.

## 20. Resampling

No se encontró un resampler explícito propio del proyecto ni una configuración que fuerce 44.1 o 48 kHz.

Posibles puntos externos donde Media3/Android podrían adaptar el sample rate:

- decoder/renderer;
- configuración del `DefaultAudioSink`;
- creación de `AudioTrack`;
- AudioFlinger/HAL;
- mixer del dispositivo.

El código auditado no identifica cuál de esos puntos resamplea en un dispositivo concreto.

Para WMA, FFmpegKit no recibe `-ar`, por lo que la conversión no fuerza un sample rate concreto. Para FLAC/WAV, no hay una conversión explícita en el repositorio.

## 21. Pérdidas de calidad antes de Epicenter

Pérdidas o limitaciones comprobables:

1. Epicenter solo acepta PCM16.
2. La ruta del sink deshabilita float output.
3. WMA local se convierte explícitamente a `pcm_s16le`.
4. FLAC/WAV de 24 bits no tienen una ruta PCM24 hacia Epicenter.
5. No hay dithering configurado en la reducción.
6. El punto exacto de reducción de FLAC/WAV 24-bit no está en código propio y debe confirmarse con trazas de Media3.
7. El sample rate original no está garantizado hasta Epicenter por contrato del proyecto.

Para `FLAC 16/44.1`, la pérdida de bit depth antes de Epicenter no existe en origen, pero sí permanece limitada a PCM16.

Para `FLAC 24/96`, `FLAC 24/192`, `WAV 24/96` y `WAV 24/192`, sí existe pérdida potencial o efectiva de profundidad antes de Epicenter porque la interfaz de entrada rechaza formatos distintos de PCM16. El repositorio no prueba por sí solo si el sample rate se conserva.

## 22. Pérdidas de calidad después de Epicenter

Después del DSP:

1. La salida vuelve a PCM16.
2. La salida no conserva PCM24 ni float.
3. El bypass también recuantiza.
4. `tanh` puede añadir distorsión armónica e intermodulación.
5. El filtro final de 18 Hz modifica la mezcla después de la saturación.
6. La suma actual no conserva `ORIGINAL` completo.
7. No existe true-peak limiting ni oversampling.
8. El sample rate final puede ser adaptado por Media3/AudioTrack/Android, pero no se fuerza en el proyecto.

## 23. Limitaciones actuales de Epicenter

Las limitaciones prioritarias para el objetivo de restauración de bajos son:

- Entrada fija en PCM16.
- Salida fija en PCM16.
- `Float` interno derivado de una fuente ya cuantizada a 16 bits.
- WMA reducido explícitamente a PCM16.
- Sin ruta de PCM24 o float de alta resolución.
- Sin garantía de sample rate original hasta Epicenter o DAC.
- Sin copia completa de `ORIGINAL`.
- La mezcla actual es una combinación de rutas procesadas más `GENERATED`.
- El “limiter” actual es saturación suave, no un limitador transparente.
- Asignaciones de buffers por callback de audio.
- Posible carrera al hacer `reset()` mientras el callback usa el DSP.
- Sin matriz de pruebas de 44.1/48/96/192 kHz y mono/estéreo/multicanal.
- Sin verificación de formato real del `AudioTrack` o DAC por dispositivo.

## 24. Arquitectura objetivo

La arquitectura objetivo para Epicenter, sin imponer Hi-Res donde el hardware no lo soporte, es:

```text
Archivo original
  -> decoder en la mayor resolución disponible
  -> PCM float o PCM de alta resolución
  -> ORIGINAL preservado
  -> análisis de baja frecuencia
  -> GENERATED
  -> ORIGINAL + GENERATED
  -> protección/limiter transparente
  -> formato máximo aceptado por AudioTrack
  -> HAL
  -> DAC
```

Para un caso ideal:

```text
FLAC 24/96 -> decoder -> float DSP -> Epicenter -> 24/96 output
WAV 24/192 -> decoder -> float DSP -> Epicenter -> 24/192 output
```

La salida debe retroceder a un formato menor cuando el sink, `AudioTrack`, HAL o DAC no soporte la resolución superior. No debe forzarse 96/192 sin comprobar la capacidad real.

## 25. Cambios necesarios para mejorar Epicenter

Esta sección identifica trabajo futuro; no se implementó nada durante esta auditoría.

1. Definir un contrato de formato interno de Epicenter: preferentemente float32 o una representación de alta resolución con headroom explícito.
2. Configurar el decoder/renderer/sink para entregar ese formato sin convertir innecesariamente a PCM16.
3. Eliminar la dependencia de `setEnableFloatOutput(false)` si la ruta float es compatible con el objetivo y el dispositivo.
4. Preservar `ORIGINAL` antes de filtros de extracción y sumar únicamente `GENERATED` adicional.
5. Diseñar la conversión de salida según capacidades reales del `AudioTrack`, no según una resolución fija.
6. Definir y probar una política de sample rate para 44.1, 48, 96 y 192 kHz.
7. Cambiar la conversión WMA para conservar la mayor resolución PCM que FFmpeg pueda entregar, evitando `pcm_s16le` como decisión automática si el decoder ofrece una alternativa adecuada.
8. Decidir dónde debe ocurrir el resampling cuando el hardware no soporte la resolución del archivo.
9. Añadir mediciones de formato negociado en decoder, sink y `AudioTrack`.
10. Diseñar protección de picos y headroom compatible con `ORIGINAL + GENERATED`.
11. Evitar asignaciones por callback de audio mediante buffers reutilizables.
12. Resolver la coordinación entre cambios de parámetros, reset y el hilo de audio.
13. Crear pruebas con tonos, impulsos y archivos 16/44.1, 24/96 y 24/192.
14. Validar calidad en salida interna y USB DAC sin asumir que la ruta Android conserva la resolución.

## 26. Riesgos

| Riesgo | Evidencia | Consecuencia |
|---|---|---|
| Reducción a PCM16 antes de Epicenter | `onConfigure()` solo acepta `ENCODING_PCM_16BIT` | Menor precisión de detección, envelopes, control dinámico y `GENERATED` |
| WMA forzado a PCM16 | `-acodec pcm_s16le` | Pérdida de profundidad antes del DSP |
| Float output deshabilitado | `.setEnableFloatOutput(false)` | Se cierra la ruta float del sink |
| Original no preservado íntegramente | `voicePath + shapedBassProgram + generatedSub` | No se cumple literalmente `ORIGINAL + GENERATED` |
| Saturación usada como protección | `tanh` en síntesis y mezcla | Distorsión e intermodulación |
| Sample rate no garantizado | No hay política ni prueba de negociación | 96/192 podrían reducirse antes o después de Epicenter |
| AudioTrack/HAL no inspeccionados | Media3/Android gestionan la salida | El formato solicitado puede no ser el formato físico real |
| Asignaciones por bloque | `FloatArray(samples)` y `FloatArray(frames)` | Presión de GC y posibles glitches |
| Reset no sincronizado | `dsp?.reset()` desde setter de control | Carrera con el callback de audio |
| WMA convertido a archivo temporal | FFmpegKit + cache | Latencia, I/O y posible degradación previa |
| Offload no validado con processor | Preferencias configurables, sink con AudioProcessor | Posible incompatibilidad o ruta no procesada |

## Conclusión de auditoría

El motor actual funciona como una cadena PCM16 con DSP interno `Float`, no como una cadena float/Hi-Res de extremo a extremo. Epicenter sí recibe y procesa floats durante sus operaciones matemáticas, pero la resolución efectiva de entrada ya está limitada a 16 bits y la salida vuelve a PCM16.

La principal pérdida para el objetivo del proyecto ocurre antes y después de Epicenter por el contrato PCM16 del `AudioProcessor`, por la conversión WMA a `pcm_s16le` y por `setEnableFloatOutput(false)`. Además, la implementación actual no conserva literalmente `ORIGINAL`; mezcla rutas filtradas de la entrada con `GENERATED`.

Las partes que no deberían tocarse sin una especificación y pruebas previas son:

- la baseline `docs/EPICENTER_BASELINE.md`;
- el diseño visual y assets no relacionados con el motor;
- la semántica de controles hasta decidir su nuevo contrato;
- la compatibilidad de formatos existente sin una matriz de regresión;
- el comportamiento de reproducción, navegación y UI;
- la ruta de fallback WMA hasta definir el formato PCM objetivo;
- la configuración de AudioTrack/HAL sin medición en dispositivos reales.

