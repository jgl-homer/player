# 🎵 Player

### Reproductor de música para Android • DSP • Epicenter • Audio de alta calidad

> **Player** es un reproductor de música desarrollado con Flutter, enfocado en reproducción local, procesamiento DSP personalizado y un sistema **Epicenter / restaurador de bajos**.

La idea principal del proyecto es:

> **Mantener el audio con la mayor calidad posible mientras se ofrece un procesamiento de graves potente y configurable.**

El repositorio contiene una implementación personalizada de `just_audio` dentro de `plugins/just_audio_epicenter`, lo que permite modificar el motor de reproducción específicamente para este proyecto.

---

## 🚧 Estado del proyecto

**Estado:** En desarrollo activo

El proyecto todavía está en desarrollo. Algunas funciones mencionadas en la hoja de ruta son objetivos futuros y **no deben considerarse implementadas todavía**.

Actualmente el proyecto cuenta con una aplicación Flutter, un plugin local basado en `just_audio`, integración con `audio_service`, `audio_session`, acceso a la biblioteca musical del dispositivo, lectura de metadatos, almacenamiento local y el desarrollo del Epicenter.

---

# 🎯 Objetivo del proyecto

Player busca ser un reproductor de música local avanzado, no solamente un reproductor básico.

La arquitectura de audio que se busca conseguir es:

```text
┌─────────────────────────┐
│      ARCHIVO DE AUDIO   │
│                         │
│ MP3 / FLAC / WAV / WMA  │
│ AAC / OGG / PCM / ...   │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│        DECODIFICADOR    │
│                         │
│ Nativo / FFmpeg         │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│           PCM           │
│                         │
│ Mantener la resolución  │
│ original cuando sea     │
│ posible                 │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│       MOTOR DSP         │
│                         │
│ Epicenter               │
│ Restaurador de bajos    │
│ Ecualizador             │
│ Ganancia                │
│ Limitador               │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│      SALIDA DE AUDIO    │
│                         │
│ AudioTrack / AAudio     │
│ Android Audio HAL       │
│ DAC USB                 │
└────────────┬────────────┘
             │
             ▼
           🔊 DAC
```

---

# 🔊 Epicenter

El **Epicenter** es una de las características principales de Player.

Su objetivo es procesar las frecuencias graves y recuperar/reforzar la percepción de bajos que pueden sentirse débiles después de determinados procesos de reproducción.

### Flujo de procesamiento

```text
Audio original
      │
      ▼
  Decodificador
      │
      ▼
      PCM
      │
      ▼
┌───────────────┐
│   EPICENTER   │
│               │
│ Restauración  │
│ de bajos      │
│ Procesamiento │
│ de graves     │
└───────┬───────┘
        │
        ▼
   Salida de audio
```

El Epicenter forma parte del concepto central del reproductor y está integrado en el flujo de audio.

---

# 🎛️ Motor DSP

El proyecto está diseñado para procesar el audio después de la decodificación.

La arquitectura objetivo es:

```text
ARCHIVO
  │
  ▼
DECODIFICADOR
  │
  ▼
PCM
  │
  ▼
DSP EN FLOAT
  │
  ├── Epicenter
  ├── Restaurador de bajos
  ├── Ecualizador
  ├── Ganancia
  └── Limitador
  │
  ▼
SALIDA
```

El procesamiento interno en punto flotante permite realizar operaciones DSP con mayor margen y reducir conversiones innecesarias durante la cadena de procesamiento.

---

# 🎧 Audio de alta calidad

Player está pensado para trabajar con archivos de alta calidad como:

- FLAC
- WAV
- PCM
- MP3
- AAC
- WMA mediante un decodificador adicional cuando se implemente
- Otros formatos compatibles con el motor de reproducción

Una de las reglas principales del proyecto es:

> **No convertir todos los archivos automáticamente a una frecuencia o profundidad fija si no es necesario.**

Por ejemplo:

```text
FLAC 24-bit / 96 kHz
        │
        ▼
    Decodificador
        │
        ▼
PCM 24-bit / 96 kHz
        │
        ▼
       DSP
        │
        ▼
Salida a 96 kHz
```

Y:

```text
WAV 16-bit / 44.1 kHz
        │
        ▼
    Decodificador
        │
        ▼
PCM 16-bit / 44.1 kHz
        │
        ▼
       DSP
        │
        ▼
Salida a 44.1 kHz
```

La frecuencia y profundidad que finalmente llegan al DAC dependen del dispositivo Android, del controlador de audio, del hardware y de la ruta de salida utilizada.

---

# ⚠️ Hi-Res no significa automáticamente Bit-Perfect

Hay que distinguir entre la calidad del archivo y la calidad física de la salida.

### Archivo

```text
FLAC 24-bit / 96 kHz
```

### Ruta de Android

