import 'package:flutter/material.dart';
import '../services/state_persistence.dart';
import '../theme/app_theme.dart';

class EpicenterEngineSelector extends StatefulWidget {
  final EpicenterEngineMode value;
  final Future<void> Function(EpicenterEngineMode) onChanged;
  final bool showDescriptions;

  const EpicenterEngineSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.showDescriptions = false,
  });

  @override
  State<EpicenterEngineSelector> createState() =>
      _EpicenterEngineSelectorState();
}

class _EpicenterEngineSelectorState extends State<EpicenterEngineSelector> {
  bool _changing = false;

  Future<void> _select(Set<EpicenterEngineMode> selection) async {
    setState(() => _changing = true);
    try {
      await widget.onChanged(selection.single);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cambiar el motor')),
        );
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleValue = widget.value == EpicenterEngineMode.legacy
        ? EpicenterEngineMode.legacy
        : EpicenterEngineMode.hybrid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Motor de síntesis', style: TextStyle(color: Colors.white)),
        const SizedBox(height: 8),
        SegmentedButton<EpicenterEngineMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            foregroundColor: Colors.white70,
            selectedForegroundColor: Colors.black,
            selectedBackgroundColor: AppTheme.primaryColor,
          ),
          segments: const [
            ButtonSegment(
              value: EpicenterEngineMode.hybrid,
              label: Text('Sintetizador 2'),
            ),
            ButtonSegment(
              value: EpicenterEngineMode.legacy,
              label: Text('Sintetizador 1'),
            ),
          ],
          selected: {visibleValue},
          onSelectionChanged: _changing ? null : _select,
        ),
        if (widget.showDescriptions) ...[
          const SizedBox(height: 12),
          const _EngineDescription(
            title: 'Sintetizador 2',
            description:
                'Síntesis más precisa, estable y controlada para restaurar el bajo.',
          ),
          const SizedBox(height: 8),
          const _EngineDescription(
            title: 'Sintetizador 1',
            description:
                'Bajo más cremoso con una fórmula matemática un poco menos precisa.',
          ),
        ],
      ],
    );
  }
}

class _EngineDescription extends StatelessWidget {
  final String title;
  final String description;

  const _EngineDescription({
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 3),
          child: Icon(Icons.circle, size: 6, color: AppTheme.primaryColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(color: Colors.white60, fontSize: 12),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
