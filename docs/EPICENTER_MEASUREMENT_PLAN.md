# Epicenter Measurement Plan

**Fecha:** 2026-10-02  
**Fase:** 0 — medición y referencia  
**Estado:** plan aprobado para preparar la medición; no implementa Fase 1.  
**Baseline protegida:** `docs/EPICENTER_BASELINE.md` no debe modificarse.

## Alcance y regla de no alteración

Este plan mide el comportamiento actual de Epicenter como restaurador de graves. No cambia el algoritmo, el sonido, el formato de producción, los controles ni la ruta de audio.

Durante la Fase 0 no se modifican:

- `EpicenterDsp.kt`;
- `EpicenterAudioProcessor.kt`;
- `AudioPlayer.java`;
- Media3, `AudioTrack`, WMA, UI, controles, dependencias, `pubspec`, baseline ni assets.

La instrumentación futura debe ser observacional: capturar copias, contadores y metadatos sin insertar filtros, ganancias o conversiones nuevas en la ruta de producción.

## 1. Señales y métricas que deben medirse

Por bloque, canal y archivo/prueba se deben registrar:

| Señal/métrica | Definición |
|---|---|
| `ORIGINAL` | PCM que entra a Epicenter, antes del DSP |
| `GENERATED` | Señal adicional generada por Epicenter |
| `FINAL` | Salida del DSP antes de la escritura final |
| `FINAL - ORIGINAL` | Diferencia alineada muestra a muestra; aproximación observable de `GENERATED` y de cualquier modificación al original |
| Peak | Pico absoluto y pico por canal, lineal y dBFS |
| RMS | RMS global, por canal y por ventana |
| Energía de baja frecuencia | Energía de bandas alrededor de 60, 80, 100/110 y rango configurado |
| `f0` detectada | Frecuencia estimada, confianza, estabilidad y tiempo activo |
| Armónicos | Nivel relativo de `2f`, `3f`, `4f` y parciales presentes |
| CPU | Tiempo de procesamiento por bloque, promedio, p95, p99 y margen respecto al tiempo real |
| Sample rate | Valor del formato recibido por el processor y del formato de salida |
| Encoding | PCM16, PCM24, float u otro en cada frontera |
| Canales | Número de canales de entrada, processor, sink y salida |
| Clipping | Muestras fuera de rango, muestras limitadas y duración acumulada |
| Saturación | Diferencia entre señal lineal y señal posterior a `tanh`/limitación |
| Fase | Fase L/R de la banda grave y coherencia de la señal generada |
| Respuesta | Ganancia por frecuencia de `ORIGINAL`, `GENERATED` y `FINAL` |

Cada captura debe incluir archivo, formato nominal, parámetros, dispositivo, versión Android, buffer size y timestamp.

## 2. Criterio `Intensity = 0`

La prueba de bypass debe verificar:

```text
Intensity = 0
GENERATED = 0
FINAL = ORIGINAL
```

Se deben comparar:

1. número de muestras;
2. sample rate;
3. canales;
4. peak y RMS;
5. diferencia muestra a muestra;
6. hash binario, si se dispone del buffer PCM original y final.

El comportamiento actual debe medirse sin asumir que es bit-perfect: la implementación existente recodifica PCM16 mediante float incluso en bypass. La tolerancia y la diferencia real deben quedar registradas, no corregirse en esta fase.

## 3. Intensidad

Para cada entrada se ejecutan cinco pasadas con los mismos parámetros:

| Intensidad | Resultado requerido |
|---:|---|
| 0 | Referencia de bypass |
| 25 | Nivel y energía inicial de `GENERATED` |
| 50 | Referencia nominal actual |
| 75 | Aumento de generación y protección |
| 100 | Máximo permitido y comportamiento ante clipping |

Registrar por pasada:

- RMS y peak de `ORIGINAL`;
- RMS y peak de `GENERATED`/`FINAL - ORIGINAL`;
- RMS y peak de `FINAL`;
- energía grave;
- `f0` y confianza;
- armónicos;
- clipping/saturación;
- CPU;
- diferencia de fase.

El nivel de `ORIGINAL` debe permanecer constante entre pasadas; si cambia, se documenta como comportamiento actual y no se interpreta como restauración pura.

## 4. Sweep

Repetir las pasadas con:

- 27 Hz;
- 45 Hz;
- 63 Hz.

