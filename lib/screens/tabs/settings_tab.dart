import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/audio_provider.dart';
import '../../services/state_persistence.dart';
import '../../services/lyrics_service.dart';
import '../../widgets/epicenter_engine_selector.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Configuración',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          _SettingsSection(
            storageKey: 'settings_tabs',
            icon: Icons.tune_rounded,
            title: 'Pestañas visibles',
            subtitle: '${audioProvider.enabledTabs.length} activas',
            child: _TabsSelector(audioProvider: audioProvider),
          ),
          const SizedBox(height: 10),
          _SettingsSection(
            storageKey: 'settings_bass',
            icon: Icons.graphic_eq_rounded,
            title: 'Restaurador de bajos / Sintetizador de bajos',
            subtitle: audioProvider.isEpicenterEnabled
                ? (audioProvider.epicenterEngine == EpicenterEngineMode.legacy
                    ? 'Sintetizador 1'
                    : 'Sintetizador 2')
                : 'Desactivado',
            initiallyExpanded: true,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Restaurador de bajos',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'Activa la síntesis y restauración de graves profundos.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  value: audioProvider.isEpicenterEnabled,
                  onChanged: (_) => audioProvider.toggleEpicenter(),
                  activeThumbColor: Colors.tealAccent,
                  activeTrackColor: Colors.teal,
                ),
                if (audioProvider.isEpicenterEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: EpicenterEngineSelector(
                      value: audioProvider.epicenterEngine,
                      onChanged: audioProvider.setEpicenterEngine,
                      showDescriptions: true,
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Protección un poco más estricta',
                        style: TextStyle(color: Colors.white)),
                    subtitle: const Text(
                      'Baja un poco más el umbral del limitador para evitar distorsión en los picos fuertes.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    value: audioProvider.epicenterPeakProtectionEnabled,
                    onChanged: (value) => audioProvider.updateEpicenterSettings(
                      peakProtectionEnabled: value,
                    ),
                    activeThumbColor: Colors.tealAccent,
                    activeTrackColor: Colors.teal,
                  ),
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: const Text(
                        'Ajustes avanzados',
                        style:
                            TextStyle(color: Colors.tealAccent, fontSize: 14),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      children: [
                        _BassSlider(
                          label: 'Sweep / Center',
                          description:
                              'Frecuencia central donde se detecta y restaura el bajo profundo.',
                          value: audioProvider.epicenterSweepFreq
                              .clamp(27.0, 63.0),
                          min: 27,
                          max: 63,
                          valueLabel:
                              '${audioProvider.epicenterSweepFreq.toInt()} Hz',
                          onChanged: (value) =>
                              audioProvider.updateEpicenterSettings(
                            sweepFreq: value,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _BassSlider(
                          label: 'Width',
                          description:
                              'Controla el ancho de frecuencias alrededor del centro.',
                          value: audioProvider.epicenterWidth.clamp(0.0, 100.0),
                          min: 0,
                          max: 100,
                          valueLabel:
                              '${audioProvider.epicenterWidth.toInt()}%',
                          onChanged: (value) =>
                              audioProvider.updateEpicenterSettings(
                            width: value,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _resetEpicenter(context, audioProvider),
                      icon:
                          const Icon(Icons.restore, color: Colors.orangeAccent),
                      label: const Text(
                        'Restablecer sintetizador de bajos',
                        style: TextStyle(color: Colors.orangeAccent),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _SettingsSection(
            storageKey: 'settings_tone_controls',
            icon: Icons.equalizer_rounded,
            title: 'ReplayGain y ecualizador',
            subtitle: _toneControlsSubtitle(audioProvider),
            child: _ToneControlsPanel(audioProvider: audioProvider),
          ),
          const SizedBox(height: 10),
          _SettingsSection(
            storageKey: 'settings_library',
            icon: Icons.library_music_outlined,
            title: 'Biblioteca',
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Mostrar letras',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'Muestra u oculta las letras en el reproductor.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  value: audioProvider.lyricsVisible,
                  onChanged: audioProvider.setLyricsVisible,
                  activeThumbColor: Colors.tealAccent,
                  activeTrackColor: Colors.teal,
                ),
                ListTile(
                  leading: const Icon(Icons.lyrics_outlined,
                      color: Colors.tealAccent),
                  title: const Text('Fuente de letras',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    audioProvider.lyricsSource == LyricsSource.internet
                        ? 'Predeterminado: busca letras sincronizadas en internet mediante LRCLIB.'
                        : 'Requiere letras incrustadas con marcas de tiempo sincronizadas con la canción.',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: DropdownButton<LyricsSource>(
                    value: audioProvider.lyricsSource,
                    dropdownColor: const Color(0xFF252525),
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(color: Colors.tealAccent),
                    items: const [
                      DropdownMenuItem(
                        value: LyricsSource.internet,
                        child: Text('Internet'),
                      ),
                      DropdownMenuItem(
                        value: LyricsSource.embedded,
                        child: Text('Incrustadas'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) audioProvider.setLyricsSource(value);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Canciones recientes',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      const Text(
                        'Ordena por fecha de modificación y define cuántas mostrar.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.new_releases_outlined,
                              color: Colors.grey, size: 20),
                          Expanded(
                            child: Slider(
                              value: audioProvider.recentSongsLimit.toDouble(),
                              min: 100,
                              max: 10000,
                              divisions: 99,
                              activeColor: Colors.tealAccent,
                              inactiveColor: Colors.white24,
                              onChanged: (value) =>
                                  audioProvider.setRecentSongsLimit(
                                (value / 100).round() * 100,
                              ),
                            ),
                          ),
                          Text(
                            audioProvider.recentSongsLimit >= 1000
                                ? '${(audioProvider.recentSongsLimit / 1000).toStringAsFixed(audioProvider.recentSongsLimit % 1000 == 0 ? 0 : 1)}k'
                                : '${audioProvider.recentSongsLimit}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _refreshLibrary(context, audioProvider),
                      icon: const Icon(Icons.refresh, color: Colors.tealAccent),
                      label: const Text(
                        'Refrescar biblioteca',
                        style: TextStyle(color: Colors.tealAccent),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.teal),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const _AboutAppSection(),
        ],
      ),
    );
  }

  String _toneControlsSubtitle(AudioProvider audioProvider) {
    final enabled = <String>[
      if (audioProvider.replayGainEnabled) 'ReplayGain',
      if (audioProvider.equalizerEnabled) 'EQ',
    ];
    return enabled.isEmpty ? 'Desactivado' : enabled.join(' + ');
  }

  Future<void> _refreshLibrary(
    BuildContext context,
    AudioProvider audioProvider,
  ) async {
    final result = await audioProvider.refreshLibrary();
    if (!context.mounted) return;
    final message = (result == null || !result.hasChanges)
        ? 'Biblioteca ya actualizada.'
        : 'Biblioteca actualizada con cambios.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _resetEpicenter(
    BuildContext context,
    AudioProvider audioProvider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Restablecer sintetizador de bajos',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Deseas restablecer los parámetros del sintetizador de bajos?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restablecer',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await audioProvider.resetEpicenterSettingsToDefault();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Parámetros restablecidos'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _AboutAppSection extends StatelessWidget {
  static const _mediaChannel = MethodChannel('com.jglhomer.player/media_utils');
  static const _githubProfile = 'https://github.com/jgl-homer';

  const _AboutAppSection();

  Future<void> _openGithub(BuildContext context) async {
    try {
      final opened = await _mediaChannel.invokeMethod<bool>(
            'open_url',
            {'url': _githubProfile},
          ) ??
          false;
      if (opened || !context.mounted) return;
    } catch (_) {
      if (!context.mounted) return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo abrir el perfil de GitHub.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      storageKey: 'settings_about',
      icon: Icons.info_outline_rounded,
      title: 'Acerca de la app',
      subtitle: 'Player 1.0.0',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Player',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Versión 1.0.0',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Reproductor de música local para Android, diseñado para bibliotecas grandes y escucha sin conexión. Incluye reproducción multiformato, letras sincronizadas, ReplayGain, ecualizador y restauración de bajos.',
              style:
                  TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 12),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: Colors.tealAccent, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'La biblioteca y los ajustes se procesan en el dispositivo. Internet se utiliza para letras en línea y enlaces externos.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.code_rounded, color: Colors.tealAccent),
              title: const Text(
                'jgl-homer en GitHub',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'github.com/jgl-homer',
                style: TextStyle(color: Colors.tealAccent, fontSize: 12),
              ),
              trailing: const Icon(
                Icons.open_in_new_rounded,
                color: Colors.white54,
                size: 19,
              ),
              onTap: () => _openGithub(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToneControlsPanel extends StatelessWidget {
  final AudioProvider audioProvider;

  const _ToneControlsPanel({required this.audioProvider});

  static const _bandLabels = ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];
  static const _presets = <String, List<double>>{
    'Plano': [0, 0, 0, 0, 0],
    'Bajos': [4, 2, 0, -1, 0],
    'Voz': [-1, -1, 1.5, 2, 1],
    'Agudos': [0, -1, 0, 2, 4],
  };

  @override
  Widget build(BuildContext context) {
    final selectedPreset = _matchingPreset(audioProvider.equalizerBandGains);
    return Column(
      children: [
        SwitchListTile(
          title:
              const Text('ReplayGain', style: TextStyle(color: Colors.white)),
          subtitle: Text(
            !audioProvider.replayGainEnabled
                ? 'Iguala el volumen cuando la pista contiene etiquetas ReplayGain.'
                : audioProvider.currentReplayGainAvailable
                    ? 'Etiqueta detectada y aplicada con transición suave.'
                    : 'La pista actual no contiene una etiqueta ReplayGain.',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          value: audioProvider.replayGainEnabled,
          onChanged: audioProvider.setReplayGainEnabled,
          activeThumbColor: Colors.tealAccent,
          activeTrackColor: Colors.teal,
        ),
        if (audioProvider.replayGainEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Las etiquetas ya guardadas en los archivos se leen una vez y se conservan en la biblioteca.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SegmentedButton<ReplayGainMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ReplayGainMode.track,
                      label: Text('Por pista'),
                    ),
                    ButtonSegment(
                      value: ReplayGainMode.album,
                      label: Text('Por álbum'),
                    ),
                  ],
                  selected: {audioProvider.replayGainMode},
                  onSelectionChanged: (selection) =>
                      audioProvider.setReplayGainMode(selection.single),
                ),
              ],
            ),
          ),
        const Divider(color: Colors.white12, height: 1),
        SwitchListTile(
          title: const Text('Ecualizador de 5 bandas',
              style: TextStyle(color: Colors.white)),
          subtitle: const Text(
            'Ajuste moderado de ±6 dB con headroom automático.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          value: audioProvider.equalizerEnabled,
          onChanged: audioProvider.setEqualizerEnabled,
          activeThumbColor: Colors.tealAccent,
          activeTrackColor: Colors.teal,
        ),
        if (audioProvider.equalizerEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Preset',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    const Spacer(),
                    DropdownButton<String>(
                      value: selectedPreset,
                      dropdownColor: const Color(0xFF252525),
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(color: Colors.tealAccent),
                      items: [
                        ..._presets.keys.map(
                          (name) => DropdownMenuItem(
                            value: name,
                            child: Text(name),
                          ),
                        ),
                        if (selectedPreset == 'Personalizado')
                          const DropdownMenuItem(
                            value: 'Personalizado',
                            enabled: false,
                            child: Text('Personalizado'),
                          ),
                      ],
                      onChanged: (name) {
                        final preset = _presets[name];
                        if (preset != null) {
                          audioProvider.setEqualizerPreset(preset);
                        }
                      },
                    ),
                  ],
                ),
                for (var index = 0; index < _bandLabels.length; index++)
                  _EqualizerBandSlider(
                    label: _bandLabels[index],
                    value: audioProvider.equalizerBandGains[index],
                    onChanged: (value) =>
                        audioProvider.setEqualizerBandGain(index, value),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: audioProvider.resetToneControls,
              icon: const Icon(Icons.restore, color: Colors.orangeAccent),
              label: const Text(
                'Restablecer ReplayGain y EQ',
                style: TextStyle(color: Colors.orangeAccent),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _matchingPreset(List<double> gains) {
    for (final entry in _presets.entries) {
      var matches = true;
      for (var index = 0; index < entry.value.length; index++) {
        if ((entry.value[index] - gains[index]).abs() >= 0.01) {
          matches = false;
          break;
        }
      }
      if (matches) return entry.key;
    }
    return 'Personalizado';
  }
}

class _EqualizerBandSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _EqualizerBandSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = value == 0
        ? '0 dB'
        : '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)} dB';
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(-6.0, 6.0),
            min: -6,
            max: 6,
            divisions: 24,
            activeColor: Colors.tealAccent,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 54,
          child: Text(
            formatted,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String storageKey;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool initiallyExpanded;
  final Widget child;

  const _SettingsSection({
    required this.storageKey,
    required this.icon,
    required this.title,
    this.subtitle,
    this.initiallyExpanded = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>(storageKey),
          initiallyExpanded: initiallyExpanded,
          maintainState: true,
          leading: Icon(icon, color: Colors.tealAccent, size: 22),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
          iconColor: Colors.tealAccent,
          collapsedIconColor: Colors.white60,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          children: [child],
        ),
      ),
    );
  }
}

class _BassSlider extends StatelessWidget {
  final String label;
  final String description;
  final double value;
  final double min;
  final double max;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  const _BassSlider({
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 4),
        Text(description,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                activeColor: Colors.tealAccent,
                inactiveColor: Colors.white24,
                onChanged: onChanged,
              ),
            ),
            Text(valueLabel,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Selector de pestañas: lista reordenable + toggles
// ────────────────────────────────────────────────────────────────────────────────
class _TabsSelector extends StatefulWidget {
  final AudioProvider audioProvider;
  const _TabsSelector({required this.audioProvider});

  @override
  State<_TabsSelector> createState() => _TabsSelectorState();
}

class _TabsSelectorState extends State<_TabsSelector> {
  static const _allTabs = StatePersistence.allAvailableTabs;

  static const _tabMeta = <String, _TabMeta>{
    'folders': _TabMeta('Carpetas', Icons.folder_outlined),
    'songs': _TabMeta('Canciones', Icons.music_note_outlined),
    'favorites': _TabMeta('Favoritos', Icons.favorite_border),
    'albums': _TabMeta('Álbumes', Icons.album_outlined),
    'artists': _TabMeta('Artistas', Icons.people_outline),
    'playlists': _TabMeta('Listas de reproducción', Icons.queue_music_outlined),
    'recently_added':
        _TabMeta('Añadido recientemente', Icons.new_releases_outlined),
  };

  late List<String> _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = List.from(widget.audioProvider.enabledTabs);
  }

  bool _isEnabled(String id) => _enabled.contains(id);

  void _toggle(String id) {
    setState(() {
      if (_isEnabled(id)) {
        if (_enabled.length <= 1) return; // at least 1 must remain
        _enabled.remove(id);
      } else {
        // Add in default order position
        final defaultPos = _allTabs.indexOf(id);
        int insertAt = _enabled.length;
        for (int i = 0; i < _enabled.length; i++) {
          if (_allTabs.indexOf(_enabled[i]) > defaultPos) {
            insertAt = i;
            break;
          }
        }
        _enabled.insert(insertAt, id);
      }
    });
    widget.audioProvider.setEnabledTabs(List.from(_enabled));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'Activa o desactiva las secciones que verás en la barra de pestañas.',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700 ? 2 : 1;
            const spacing = 16.0;
            final itemWidth =
                (constraints.maxWidth - 32 - spacing * (columns - 1)) / columns;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: spacing,
                runSpacing: 2,
                children: _allTabs.map((id) {
                  final meta = _tabMeta[id]!;
                  final enabled = _isEnabled(id);
                  final isLast = enabled && _enabled.length == 1;

                  return SizedBox(
                    width: itemWidth,
                    child: InkWell(
                      onTap: isLast ? null : () => _toggle(id),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Checkbox(
                              value: enabled,
                              onChanged: isLast ? null : (_) => _toggle(id),
                              activeColor: Colors.tealAccent,
                              checkColor: Colors.black,
                              side: const BorderSide(
                                color: Colors.white54,
                                width: 1.6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              meta.icon,
                              color:
                                  enabled ? Colors.tealAccent : Colors.white54,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                meta.label,
                                style: TextStyle(
                                  color:
                                      enabled ? Colors.white : Colors.white60,
                                  fontWeight: enabled
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              Text(
                '${_enabled.length} pestañas activas',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabMeta {
  final String label;
  final IconData icon;
  const _TabMeta(this.label, this.icon);
}
