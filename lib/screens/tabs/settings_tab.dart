import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/audio_provider.dart';
import '../../services/state_persistence.dart';
import '../../services/lyrics_service.dart';

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
        padding: const EdgeInsets.all(0),
        children: [
          // ─── Sección: Pestañas ─────────────────────────────────────────
          _SectionHeader(label: 'Pestañas visibles'),
          _TabsSelector(audioProvider: audioProvider),

          const SizedBox(height: 8),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),

          // ─── Sección: Reproducción ─────────────────────────────────────
          _SectionHeader(label: 'Reproducción'),
          SwitchListTile(
            title: const Text('Modo automático',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Activa el modo automático (cambia orientación)',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: audioProvider.isAutoModeEnabled,
            onChanged: (v) => audioProvider.setAutoMode(v),
            activeThumbColor: Colors.tealAccent,
            activeTrackColor: Colors.teal.withAlpha(100),
          ),
          SwitchListTile(
            title: const Text('Epicentro habilitado',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Aplica el efecto epicentro al audio',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: audioProvider.isEpicenterEnabled,
            onChanged: (v) => audioProvider.toggleEpicenter(),
            activeThumbColor: Colors.tealAccent,
            activeTrackColor: Colors.teal.withAlpha(100),
          ),
          if (audioProvider.isEpicenterEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Intensidad de Epicentro',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text(
                      'Define la cantidad y fuerza de bajo sintetizado que se añadirá a la mezcla.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Row(
                    children: [
                      const Icon(Icons.graphic_eq,
                          color: Colors.grey, size: 20),
                      Expanded(
                        child: Slider(
                          value: audioProvider.epicenterIntensity,
                          min: 0,
                          max: 100,
                          activeColor: Colors.tealAccent,
                          inactiveColor: Colors.white24,
                          onChanged: (v) => audioProvider
                              .updateEpicenterSettings(intensity: v),
                        ),
                      ),
                      Text('${audioProvider.epicenterIntensity.toInt()}%',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Protección anti-clip',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                audioProvider.epicenterPeakProtectionEnabled
                    ? 'Activa el límite transparente actual del Epicentro'
                    : 'Deja la salida como antes, sin el límite nuevo',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              value: audioProvider.epicenterPeakProtectionEnabled,
              onChanged: (v) => audioProvider.updateEpicenterSettings(
                peakProtectionEnabled: v,
              ),
              activeThumbColor: Colors.tealAccent,
              activeTrackColor: Colors.teal.withAlpha(100),
            ),
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text('Ajustes Avanzados de Epicentro',
                    style: TextStyle(color: Colors.tealAccent, fontSize: 14)),
                childrenPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sweep Freq',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text(
                          'Ajusta la frecuencia central donde se detectará y restaurará el bajo profundo.',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: audioProvider.epicenterSweepFreq
                                  .clamp(27.0, 63.0),
                              min: 27,
                              max: 63,
                              activeColor: Colors.tealAccent,
                              inactiveColor: Colors.white24,
                              onChanged: (v) => audioProvider
                                  .updateEpicenterSettings(sweepFreq: v),
                            ),
                          ),
                          Text('${audioProvider.epicenterSweepFreq.toInt()} Hz',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Width',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text(
                          'Controla el rango de frecuencias adyacentes que afectará el efecto de bajo.',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: audioProvider.epicenterWidth
                                  .clamp(0.0, 100.0),
                              min: 0,
                              max: 100,
                              activeColor: Colors.tealAccent,
                              inactiveColor: Colors.white24,
                              onChanged: (v) => audioProvider
                                  .updateEpicenterSettings(width: v),
                            ),
                          ),
                          Text('${audioProvider.epicenterWidth.toInt()}%',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),

          // ─── Sección: Biblioteca ───────────────────────────────────────
          _SectionHeader(label: 'Biblioteca'),
          ListTile(
            leading:
                const Icon(Icons.lyrics_outlined, color: Colors.tealAccent),
            title: const Text('Fuente de letras',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              audioProvider.lyricsSource == LyricsSource.embedded
                  ? 'Leer letras incrustadas en cada archivo'
                  : 'Buscar letras en internet mediante LRCLIB',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            trailing: DropdownButton<LyricsSource>(
              value: audioProvider.lyricsSource,
              dropdownColor: const Color(0xFF252525),
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: Colors.tealAccent),
              items: const [
                DropdownMenuItem(
                  value: LyricsSource.embedded,
                  child: Text('Incrustadas'),
                ),
                DropdownMenuItem(
                  value: LyricsSource.internet,
                  child: Text('Internet'),
                ),
              ],
              onChanged: (value) {
                if (value != null) audioProvider.setLyricsSource(value);
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Mostrar letras',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Muestra u oculta el recuadro de letras en el reproductor',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: audioProvider.lyricsVisible,
            onChanged: audioProvider.setLyricsVisible,
            activeThumbColor: Colors.tealAccent,
            activeTrackColor: Colors.teal,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Canciones recientes',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                const Text(
                    'Ordena por fecha de modificación y define cuántas mostrar.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                        onChanged: (value) => audioProvider.setRecentSongsLimit(
                          (value / 100).round() * 100,
                        ),
                      ),
                    ),
                    Text(
                      audioProvider.recentSongsLimit >= 1000
                          ? '${(audioProvider.recentSongsLimit / 1000).toStringAsFixed(audioProvider.recentSongsLimit % 1000 == 0 ? 0 : 1)}k'
                          : '${audioProvider.recentSongsLimit}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () async {
                final result = await audioProvider.refreshLibrary();
                if (!context.mounted) return;
                final msg = (result == null || !result.hasChanges)
                    ? 'Biblioteca ya actualizada.'
                    : 'Biblioteca actualizada con cambios.';
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(msg), behavior: SnackBarBehavior.floating));
              },
              icon: const Icon(Icons.refresh, color: Colors.tealAccent),
              label: const Text('Refrescar biblioteca',
                  style: TextStyle(color: Colors.tealAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.teal),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF222222),
                    title: const Text('Restablecer epicentro',
                        style: TextStyle(color: Colors.white)),
                    content: const Text(
                        '¿Deseas restablecer los parámetros del epicentro?',
                        style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Restablecer',
                              style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                );
                if (ok == true) {
                  await audioProvider.resetEpicenterSettingsToDefault();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Parámetros restablecidos'),
                      behavior: SnackBarBehavior.floating));
                }
              },
              icon: const Icon(Icons.restore, color: Colors.orangeAccent),
              label: const Text('Restablecer epicentro',
                  style: TextStyle(color: Colors.orangeAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Header de sección
// ────────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.4,
        ),
      ),
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
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
          ),
          itemCount: _allTabs.length,
          itemBuilder: (context, index) {
            final id = _allTabs[index];
            final meta = _tabMeta[id]!;
            final enabled = _isEnabled(id);
            final isLast = enabled && _enabled.length == 1;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color:
                    enabled ? const Color(0xFF1E3A3A) : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: enabled
                      ? Colors.tealAccent.withAlpha(100)
                      : Colors.white10,
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isLast ? null : () => _toggle(id),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          meta.icon,
                          color: enabled ? Colors.tealAccent : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            meta.label,
                            style: TextStyle(
                              color: enabled ? Colors.white : Colors.grey,
                              fontWeight:
                                  enabled ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Transform.scale(
                          scale: 0.65,
                          child: Switch(
                            value: enabled,
                            onChanged: isLast ? null : (_) => _toggle(id),
                            activeThumbColor: Colors.tealAccent,
                            activeTrackColor: Colors.teal.withAlpha(100),
                            inactiveTrackColor: Colors.white12,
                            inactiveThumbColor: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
