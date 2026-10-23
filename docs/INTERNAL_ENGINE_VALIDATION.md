# Auditoría y validación local del motor

Rama: `refactor/internal-engine-preserve-ui-folders`. PR #8 permanece draft.
Punto de partida: `d17267588f455684c5efbd54964a01d70b40e7d9`.
Se revisó el código actual, no se tomó `AUDIO_ENGINE_AUDIT.md` como descripción vigente.

## Contratos preservados

- Sin cambios en screens, widgets, assets, temas ni disposición visual durante esta etapa.
- Las nueve funciones de carpetas indicadas por el propietario se comparan textualmente contra `main` y `origin/main`, normalizando únicamente CRLF/LF. La comprobación pasó antes y después de las correcciones. No se movió navegación de carpetas.
- Sin cambios en **ningún archivo de producción Kotlin** del plugin: motores, filtros, analizadores, parámetros y ecuaciones siguen intactos.
- `.github/workflows/refactor-validate.yml` conserva exclusivamente `workflow_dispatch`.
- No se incorporó código de Rhythm ni Resonate. Las correcciones son propias y usan las APIs existentes.
- No se hizo merge, rebase ni force push. El checkout original y sus cambios locales en `main` se conservaron.

## Arquitectura y correcciones

`UI → AudioProvider → PlaybackEngine → MyAudioHandler → just_audio → Media3`

`AudioEffectsController → PlaybackEngine` para speed/pitch y `NativeAudioBridge` para efectos. El proveedor ya no recibe el reproductor crudo ni declara MethodChannel. El canal del widget también vive en el bridge y se desconecta al liberar el proveedor.

AudioProvider sigue siendo la fachada compatible y conserva biblioteca, carpetas y coordinación de contexto. No se afirma que todo el archivo sea pequeño: sacar biblioteca/metadata es trabajo independiente; no se hizo un refactor masivo que arriesgara carpetas.

| Problema encontrado | Corrección |
| --- | --- |
| Posición ≥ duración y estado completed podían competir con el avance nativo | Se elimina la detección por posición. Media3 avanza dentro de la cola; solo completed terminal solicita cambio de contexto, con identificación por revisión/índice |
| Play y pause de MediaSession llamaban al mismo toggle | Callbacks distintos, comandos idempotentes |
| `await player.play()` retenía la operación hasta pausar/finalizar | Inicio sin esperar la duración de la canción, con manejo de errores |
| Inserción en cola vacía anidaba el serializador | Operación interna que no vuelve a adquirirlo |
| Inserción/reordenación mezclaban la playlist interna de just_audio con la ConcatenatingAudioSource propia | Mutaciones sobre la misma fuente que se cargó |
| Fallo al mover publicaba una cola que podía no haberse aplicado | Se propaga el fallo; no se publica el orden fallido |
| UpdateQueue solo cambiaba metadata | Reconstruye la fuente real |
| Archivos inválidos podían provocar avances repetidos o bloquear la reproducción | Recuperación única y acotada a las pistas restantes, sin envolver incluso con loop; stop si todas fallan |
| El listener antiguo esperaba excepciones de playbackEventStream; just_audio 0.10 entrega fallos del decoder en errorStream | Suscripción a errorStream, descarte de errores tardíos de otra pista y maxSkipsOnError=0 explícito para evitar un segundo recuperador |
| Nueva cola o stop durante una carga podían terminar en autoplay tardío | Revisión de solicitudes e invalidación al pausar/detener |
| Provider también intentaba next después de un error de carga | Se elimina ese segundo propietario de recuperación |
| Suscripciones del proveedor permanecían activas | Cancelación en dispose, desconexión de callbacks y protección de notificaciones tardías |
| Artwork asíncrono podía acabar en otra canción | Validación de identidad tras esperar la portada |
| Mismo archivo repetido en cola mostraba su primera aparición | Se prioriza el índice nativo si corresponde al path |
| Borrar la última pista conservaba cola/restauración antiguas | Limpieza de fuente, MediaSession e instantánea persistida |
| Guardados de reproducción concurrentes mezclaban claves | Escrituras serializadas más snapshot JSON completo, compatible con instalaciones anteriores |
| Caché de ReplayGain retenía fallos temporales y resultados invalidados | Reintento, generación de caché e invalidación en sincronización de biblioteca |
| Comparación de biblioteca aceptaba duplicados en lugar de canciones faltantes | Comparación de multiplicidades |