Mantener `Intensity`, `Width`, `Balance` y `Volume` constantes. Medir:

- frecuencias detectadas;
- coeficientes/respuesta de las bandas;
- `f0`;
- parciales generados;
- nivel de `GENERATED`;
- transitorios al cambiar el valor;
- CPU y estabilidad entre bloques.

## 5. Corpus de señales

### Señales sintéticas

1. Silencio.
2. Seno grave de 30–45 Hz.
3. Seno de 60 Hz.
4. Seno de 80 Hz.
5. Seno de 100 Hz.
6. Seno con armónicos controlados.
7. Fundamental ausente con armónicos presentes.
8. Barrido grave.
9. Impulso y transitorios cortos.
10. Ruido de banda ancha.

### Material real

1. Voz hablada y cantada.
2. Música completa.
3. Bajo aislado.
4. Batería/transitorios.
5. Mezcla estéreo con bajo centrado.
6. Mezcla estéreo con contenido lateral.
7. La misma señal convertida a mono.

Cada señal debe tener duración, nivel de entrada y formato documentados para permitir repetición.

## 6. Métricas de nivel, clipping, fase y respuesta

### Nivel

Calcular RMS, peak, crest factor y LUFS si la herramienta externa está disponible para:

- `ORIGINAL`;
- `GENERATED`;
- `FINAL`;
- `FINAL - ORIGINAL`.

### Clipping y saturación

Contar:

- muestras `abs(x) > 1`;
- muestras exactamente limitadas a `-1` o `1`;
- muestras afectadas por la conversión PCM;
- diferencia entre mezcla previa y salida protegida;
- duración de eventos de saturación.

### Fase

Medir:

- correlación L/R;
- fase de `ORIGINAL` grave;
- fase de `GENERATED` respecto a `ORIGINAL`;
- correlación de `FINAL`;
- cancelación al sumar mono.

### Respuesta de frecuencia

Usar senos y barridos con igual nivel de entrada para obtener:

- transferencia `ORIGINAL -> FINAL`;
- transferencia de `GENERATED`;
- ganancia en `f0`, `2f0`, `3f0`, `4f0`;
- cambios fuera de la banda grave;
- respuesta por canal.

## 7. Sample rates

Ejecutar el mismo corpus en:

- 44.1 kHz;
- 48 kHz;
- 96 kHz;
- 192 kHz.

Registrar en runtime el sample rate recibido por `onConfigure()` y el sample rate final negociado. No basta con el sample rate nominal del archivo.

Comparar:

- `f0` estimada;
- tiempos de envelope expresados en milisegundos;
- respuesta de filtros;
- CPU por muestra y por segundo;
- resampling detectado;
- cambios de fase o nivel.

Si el dispositivo no admite 96/192 kHz, la prueba debe marcar `UNSUPPORTED` y registrar el fallback, sin forzar el formato.

## 8. Encodings

Cuando la ruta lo permita, probar:

- PCM16;
- PCM24;
- FLOAT32;
- cualquier encoding negociado por Media3.

Para cada caso registrar:

1. encoding del archivo;
2. encoding entregado al decoder/renderer;
3. encoding recibido por `AudioProcessor`;
4. encoding de salida del processor;
5. encoding solicitado por `AudioTrack`;
6. encoding efectivo si el dispositivo lo expone;
7. fallback o excepción.

La expectativa de referencia actual es PCM16 en `EpicenterAudioProcessor`; PCM24 y float deben marcarse como `RECHAZADO`, `CONVERTIDO` o `NO OBSERVABLE`, nunca asumirse como soportados.

## 9. Identificación en runtime

La instrumentación futura debe observar, sin alterar el audio:

### AudioProcessor

En `onConfigure()` registrar:

- sample rate;
- encoding;
- channel count;
- bytes por frame;
- si el processor se configuró más de una vez;
- motivo de rechazo si no es PCM16.

En `queueInput()` registrar solo contadores agregados:

- bytes y frames por bloque;
- duración de procesamiento;
- allocations observadas si la herramienta las mide;
- peak/RMS de copias de entrada/salida.

No se debe hacer logging por muestra.

### AudioTrack/sink

Obtener mediante APIs de diagnóstico o dumps del dispositivo:

- sample rate;
- encoding;
- channel mask;
- buffer size;
- modo de transferencia;
- si hubo fallback;
- si el offload quedó activo;
- si el formato fue convertido.

### Resampling

Comparar sample count, sample rate y duración antes/después de cada frontera. Confirmar resampling mediante formato runtime, logs controlados de diagnóstico o análisis de tono; no inferirlo solo por el nombre del archivo.

## 10. Matriz de pruebas de formatos

| Caso | Archivo | Resolución nominal | Entrada esperada a Media3 | Entrada observada a Epicenter | Salida solicitada | Resultado |
|---|---|---|---|---|---|---|
| F1 | FLAC | 16/44.1 | Registrar | PCM16 actual esperado | Registrar | Pendiente de dispositivo |
| F2 | FLAC | 24/96 | Registrar | PCM16 actual esperado o rechazo | Registrar | Pendiente de dispositivo |
| F3 | FLAC | 24/192 | Registrar | PCM16 actual esperado o rechazo | Registrar | Pendiente de dispositivo |
| W1 | WAV | 16/44.1 | Registrar | PCM16 actual esperado | Registrar | Pendiente de dispositivo |
| W2 | WAV | 24/96 | Registrar | PCM16 actual esperado o rechazo | Registrar | Pendiente de dispositivo |
| W3 | WAV | 24/192 | Registrar | PCM16 actual esperado o rechazo | Registrar | Pendiente de dispositivo |
| M1 | WMA | Resolución reportada por FFprobe | WAV `pcm_s16le` por conversión actual | PCM16 esperado | Registrar | Pendiente de dispositivo |

Para cada fila se deben conservar:

- archivo de prueba y hash;
- metadata FFprobe;
- formato del renderer;
- formato `onConfigure()`;
- formato output;
- formato AudioTrack;
- sample rate en cada frontera;
- RMS/peak de `ORIGINAL`, `GENERATED`, `FINAL`;
- clipping, CPU y resultado de bypass.

## 11. Cómo separar ORIGINAL, GENERATED y FINAL

### Estado actual

La implementación no expone buffers independientes de `ORIGINAL` y `GENERATED`. Por eso, antes de Fase 1, deben considerarse dos niveles de medición:

1. **Medición externa:** capturar entrada y salida del processor; calcular `FINAL - ORIGINAL` después de alinear buffers.
2. **Medición interna futura:** exponer copias de diagnóstico de `subBuffer`/ruta generada sin cambiar su cálculo ni mezclarla de otra forma.

La medición externa no demuestra que `FINAL - ORIGINAL` sea exactamente `GENERATED`, porque el algoritmo actual también modifica la ruta original. Debe etiquetarse como:

```text
delta_observado = FINAL - ORIGINAL
```

y no como `GENERATED` puro hasta que exista una salida interna separada.

## 12. Verificaciones de estabilidad

Para cada prueba:

- repetir tres veces;
- comparar primeros, medios y últimos bloques;
- verificar continuidad entre bloques;
- comprobar reset/flush;
- activar/desactivar Epicenter durante reproducción;
- cambiar parámetros en límites y en pasos intermedios;
- medir clicks mediante pico diferencial y energía de alta frecuencia.

Registrar si el cambio de parámetro provoca discontinuidad, cambio de coeficientes o salto de ganancia.

## 13. CPU y realtime

Medir:

- duración de `queueInput()`;
- tiempo total de DSP;
- porcentaje del presupuesto de tiempo real;
- p50/p95/p99;
- jitter;
- GC durante reproducción;
- underruns/glitches;
- allocations por bloque;
- CPU por sample rate y canales.

La regla de aceptación preliminar es que p99 del procesamiento quede por debajo del tiempo de audio del bloque, con margen suficiente para decoder y sink. El umbral exacto debe fijarse tras medir el dispositivo objetivo.

## 14. Resultados esperados antes de instrumentación

Hechos ya verificables por inspección estática:

- `EpicenterAudioProcessor` acepta solo PCM16.
- Convierte PCM16 a `Float` y vuelve a PCM16.
- WMA local se convierte a WAV `pcm_s16le`.
- `DefaultAudioSink` tiene float output deshabilitado.
- El DSP actual no expone `ORIGINAL` y `GENERATED` por separado.
- `FINAL - ORIGINAL` puede calcularse externamente si se capturan ambos buffers alineados.

