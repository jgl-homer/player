import 'package:flutter/material.dart';

import '../models/autodj_settings.dart';
import '../services/autodj_controller.dart';

class AutoDjSettingsSection extends StatelessWidget {
  final AutoDjController controller;
  final List<String> libraryPaths;

  const AutoDjSettingsSection({
    super.key,
    required this.controller,
    required this.libraryPaths,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final settings = controller.settings;
        final progress = controller.analysisProgress;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'AUTODJ',
                style: TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            SwitchListTile(
              title:
                  const Text('AutoDJ', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _statusText(controller),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              value: settings.enabled,
              onChanged: (value) => controller.updateSettings(
                settings.copyWith(enabled: value),
              ),
              activeThumbColor: Colors.tealAccent,
              activeTrackColor: Colors.teal.withAlpha(100),
            ),
            if (settings.enabled) ...[
              SwitchListTile(
                title: const Text('Modo inteligente',
                    style: TextStyle(color: Colors.white)),
                value: settings.intelligentMode,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(
                    intelligentMode: value,
                    transitionType: value
                        ? AutoDjTransitionType.smart
                        : settings.transitionType == AutoDjTransitionType.smart
                            ? AutoDjTransitionType.smooth
                            : settings.transitionType,
                  ),
                ),
                activeThumbColor: Colors.tealAccent,
              ),
              _DropdownRow<AutoDjPlayDuration>(
                label: 'Duración por canción',
                value: settings.playDuration,
                items: AutoDjPlayDuration.values,
                text: _durationLabel,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(playDuration: value),
                ),
              ),
              _DropdownRow<AutoDjTransitionType>(
                label: 'Tipo de transición',
                value: settings.transitionType,
                items: AutoDjTransitionType.values,
                text: _transitionLabel,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(transitionType: value),
                ),
              ),
              _SliderRow(
                label: 'Duración de transición',
                value: settings.transitionSeconds,
                min: 0.5,
                max: 12,
                divisions: 23,
                suffix: '${settings.transitionSeconds.toStringAsFixed(1)} s',
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(transitionSeconds: value),
                ),
              ),
              _SliderRow(
                label: 'Intensidad de efectos',
                value: settings.effectIntensity,
                min: 0,
                max: 1,
                divisions: 20,
                suffix: '${(settings.effectIntensity * 100).round()}%',
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(effectIntensity: value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: AutoDjTransitionType.values
                      .where((type) =>
                          type != AutoDjTransitionType.smart &&
                          type != AutoDjTransitionType.random)
                      .map((type) => FilterChip(
                            label: Text(_transitionLabel(type)),
                            selected: settings.enabledEffects.contains(type),
                            onSelected: (selected) {
                              final effects = {...settings.enabledEffects};
                              selected
                                  ? effects.add(type)
                                  : effects.remove(type);
                              controller.updateSettings(
                                settings.copyWith(enabledEffects: effects),
                              );
                            },
                            selectedColor: Colors.teal.withAlpha(90),
                            checkmarkColor: Colors.tealAccent,
                          ))
                      .toList(growable: false),
                ),
              ),
              SwitchListTile(
                title: const Text('Sincronizar beats',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                    'Alinea beatgrid y downbeats cuando son confiables',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                value: settings.beatSync,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(beatSync: value),
                ),
                activeThumbColor: Colors.tealAccent,
              ),
              SwitchListTile(
                title: const Text('Ajuste moderado de tempo',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Limita el cambio a ±8%',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                value: settings.tempoAdjustment,
                onChanged: settings.beatSync
                    ? (value) => controller.updateSettings(
                          settings.copyWith(tempoAdjustment: value),
                        )
                    : null,
                activeThumbColor: Colors.tealAccent,
              ),
              SwitchListTile(
                title: const Text('Normalizar loudness',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                    'Compensa diferencias con protección de pico',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                value: settings.loudnessNormalization,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(loudnessNormalization: value),
                ),
                activeThumbColor: Colors.tealAccent,
              ),
              SwitchListTile(
                title: const Text('Efectos en cambios manuales',
                    style: TextStyle(color: Colors.white)),
                value: settings.manualTransitionEffects,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(manualTransitionEffects: value),
                ),
                activeThumbColor: Colors.tealAccent,
              ),
              SwitchListTile(
                title: const Text('Efectos visuales',
                    style: TextStyle(color: Colors.white)),
                value: settings.visualEffects,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(visualEffects: value),
                ),
                activeThumbColor: Colors.tealAccent,
              ),
              SwitchListTile(
                title: const Text('Análisis en segundo plano',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                    'Sólo cuando lo inicies; no analiza miles de canciones al instalar',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                value: settings.backgroundAnalysis,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(backgroundAnalysis: value),
                ),
                activeThumbColor: Colors.tealAccent,
              ),
              if (progress != null && progress.total > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    color: Colors.tealAccent,
                    backgroundColor: Colors.white12,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: controller.analyzer.isRunning
                          ? controller.cancelAnalysis
                          : () => _analyze(context),
                      icon: Icon(controller.analyzer.isRunning
                          ? Icons.stop
                          : Icons.analytics_outlined),
                      label: Text(controller.analyzer.isRunning
                          ? 'Cancelar análisis'
                          : 'Analizar biblioteca'),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.analysisCount == 0
                          ? null
                          : () => _confirmClear(context),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(
                          'Eliminar análisis (${controller.analysisCount})'),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.preparedPlan == null
                          ? null
                          : controller.mixNow,
                      icon: const Icon(Icons.multitrack_audio),
                      label: const Text('Mezclar ahora'),
                    ),
                  ],
                ),
              ),
            ],
            _GainSettings(controller: controller, settings: settings),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  controller.error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            const Divider(color: Colors.white10, height: 1),
          ],
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar análisis de AutoDJ'),
        content: const Text(
          'Se borrarán BPM, beatgrids y cues guardados. La biblioteca y las letras no se modificarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.clearAnalysis();
  }

  Future<void> _analyze(BuildContext context) async {
    try {
      final results = await controller.analyzeLibrary(libraryPaths);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${results.length} canciones analizadas')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se completó el análisis: $error')),
      );
    }
  }
}