La persistencia reduce estados mezclados; SharedPreferences no garantiza conservar los últimos milisegundos ante una muerte abrupta. Se mantiene restauración pausada al abrir la app y posición periódica cada dos segundos. No se promete reanudación tras force-stop del sistema sin volver a abrir la aplicación.

## Ruta PCM comprobada por código

Media3 está fijado en **1.4.1**. Ambos processors aceptan PCM16, PCM24, PCM32 y FLOAT32; `EpicenterPcm.kt` ya existía y se conserva.

Ruta efectiva actual:

`decoder → ToInt16PcmAudioProcessor / mapping / trim → ToneControls (EQ/ReplayGain) → Epicenter → procesadores Media3 de velocidad/silencio → AudioTrack → Android/HAL`

El orden ToneControls antes de Epicenter es el existente. Invertirlos cambiaría la señal que excita Epicenter y por tanto el sonido; se conservó por la restricción de esta fase.

**Aceptar PCM24/32/FLOAT en los processors no significa que DefaultAudioSink les entregue esos formatos.** En esta versión, la rama integer introduce `ToInt16PcmAudioProcessor` antes de la cadena personalizada. Activar float selecciona otra cadena que omite esos processors. Por eso permanece `setEnableFloatOutput(false)`; no se degradó una ruta Hi-Res existente ni se anuncia salida Hi-Res/bit-perfect.

Una ruta de mayor precisión con DSP requiere una implementación de AudioSink/renderer que procese antes de esa conversión, además de pruebas de trimming, gapless, velocidad, channel mapping y AudioTrack. Se conserva el fallback probado en lugar de cambiar el sink sin validación física.

