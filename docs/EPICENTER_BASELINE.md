# Baseline de Epicenter DSP

**Fecha de referencia:** 2026-10-02  
**Repositorio:** `jgl-homer/player`  
**Propósito:** dejar registrada la referencia funcional y técnica del procesamiento Epicenter sin cambiar su implementación.

## Alcance

Esta baseline describe el procesamiento de audio Epicenter tal como existe en la fecha indicada. Es un documento de referencia para comparar cambios posteriores; no define una nueva arquitectura ni introduce modificaciones de código, DSP, audio, UI o comportamiento.

El procesador recibe PCM lineal de 16 bits, conserva la frecuencia de muestreo y el número de canales, y entrega PCM lineal de 16 bits con el mismo formato. El procesamiento se realiza por bloques intercalados y mantiene estado entre bloques para filtros y envolventes.

## Controles de referencia

- **Sweep frequency:** valor predeterminado de 45 Hz; se limita al intervalo de 27–63 Hz.
- **Width:** valor predeterminado de 50; se limita al intervalo de 0–100.
- **Intensity:** valor predeterminado de 50; se limita al intervalo de 0–100.
- **Balance:** valor predeterminado de 50; se limita al intervalo de 0–100.
- **Volume:** valor predeterminado de 100; se limita al intervalo de 0–100.
- **Epicenter enabled:** desactivado por defecto. Al desactivarse, se reinicia el estado DSP y la señal se copia sin el procesamiento Epicenter.

Cuando `intensity` es prácticamente cero, la ruta activa también conserva la señal de entrada. Los formatos distintos de PCM de 16 bits no forman parte de esta baseline.

## Pipeline exacto

El orden de referencia es:

**PCM -> Headroom/protección -> Subsonic -> Low-frequency detection -> Envelope follower -> Bass extraction -> Harmonic generation -> Harmonic filtering -> Dynamic gain -> Dry/Wet mix -> Limiter/protection -> Output**

### 1. PCM

La entrada se interpreta como muestras PCM signed de 16 bits en little-endian y se normaliza a `[-1, 1]`. La señal se procesa intercalada, con ruta mono para detección/generación y rutas independientes por canal para la mezcla.

### 2. Headroom/protección

Los parámetros se normalizan y acotan antes de calcular ganancias. La intensidad usa un factor interno de headroom de 0.75. También se eliminan valores denormales próximos a cero para mantener estable el procesamiento.

### 3. Subsonic

La salida final de cada canal pasa por un filtro pasa-altos de 18 Hz para retirar componente DC y contenido subsónico residual.

### 4. Low-frequency detection

La señal mono se forma promediando los canales izquierdo y derecho. Se analizan bandas alrededor de 60, 80 y 110 Hz, además de una referencia pasa-bajos de 120 Hz. La detección pondera esas bandas para identificar actividad de baja frecuencia.

### 5. Envelope follower

Se siguen envolventes separadas para detector, señal mono, diferencia entre canales, compuerta, nivel del sintetizador y presencia vocal. Cada envolvente tiene tiempos de ataque y liberación independientes; la compuerta incluye retención temporal para evitar cortes abruptos.

### 6. Bass extraction

Por canal se separan la presencia vocal mediante pasa-altos, el programa de graves mediante pasa-bajos, el cuerpo de low-mid mediante banda pasante y una banda de reducción de low-mid. Sus niveles dependen de `balance`, `width`, `intensity` y de la protección asociada a la presencia vocal.

### 7. Harmonic generation

El detector mono genera una señal de media onda alternada mediante un estado de inversión de fase. La señal se filtra y se controla con la actividad detectada y la compuerta antes de convertirse en el subgrave sintetizado.

### 8. Harmonic filtering

La señal sintetizada usa un pasa-altos y un pasa-bajos dependientes de `sweep frequency` y `width`. Después, cada canal aplica otro pasa-bajos para limitar el contenido subgrave que se reincorpora a la mezcla.

### 9. Dynamic gain

La presencia vocal reduce dinámicamente la contribución del programa de graves y de los armónicos generados. El nivel del sintetizador se sigue con una envolvente adicional, y las ganancias de intensidad, balance y volumen se aplican antes de la mezcla final.

### 10. Dry/Wet mix

La ruta seca conserva la presencia vocal y el contenido original filtrado por canal. La ruta húmeda combina el programa de graves, el cuerpo low-mid y los armónicos generados. Ambas rutas se suman por canal y se escalan con el volumen configurado.

### 11. Limiter/protection

La suma se protege mediante saturación suave (`tanh`) y la señal sintetizada recibe protección previa también mediante saturación suave. La conversión de salida limita cada muestra al rango PCM válido de 16 bits.

### 12. Output

La señal resultante conserva frecuencia de muestreo, número de canales y tamaño de bloque. Se vuelve a cuantizar a signed PCM de 16 bits little-endian y se entrega al siguiente componente de reproducción.

## Estado y reinicio

- El estado de filtros y envolventes se conserva entre bloques para evitar discontinuidades.
- El cambio de frecuencia de barrido o anchura actualiza los coeficientes derivados sin reconstruir innecesariamente el resto del estado.
- Al hacer `flush`, `reset` o desactivar Epicenter, se reinician filtros, envolventes, contadores y estados de detección.
- Los canales mono y multicanal comparten la detección mono, mientras que la mezcla de salida mantiene estado por canal.

## Invariantes de la baseline

- No se cambia el formato PCM de entrada ni de salida.
- No se añaden etapas fuera del pipeline exacto documentado.
- No se modifica el comportamiento de la interfaz de usuario ni los valores de control.
- Esta baseline no constituye una propuesta de refactorización ni una autorización para editar la implementación.