```text
Aplicación
    ↓
Sistema de audio de Android
    ↓
Audio HAL
    ↓
DAC
```

Aunque el reproductor conserve 24/96 internamente, Android o el hardware pueden realizar un resampling antes de llegar al DAC.

Por eso el objetivo del proyecto es:

- Conservar los parámetros originales cuando sea posible.
- Evitar resampling innecesario.
- Utilizar la ruta de salida de mayor calidad disponible.
- Detectar las capacidades del dispositivo cuando sea posible.
- No afirmar que una salida es Bit-Perfect cuando el hardware no lo permite.

---

# 🧩 Compatibilidad de formatos

La estrategia del proyecto es utilizar el decodificador más apropiado para cada formato.

```text
                 ARCHIVO
                    │
          ┌─────────┴─────────┐
          │                   │
   Decodificador         FFmpeg
       nativo          cuando sea necesario
          │                   │
          └─────────┬─────────┘
                    ▼
                   PCM
                    │
                    ▼
                   DSP
                    │
                    ▼
                  SALIDA
```

La intención **no es pasar absolutamente todo por FFmpeg**.

Formatos que Android/el backend puedan manejar correctamente pueden continuar usando su ruta nativa.

FFmpeg se puede utilizar para ampliar la compatibilidad con formatos que no estén soportados adecuadamente, por ejemplo WMA.

---

# 📱 Plataformas

El proyecto utiliza:

- **Flutter**
- **Dart**
- **Android**
- iOS
- macOS
- Linux
- Windows
- Web

Android es la plataforma principal para las funciones avanzadas de audio.

---

# 🏗️ Estructura del proyecto

```text
player/
│
├── android/
│
├── ios/
│
├── linux/
│
├── macos/
│
├── web/
│
├── windows/
│
├── assets/
│   └── icon/
│
├── lib/
│   └── Código principal de la aplicación
│
├── plugins/
│   └── just_audio_epicenter/
│       ├── android/
│       ├── ios/
│       ├── macos/
│       ├── web/
│       └── lib/
│
├── test/
│
├── pubspec.yaml
├── pubspec.lock
├── analysis_options.yaml
└── README.md
```

El plugin personalizado se mantiene directamente dentro del repositorio:

```text
plugins/just_audio_epicenter/
```

Esto permite modificar el motor de reproducción sin depender exclusivamente de una versión externa sin cambios.

---

# 🧰 Tecnologías principales

| Tecnología | Uso |
|---|---|
| Flutter | Framework principal |
| Dart | Lenguaje principal |
| just_audio | Base del reproductor |
| just_audio_epicenter | Implementación personalizada |
| audio_service | Reproducción en segundo plano |
| audio_session | Administración de sesiones de audio |
| RxDart | Streams y programación reactiva |
| Provider | Administración de estado |
| on_audio_query | Acceso a la biblioteca musical |
| audiotags | Lectura de metadatos |
| SQLite / sqflite | Almacenamiento local |
| SharedPreferences | Preferencias |
| Permission Handler | Permisos |
| Home Widget | Widgets |
| Device Preview | Pruebas de interfaz |
| Marquee | Texto desplazable |
| Image Picker | Selección de imágenes |

---

# 🎵 Biblioteca musical

Player está diseñado para trabajar con música almacenada localmente en el dispositivo.

Puede manejar información como:

- Título
- Artista
- Álbum
- Género
- Duración
- Ruta del archivo
- Artwork
- Metadatos disponibles

Para esto se utilizan principalmente:

```text
on_audio_query
audiotags
```

---

# 🖼️ Artwork

Las carátulas forman parte de la experiencia del reproductor.

La estructura conceptual es:

```text
┌──────────────────────────┐
│                          │
│       CARÁTULA           │
│                          │
└──────────────────────────┘
          │
          ├── Artista
          ├── Álbum
          └── Canción
```

Las imágenes pueden provenir de los metadatos del archivo o de otras fuentes disponibles dentro de la aplicación.

---

# 🔄 Reproducción en segundo plano

El proyecto utiliza `audio_service` para integrar la reproducción con Android y los controles multimedia del sistema.

La arquitectura está preparada para:

- Reproducción con pantalla apagada.
- Reproducción en segundo plano.
- Controles desde la notificación.
- Controles multimedia del sistema.
- Controles externos.
- Sincronización del estado de reproducción.

---

# 🎚️ Filosofía de procesamiento

La regla principal del motor de audio es:

> **No degradar la señal sin una razón técnica.**

### Ruta deseada

```text
FUENTE
  ↓
DECODIFICACIÓN
  ↓
PCM APROPIADO
  ↓
DSP EN FLOAT
  ↓
SALIDA
```

### Ruta que se quiere evitar

```text
FUENTE
  ↓
FORZAR 16-bit / 44.1 kHz
  ↓
DSP
  ↓
SALIDA
```