Referencia primaria: [DefaultAudioSink 1.4.1](https://github.com/androidx/media/blob/1.4.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/audio/DefaultAudioSink.java), constructor, configure y setEnableFloatOutput.

## WMA y caché

FFprobe consulta el primer stream de audio. Profundidad conocida ≤16 → `pcm_s16le`; 17–24 → `pcm_s24le`; 25–32 → `pcm_s32le`. Si no hay profundidad, se conserva la representación entera del decoder cuando se conoce, o FLOAT32 para salida float/desconocida. Un WMA con pérdida no adquiere resolución original de 32 bits por almacenarse como float: se evita una cuantización intermedia adicional.

No se pasan `-ar` ni `-ac`: se conservan frecuencia y canales del stream seleccionado. El caché v2 depende de path/tamaño/mtime, invalida WAV antiguos PCM16, serializa conversiones y publica un `.partial.wav` solo tras éxito. Un cambio del archivo durante la conversión impide publicar ese resultado. Si falla FFprobe se intenta FLOAT32; si falla FFmpeg se conserva el fallback de URI original.

Limitaciones: WMA local con URI file; no se amplió a content/SAF. La conversión existente sigue siendo síncrona y puede retrasar la preparación de archivos grandes; no se promete reproducción instantánea. No se aportaron muestras WMA originales para verificar su profundidad real en esta sesión. La selección se evalúa por archivo en ejecución y tiene pruebas unitarias. La cuantización posterior del sink descrita arriba sigue existiendo.

Referencias: [FFprobe](https://ffmpeg.org/ffprobe.html), [WavUtil de Media3 1.4.1](https://github.com/androidx/media/blob/1.4.1/libraries/extractor/src/main/java/androidx/media3/extractor/WavUtil.java) (PCM entero 16/24/32 y float de 32 bits), y [formatos Media3](https://developer.android.com/media/media3/exoplayer/supported-formats).

## Offload, formatos y Android

Se fuerza `AUDIO_OFFLOAD_MODE_DISABLED` al construir las preferencias efectivas del reproductor, incluso si el llamador solicita offload. Los efectos pueden activarse durante reproducción; esta política conservadora evita que un cambio de controles omita el DSP. Con todo OFF sigue deshabilitado: habilitarlo dinámicamente queda fuera de esta corrección segura.

| Entrada | Ruta esperada / alcance de validación |
| --- | --- |
| MP3, AAC/M4A | Extractor Media3 + decoder disponible en Android |
| OGG/Vorbis, OPUS | Extractor correspondiente + decoder disponible; depende del contenedor/perfil |
| FLAC 16/44.1, 24/48, 24/96, 24/192 | Soporte de extracción/decodificación; precisión efectiva limitada por sink actual |
| WAV 16/44.1, 24/96, 24/192; PCM32/FLOAT | Formatos PCM aceptados por processors; sink actual convierte antes del DSP |
| WMA | FFprobe + FFmpeg a WAV local, caché y fallback descritos arriba |

No se fuerza 192 kHz ni se añade resampling propio. AudioTrack y Android/HAL negocian con el dispositivo; el mezclador, Bluetooth y hardware pueden remuestrear. La matriz JVM prueba processors, no certifica todos los codecs en un teléfono. Android 15 no elimina las limitaciones de la cadena Media3. No hay dispositivo ADB conectado: notificación, lock screen, Bluetooth, Android Auto, rutas físicas y muerte real del proceso necesitan prueba física. Tampoco se certifica compatibilidad de todas las bibliotecas nativas con dispositivos de páginas de memoria de 16 KB solo porque compile el APK.

## DSP realtime

Buffers internos reutilizados; Epicenter divide el trabajo en bloques de hasta 4096 samples. Motores preparados en flush; snapshots de controles fuera del callback. El buffer de salida de BaseAudioProcessor puede crecer cuando llega un bloque mayor. No se afirma cero allocations absolutas sin perfilar ART: el análisis estático y las pruebas demuestran reutilización normal y estabilidad funcional, no un perfil de latencias del dispositivo.

OFF/intensity 0 conserva bytes una vez completada la rampa de salida. No se eliminó esa rampa para forzar un bypass inmediato que alteraría el comportamiento audible. Las pruebas cubren bytes de bypass, motores, cambios de formato, buffers grandes, mono/estéreo/multicanal, flush/reset y muestras finitas. No se cambiaron referencias sonoras.

## Validación local

Los resultados finales y SHA se entregan junto con este reporte. Comandos utilizados:

```text
flutter pub get
flutter analyze --no-pub <archivos Dart modificados y tests>
flutter test --no-pub <pruebas de handler, persistencia, ReplayGain, política, arquitectura y selector>
android/gradlew.bat :just_audio:testDebugUnitTest --console=plain --max-workers=2
flutter build apk --debug --no-pub
flutter build apk --release --no-pub
git diff --check
```

Resultados: `flutter pub get` correcto; análisis de todos los Dart modificados y tests sin incidencias (incluida repetición del handler tras el último ajuste); 36 tests Dart enfocados y 33 tests JVM aprobados. Se ejecutaron por grupos, no se presenta el suite completo como validado. Las pruebas de carpetas volvieron a pasar después de los cambios y `git diff --check` no reportó errores.

Los APK debug y release compilaron correctamente. Se repitió la compilación tras los cambios de recuperación. Los APK release de este checkout usan la configuración existente: sin `key.properties`, se firma con la clave debug; no es una entrega firmada para Play Store. Los warnings de versiones/NDK existentes no se resolvieron alterando dependencias o UI.

## Archivos de esta etapa

- `lib/providers/audio_provider.dart`: coordinación, listeners, índices, cola vacía y bridge.
- `lib/services/audio_handler.dart`: MediaSession, cola, finalización y recuperación.
- `lib/services/playback_engine.dart`: frontera de playback y speed/pitch.
- `lib/services/audio_effects_controller.dart`: gateway y ciclo de vida.
- `lib/services/native_audio_bridge.dart`: acciones del widget.
- `lib/services/playback_queue_policy.dart`: multiplicidades e índice de repetidos.
- `lib/services/replay_gain_repository.dart`: caché, reintentos y resultados obsoletos.
- `lib/services/state_persistence.dart`: instantánea y serialización.
- `plugins/just_audio_epicenter/android/src/main/java/com/ryanheise/just_audio/AudioPlayer.java`: WMA y bloqueo de offload.
- `plugins/just_audio_epicenter/android/src/main/java/com/ryanheise/just_audio/WmaPcmPolicy.java`: política propia de precisión.
- Tests Dart en `test/architecture` y `test/services`; tests Java/Kotlin `WmaPcmPolicyTest` y `PcmLifecycleTest`.
- Este reporte. No se incluyen cambios generados por pub get en plataformas ajenas a Android.