class _GainSettings extends StatelessWidget {
  final AutoDjController controller;
  final AutoDjSettings settings;

  const _GainSettings({required this.controller, required this.settings});

  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: const Text('Ganancia de audio',
            style: TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: const Text('Independiente de AutoDJ',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        iconColor: Colors.tealAccent,
        collapsedIconColor: Colors.grey,
        children: [
          SwitchListTile(
            title: const Text('Activar ganancia',
                style: TextStyle(color: Colors.white)),
            value: settings.audioGainEnabled,
            onChanged: (value) => controller.updateSettings(
              settings.copyWith(audioGainEnabled: value),
            ),
            activeThumbColor: Colors.tealAccent,
          ),
          _SliderRow(
            label: 'Ganancia',
            value: settings.audioGainDb,
            min: -12,
            max: 12,
            divisions: 48,
            suffix: '${settings.audioGainDb.toStringAsFixed(1)} dB',
            onChanged: settings.audioGainEnabled
                ? (value) => controller.updateSettings(
                      settings.copyWith(audioGainDb: value),
                    )
                : null,
          ),
          SwitchListTile(
            title: const Text('Limitador seguro',
                style: TextStyle(color: Colors.white)),
            value: settings.limiterEnabled,
            onChanged: settings.audioGainEnabled
                ? (value) => controller.updateSettings(
                      settings.copyWith(limiterEnabled: value),
                    )
                : null,
            activeThumbColor: Colors.tealAccent,
          ),
        ],
      );
}

class _DropdownRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) text;
  final ValueChanged<T> onChanged;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.text,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(label, style: const TextStyle(color: Colors.white)),
        trailing: DropdownButton<T>(
          value: value,
          dropdownColor: const Color(0xFF252525),
          style: const TextStyle(color: Colors.tealAccent),
          underline: const SizedBox.shrink(),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(text(item)),
                  ))
              .toList(growable: false),
          onChanged: (item) {
            if (item != null) onChanged(item);
          },
        ),
      );
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double>? onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: onChanged,
                    activeColor: Colors.tealAccent,
                  ),
                ),
                SizedBox(
                  width: 62,
                  child: Text(suffix,
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      );
}

String _statusText(AutoDjController controller) => switch (controller.status) {
      AutoDjStatus.disabled =>
        'Desactivado; la reproducción funciona como antes',
      AutoDjStatus.idle => 'Esperando la siguiente canción',
      AutoDjStatus.analyzing => 'Analizando audio localmente…',
      AutoDjStatus.ready => 'Siguiente mezcla preparada',
      AutoDjStatus.mixing => 'Mezclando dos decks…',
      AutoDjStatus.error => 'Revisa el diagnóstico mostrado abajo',
    };

String _durationLabel(AutoDjPlayDuration value) => switch (value) {
      AutoDjPlayDuration.full => 'Completa',
      AutoDjPlayDuration.seconds60 => '60 s',
      AutoDjPlayDuration.seconds90 => '90 s',
      AutoDjPlayDuration.seconds120 => '120 s',
      AutoDjPlayDuration.seconds150 => '150 s',
      AutoDjPlayDuration.seconds180 => '180 s',
      AutoDjPlayDuration.automatic => 'Automática',
    };

String _transitionLabel(AutoDjTransitionType value) => switch (value) {
      AutoDjTransitionType.smooth => 'Suave',
      AutoDjTransitionType.beatSync => 'Beat sync',
      AutoDjTransitionType.bassSwap => 'Bass swap',
      AutoDjTransitionType.echoOut => 'Echo out',
      AutoDjTransitionType.filterSweep => 'Filter sweep',
      AutoDjTransitionType.quickCut => 'Corte rápido',
      AutoDjTransitionType.smart => 'Inteligente',
      AutoDjTransitionType.random => 'Aleatoria',
    };