La segunda ruta puede descartar información innecesariamente en archivos de alta resolución.

---

# 🚀 Hoja de ruta

## 🔊 Motor de audio

- [ ] Integración completa de FFmpeg.
- [ ] Reproducción WMA mediante FFmpeg.
- [ ] Soporte para formatos adicionales.
- [ ] Detección automática de sample rate.
- [ ] Detección de bit depth.
- [ ] Administración avanzada del formato PCM.
- [ ] DSP interno en Float32.
- [ ] Administración del sample rate de salida.
- [ ] Evitar resampling innecesario.
- [ ] Protección contra clipping.
- [ ] Administración de headroom.
- [ ] Detección de capacidades del dispositivo.

## 🎛️ Epicenter

- [x] Epicenter integrado al proyecto.
- [ ] Mejorar el algoritmo de restauración de bajos.
- [ ] Control de intensidad.
- [ ] Mejor manejo de transitorios.
- [ ] Protección contra clipping.
- [ ] Presets.
- [ ] Optimización DSP.
- [ ] Cambios de parámetros en tiempo real.

## 🎵 Reproductor

- [ ] Playlists avanzadas.
- [ ] Favoritos.
- [ ] Reproducciones recientes.
- [ ] Historial.
- [ ] Administración de cola.
- [ ] Gapless playback.
- [ ] Crossfade.
- [ ] ReplayGain.
- [ ] Temporizador.
- [ ] Ecualizador avanzado.
- [ ] Más filtros para la biblioteca.

## 🎧 Hi-Res / salida

- [ ] Ruta AudioTrack optimizada.
- [ ] Uso de AAudio cuando corresponda.
- [ ] Detección de capacidades de salida.
- [ ] Selección de salida Hi-Res.
- [ ] Soporte para DAC USB.
- [ ] Salida USB exclusiva.
- [ ] Selección de sample rate.
- [ ] Controles de buffer.
- [ ] Información detallada del dispositivo de salida.

---

# 🧪 Pruebas de audio

Para probar correctamente el motor se recomienda utilizar archivos con características conocidas.

Ejemplo:

```text
test/
├── 16bit_44.1kHz.wav
├── 24bit_44.1kHz.wav
├── 24bit_48kHz.wav
├── 24bit_96kHz.wav
├── 24bit_192kHz.wav
├── FLAC_16_44.1.flac
├── FLAC_24_96.flac
├── MP3_320.mp3
└── WMA_test.wma
```

Para cada archivo conviene verificar:

1. Que el decoder funcione.
2. Que los metadatos sean correctos.
3. Que se detecte correctamente el sample rate.
4. Que se detecte correctamente el número de canales.
5. Que se conserve el bit depth cuando la ruta lo permita.
6. Que el DSP no produzca clipping.
7. Que Epicenter funcione correctamente.
8. Que la frecuencia de salida corresponda a la ruta seleccionada.
9. Que no exista resampling inesperado.
10. Que no aparezcan clics o pops al cambiar de canción.

---

# 🔬 Prueba del DSP

Flujo recomendado:

```text
1. DSP APAGADO
       │
       ▼
Comprobar reproducción limpia
       │
       ▼
2. EPICENTER ENCENDIDO
       │
       ▼
Comprobar procesamiento de graves
       │
       ▼
3. Aumentar Epicenter
       │
       ▼
Comprobar headroom / clipping
       │
       ▼
4. Cambiar sample rate
       │
       ▼
Comprobar estabilidad
```

Se debe prestar especial atención a las frecuencias graves, ya que la restauración de bajos puede aumentar considerablemente los picos de la señal.

---

# 🛡️ Clipping y headroom

Un procesamiento fuerte de graves puede aumentar bastante el nivel máximo de la señal.

Por eso la arquitectura DSP futura debería manejar una cadena similar a:

```text
PCM
 │
 ▼
Preamp / Headroom
 │
 ▼
Epicenter
 │
 ▼
EQ
 │
 ▼
Limitador / Protección
 │
 ▼
Salida
```

Esto permite que el Epicenter sea potente sin provocar clipping digital innecesario.

---

# 🧠 ¿Por qué un `just_audio` personalizado?

El proyecto utiliza:

```yaml
just_audio:
  path: plugins/just_audio_epicenter
```

en lugar de depender únicamente de un paquete externo.

Esto permite trabajar directamente en funciones relacionadas con:

- DSP.
- Epicenter.
- Motor de reproducción.
- Salida de audio.
- Integración específica de Android.
- Futuros decodificadores.
- Comportamiento de bajo nivel.

El plugin forma parte del mismo repositorio para mantener el código del reproductor y el motor de audio sincronizados.

---

# 🛠️ Instalación para desarrollo

## Requisitos

Necesitas:

- Flutter SDK
- Dart SDK
- Android Studio
- Android SDK
- Build Tools de Android
- JDK compatible con la versión de Flutter/Gradle utilizada
- Dispositivo Android físico o emulador

Comprueba el entorno:

```bash
flutter doctor
```

---

# 📥 Clonar el proyecto

```bash
git clone https://github.com/jgl-homer/player.git
cd player
```

Instalar dependencias:

```bash
flutter pub get
```

---

# ▶️ Ejecutar

Con un dispositivo Android conectado:

```bash
flutter run
```

---

# 📦 Compilar APK

### Debug

```bash
flutter build apk --debug
```

### Release

```bash
flutter build apk --release
```

---

# 🧹 Comandos útiles

Limpiar archivos de compilación:

```bash
flutter clean
```

Instalar dependencias:

```bash
flutter pub get
```

Analizar el proyecto:

```bash
flutter analyze
```

Ejecutar pruebas:

```bash
flutter test
```

---

# 🐛 Reportar errores

Al abrir un Issue, proporciona la mayor cantidad de información posible.

### Dispositivo

```text
Marca:
Modelo:
Versión de Android:
```

### Audio

```text
Formato:
Sample rate:
Bit depth:
Canales:
```

### Salida

```text
Altavoz / Bluetooth / USB DAC / 3.5 mm / Otra:
```

### Problema

Indica:

- Qué esperabas que ocurriera.
- Qué ocurrió realmente.
- Si Epicenter estaba activado.
- Si ocurre con otros archivos.
- Si cambia el comportamiento al utilizar otra salida de audio.

---

# 🤝 Contribuciones

Las contribuciones, ideas y reportes de errores son bienvenidos.

Antes de realizar cambios importantes en el motor de audio:

1. Explica el cambio.
2. Prueba varios formatos.
3. Prueba con Epicenter apagado.
4. Prueba con Epicenter encendido.
5. Comprueba clipping.
6. Comprueba sample rate.
7. Comprueba reproducción en segundo plano.
8. Prueba en hardware físico cuando sea posible.

Para cambios en el DSP, es recomendable incluir el comportamiento antes/después y las características del archivo utilizado para las pruebas.

---

# 📄 Licencia

Actualmente el proyecto no tiene una licencia declarada.

Hasta que se agregue una licencia al repositorio, el código debe considerarse **todos los derechos reservados** y no debe asumirse que puede redistribuirse o reutilizarse libremente.

---

# 👨‍💻 Autor

**jgl-homer**

GitHub:

https://github.com/jgl-homer/player

---

# 🎯 Metas principales

Player se está desarrollando alrededor de cuatro objetivos:

```text
┌─────────────────────────────────────┐
│              PLAYER                 │
├─────────────────────────────────────┤
│                                     │
│  🎧 CALIDAD DE AUDIO                │
│     Conservar la fuente cuando      │
│     la plataforma lo permita.       │
│                                     │
│  🔊 EPICENTER                       │
│     Restauración y procesamiento    │
│     potente de graves.              │
│                                     │
│  🧠 DSP                             │
│     Procesamiento de audio          │
│     en tiempo real.                 │
│                                     │
│  ⚡ RENDIMIENTO                     │
│     Baja latencia y reproducción    │
│     estable en Android.             │
│                                     │
└─────────────────────────────────────┘
```

---

# 🎶 Cadena de audio objetivo

```text
                         PLAYER
                           │
                           ▼
                  ┌─────────────────┐
                  │  ARCHIVO AUDIO   │
                  └────────┬────────┘
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
      Decoder nativo                 FFmpeg
             │                           │
             └─────────────┬─────────────┘
                           │
                           ▼
                    ┌────────────┐
                    │    PCM     │
                    └─────┬──────┘
                          │
                          ▼
                 ┌────────────────┐
                 │   DSP EN FLOAT │
                 │                │
                 │ Epicenter      │
                 │ Restaurador    │
                 │ de bajos       │
                 │ EQ             │
                 │ Ganancia       │
                 │ Limitador      │
                 └───────┬────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │ SALIDA AUDIO  │
                  └──────┬───────┘
                         │
             ┌───────────┼───────────┐
             │           │           │
             ▼           ▼           ▼
          Altavoz     Audífonos    DAC USB
             │           │           │
             └───────────┴───────────┘
                         │
                         ▼
                        🔊
```

---

# ⭐ Objetivo final

Player busca convertirse en un reproductor Android enfocado en:

**música local + alta calidad + DSP personalizado + Epicenter.**

La meta no es simplemente soportar más extensiones.

La meta es construir una cadena de audio donde:

```text
          CALIDAD
             +
          CONTROL
             +
            DSP
             +
         EPICENTER
             ↓
      REPRODUCTOR COMPLETO
```

---

### Hecho con Flutter ❤️

**Diseñado para audio.  
Construido para experimentar.  
Enfocado en los bajos.**
