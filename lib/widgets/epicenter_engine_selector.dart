import 'package:flutter/material.dart';
import '../services/state_persistence.dart';

class EpicenterEngineSelector extends StatefulWidget {
  final EpicenterEngineMode value;
  final Future<void> Function(EpicenterEngineMode) onChanged;

  const EpicenterEngineSelector({
    super.key,
    required this.value,
    required this.onChanged,
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
        const Text('Motor del Epicentro',
            style: TextStyle(color: Colors.white)),
        const SizedBox(height: 8),
        SegmentedButton<EpicenterEngineMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            foregroundColor: Colors.white70,
            selectedForegroundColor: Colors.black,
            selectedBackgroundColor: Colors.tealAccent,
          ),
          segments: const [
            ButtonSegment(
              value: EpicenterEngineMode.hybrid,
              label: Text('HYBRID'),
            ),
            ButtonSegment(
              value: EpicenterEngineMode.legacy,
              label: Text('LEGACY'),
            ),
          ],
          selected: {visibleValue},
          onSelectionChanged: _changing ? null : _select,
        ),
      ],
    );
  }
}
