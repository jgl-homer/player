import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../providers/audio_provider.dart';

class ConcertHallModal extends StatelessWidget {
  const ConcertHallModal({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final isEnabled = audioProvider.isReverbEnabled;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: Color(0xFF080604), // --dark
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildHeader(context, audioProvider),
          Expanded(
            child: Opacity(
              opacity: isEnabled ? 1.0 : 0.4,
              child: AbsorbPointer(
                absorbing: !isEnabled,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      _buildStatusBar(audioProvider),
                      const SizedBox(height: 15),
                      _buildPanel(
                        label: "PRESETS DE SALA",
                        child: _buildPresetsGrid(audioProvider),
                      ),
                      const SizedBox(height: 15),
                      _buildPanel(
                        label: "PARÁMETROS DE REVERB",
                        child: _buildReverbKnobs(audioProvider),
                      ),
                      const SizedBox(height: 15),
                      _buildPanel(
                        label: "MEZCLA WET / DRY",
                        child: _buildFaders(audioProvider),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AudioProvider provider) {
    final isEnabled = provider.isReverbEnabled;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1A1005).withOpacity(0.8),
            Colors.transparent,
          ],
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF5A4820), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 48), // Spacer for balance
          Column(
            children: [
              const Text(
                "3D CONCERT HALL",
                style: TextStyle(
                  color: Color(0xFFC9A84C), // --gold
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "NATIVE 3D DSP PROCESSOR",
                style: TextStyle(
                  color: const Color(0xFF7A6030), // --gold-mid
                  fontSize: 9,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          _PowerToggle(
            isEnabled: isEnabled,
            onTap: provider.toggleBypass,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(AudioProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF110E07), // --mid
        border: Border.all(color: const Color(0xFF5A4820)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              provider.currentSong?.title.toUpperCase() ?? "SIN AUDIO",
              style: const TextStyle(
                  color: Color(0xFF7A6030), fontSize: 9, letterSpacing: 1.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            provider.isReverbEnabled ? "ON" : "OFF",
            style: TextStyle(
              color: provider.isReverbEnabled
                  ? const Color(0xFFC9A84C)
                  : const Color(0xFF8B1A1A),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0B06), // --panel
        border: Border.all(color: const Color(0xFF5A4820)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7A6030),
              fontSize: 8,
              letterSpacing: 2.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildPresetsGrid(AudioProvider provider) {
    final presets = {
      AudioPreset.concertHall: "3D HALL",
      AudioPreset.chamber: "CHAMBER",
      AudioPreset.cathedral: "CATHEDRAL",
      AudioPreset.studio: "STUDIO",
      AudioPreset.plate: "PLATE",
    };

    return LayoutBuilder(builder: (context, constraints) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: presets.entries.map((entry) {
          final isActive = provider.currentPreset == entry.key;
          return GestureDetector(
            onTap: () => provider.setAudioPreset(entry.key),
            child: Container(
              width: (constraints.maxWidth - 24) / 5,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFC9A84C).withOpacity(0.1)
                    : Colors.transparent,
                border: Border.all(
                  color: isActive
                      ? const Color(0xFFC9A84C)
                      : const Color(0xFF5A4820),
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFFC9A84C)
                        : const Color(0xFF7A6030),
                    fontSize: 7.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
    });
  }

  Widget _buildReverbKnobs(AudioProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        GoldKnob(
          label: "DECAY",
          value: provider.reverbDecay,
          min: 0.2,
          max: 8.0,
          fmt: (v) => "${v.toStringAsFixed(1)}s",
          onChanged: (v) => provider.updateReverbParam('decay', v),
        ),
        GoldKnob(
          label: "PRE-DLY",
          value: provider.reverbPreDelay,
          min: 0.0,
          max: 0.1,
          fmt: (v) => "${(v * 1000).toInt()}ms",
          onChanged: (v) => provider.updateReverbParam('preDelay', v),
        ),
        GoldKnob(
          label: "ROOM",
          value: provider.reverbRoomSize,
          min: 0.1,
          max: 0.99,
          fmt: (v) => "${(v * 100).toInt()}%",
          onChanged: (v) => provider.updateReverbParam('roomSize', v),
        ),
        GoldKnob(
          label: "DAMPING",
          value: provider.reverbDamping,
          min: 0.0,
          max: 1.0,
          fmt: (v) => "${(v * 100).toInt()}%",
          onChanged: (v) => provider.updateReverbParam('damping', v),
        ),
      ],
    );
  }

  Widget _buildFaders(AudioProvider provider) {
    return Column(
      children: [
        _buildFaderGroup(
          label: "WET (EFECTO)",
          value: provider.reverbWet,
          onChanged: (v) => provider.updateReverbParam('wet', v),
        ),
        const SizedBox(height: 12),
        _buildFaderGroup(
          label: "DRY (ORIGINAL)",
          value: provider.reverbDry,
          onChanged: (v) => provider.updateReverbParam('dry', v),
        ),
      ],
    );
  }

  Widget _buildFaderGroup(
      {required String label,
      required double value,
      required ValueChanged<double> onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF7A6030), fontSize: 9, letterSpacing: 1.5)),
            Text("${value.toInt()}%",
                style: const TextStyle(
                    color: Color(0xFFC9A84C),
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            activeTrackColor: const Color(0xFFC9A84C),
            inactiveTrackColor: const Color(0xFF110E07),
            thumbColor: const Color(0xFFC9A84C),
            thumbShape: const RectSliderThumbShape(),
            overlayColor: const Color(0xFFC9A84C).withOpacity(0.1),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: 100,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _PowerToggle extends StatelessWidget {
  final bool isEnabled;
  final VoidCallback onTap;

  const _PowerToggle({required this.isEnabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isEnabled
              ? const Color(0xFFC9A84C).withOpacity(0.2)
              : const Color(0xFF1A0808),
          border: Border.all(
            color:
                isEnabled ? const Color(0xFFC9A84C) : const Color(0xFF5A2020),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color:
                  isEnabled ? const Color(0xFFC9A84C) : const Color(0xFF5A2020),
              shape: BoxShape.circle,
              boxShadow: [
                if (isEnabled)
                  BoxShadow(
                    color: const Color(0xFFC9A84C).withOpacity(0.5),
                    blurRadius: 10,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GoldKnob extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) fmt;
  final ValueChanged<double> onChanged;

  const GoldKnob({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.fmt,
    required this.onChanged,
  });

  @override
  State<GoldKnob> createState() => _GoldKnobState();
}

class _GoldKnobState extends State<GoldKnob> {
  double _startValue = 0;
  double _startY = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(widget.label,
            style: const TextStyle(
                color: Color(0xFF7A6030), fontSize: 8, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        GestureDetector(
          onVerticalDragStart: (details) {
            _startY = details.globalPosition.dy;
            _startValue = widget.value;
          },
          onVerticalDragUpdate: (details) {
            final delta = (_startY - details.globalPosition.dy) / 100;
            final newValue = (_startValue + delta * (widget.max - widget.min))
                .clamp(widget.min, widget.max);
            widget.onChanged(newValue);
          },
          child: CustomPaint(
            size: const Size(50, 50),
            painter: KnobPainter(
              value: (widget.value - widget.min) / (widget.max - widget.min),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(widget.fmt(widget.value),
            style: const TextStyle(color: Color(0xFFC9A84C), fontSize: 9)),
      ],
    );
  }
}

class KnobPainter extends CustomPainter {
  final double value; // 0 to 1

  KnobPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final gold = const Color(0xFFC9A84C);
    final goldDim = const Color(0xFF1A1208);
    final dark = const Color(0xFF140F08);

    // Background Ring
    final ringPaint = Paint()
      ..color = goldDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius - 4, ringPaint);

    // Value Arc
    final arcPaint = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const startAngle = 135.0 * math.pi / 180.0;
    final sweepAngle = (value * 270.0) * math.pi / 180.0;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );

    // Knob Body
    final bodyPaint = Paint()..color = dark;
    canvas.drawCircle(center, radius - 10, bodyPaint);
    final borderPaint = Paint()
      ..color = const Color(0xFF3A2A0A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius - 10, borderPaint);

    // Pointer Dot
    final angle = startAngle + sweepAngle;
    final dotPos = Offset(
      center.dx + (radius - 12) * math.cos(angle),
      center.dy + (radius - 12) * math.sin(angle),
    );
    canvas.drawCircle(dotPos, 2.5, Paint()..color = gold);
  }

  @override
  bool shouldRepaint(KnobPainter oldDelegate) => oldDelegate.value != value;
}

class RectSliderThumbShape extends SliderComponentShape {
  const RectSliderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(12, 24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final paint = Paint()..color = sliderTheme.thumbColor ?? Colors.blue;
    final rect = Rect.fromCenter(center: center, width: 14, height: 24);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);

    // Add shadow
    canvas.drawShadow(Path()..addRect(rect), Colors.black, 4, true);
  }
}