Todavía no existen resultados numéricos de peak, RMS, `f0`, armónicos, CPU, clipping, formato efectivo de `AudioTrack` ni DAC en esta Fase 0 documental.

## 15. Métricas obtenibles sin dispositivo físico

A partir del código y pruebas locales controladas pueden obtenerse:

- formato declarado de entrada exigido por Epicenter;
- conversiones PCM16 ↔ float;
- conversión WMA a `pcm_s16le`;
- parámetros y límites;
- ecuaciones de detección/generación;
- número y tipo de filtros;
- asignaciones por bloque;
- diferencias offline entre buffers si se construye un harness de reproducción de la lógica actual.

No debe confundirse una prueba offline con el formato real que Media3 o Android negocian.

## 16. Métricas que requieren dispositivo físico

Requieren un dispositivo Android real:

- formato efectivo de `AudioTrack`;
- sample rate y encoding efectivos del sink;
- fallback de 96/192 kHz;
- comportamiento del HAL;
- salida a DAC interno o USB;
- offload efectivo;
- resampling de Android;
- CPU, GC, underruns y glitches reales;
- estabilidad con buffers y cargas reales;
- medición eléctrica o digital del DAC.

## 17. Ejecución propuesta

### Estado actual

No existe todavía un test runner de medición específico en el repositorio. Por tanto, no hay un comando de Fase 0 que produzca métricas numéricas automáticamente sin añadir instrumentación.

### Preparación recomendada, sin ejecutar cambios todavía

1. Preparar corpus local con los siete casos de la matriz.
2. Obtener hashes y metadata con FFprobe/FFprobeKit.
3. Ejecutar la aplicación en un dispositivo conectado.
4. Activar/desactivar Epicenter y recorrer la matriz de parámetros.
5. Capturar buffers de entrada/salida mediante un harness de diagnóstico no productivo.
6. Exportar CSV/WAV de `ORIGINAL`, `delta_observado` y `FINAL`.
7. Calcular métricas offline con una herramienta reproducible.
8. Consultar el formato negociado de `AudioTrack`.
9. Repetir en cada sample rate que el dispositivo soporte.

### Comandos de verificación actuales

Estos comandos solo verifican el estado documental y no cambian el audio:

```powershell
git status --short
git diff --check -- docs/EPICENTER_MEASUREMENT_PLAN.md
```

La ejecución de pruebas de dispositivo queda pendiente de definir el harness y el dispositivo objetivo.

## 18. Criterios de aceptación de la Fase 0

La Fase 0 se considera completa cuando exista, para cada caso:

- captura de `ORIGINAL`;
- captura de `FINAL`;
- `delta_observado`;
- peak/RMS y clipping;
- energía grave y `f0`;
- armónicos;
- CPU y allocations;
- sample rate/encoding/canales en processor;
- formato solicitado y efectivo de AudioTrack cuando esté disponible;
- resultado de bypass;
- registro de resampling/fallback;
- archivo y parámetros reproducibles.

No se considera aprobada una medición que solo use la metadata del archivo o el sample rate nominal.

## 19. Preparación de Fase 1

La Fase 1 debe comenzar solo después de congelar los resultados de esta referencia. Sus primeros cambios previstos, fuera de este documento, son:

1. crear buffers diagnósticos reutilizables;
2. separar conceptualmente `ORIGINAL_FLOAT`, `GENERATED` y `FINAL`;
3. mantener la semántica actual mientras se comparan las señales;
4. no migrar todavía el algoritmo a FLOAT32 de producción;
5. no cambiar la generación ni los controles hasta contar con comparativas.

Los archivos previstos para la fase posterior son:

- `plugins/just_audio_epicenter/android/src/main/kotlin/com/ryanheise/just_audio/EpicenterDsp.kt`;
- `plugins/just_audio_epicenter/android/src/main/kotlin/com/ryanheise/just_audio/EpicenterAudioProcessor.kt`;
- `plugins/just_audio_epicenter/android/src/main/java/com/ryanheise/just_audio/AudioPlayer.java`;
- pruebas/harness de audio nuevos;
- solo si la negociación lo requiere, configuración específica de decoder/sink.

No se modifica en Fase 0:

- `docs/EPICENTER_BASELINE.md`;
- el algoritmo de generación;
- el formato actual de producción;
- UI, controles, assets, dependencias o `pubspec`.

