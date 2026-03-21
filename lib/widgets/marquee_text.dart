import 'dart:async';
import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double velocity; // Pixels per second
  final double gap; // Space between repetitions
  final Duration pauseDuration;
  final TextAlign textAlign;
  final double? height;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.velocity = 35.0,
    this.gap = 50.0,
    this.pauseDuration = const Duration(seconds: 2),
    this.textAlign = TextAlign.start,
    this.height,
  });

  static bool isOverflowing({
    required String text,
    TextStyle? style,
    required double maxWidth,
    required TextScaler scaler,
  }) {
    if (text.isEmpty || maxWidth <= 0) {
      return false;
    }

    // 🔥 Si maxWidth es infinito, no podemos medir desbordamiento así.
    if (maxWidth == double.infinity) return false;

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout(); // Intrinsic layout

    return textPainter.width > maxWidth;
  }

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _timer;

  String? _lastText;
  TextStyle? _lastStyle;
  TextScaler? _lastTextScaler;
  double _cachedTextWidth = 0.0;
  bool _shouldScroll = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _stopAndReset();
    }
  }

  void _stopAndReset() {
    _timer?.cancel();
    _timer = null;
    _controller.stop();
    _controller.reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _calculateMetrics(double maxWidth, TextScaler scaler) {
    final bool textChanged = widget.text != _lastText ||
        widget.style != _lastStyle ||
        scaler != _lastTextScaler;

    if (textChanged) {
      _lastText = widget.text;
      _lastStyle = widget.style;
      _lastTextScaler = scaler;

      // 🔍 Medición intrínseca real sin restricciones de ancho
      final textPainter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout(); // Sin parámetros = ancho infinito para medir texto real

      _cachedTextWidth = textPainter.width;
    }

    final bool newShouldScroll = _cachedTextWidth > maxWidth;

    if (newShouldScroll != _shouldScroll) {
      _shouldScroll = newShouldScroll;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (_shouldScroll) {
            _setupAnimation();
          } else {
            _stopAndReset();
          }
        }
      });
    } else if (_shouldScroll && textChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setupAnimation();
      });
    }
  }

  void _setupAnimation() {
    _stopAndReset();
    if (!_shouldScroll) return;

    final distance = _cachedTextWidth + widget.gap;
    final durationInSeconds = distance / widget.velocity;

    _controller.duration =
        Duration(milliseconds: (durationInSeconds * 1000).toInt());

    _timer = Timer(widget.pauseDuration, () {
      if (mounted && _shouldScroll) {
        _controller.repeat();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 🔥 Si maxWidth es infinito (dentro de un Column), tomamos el ancho de pantalla
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;

        _calculateMetrics(maxWidth, textScaler);

        // 🧾 TEXTO NORMAL (SIN SCROLL)
        if (!_shouldScroll) {
          return SizedBox(
            width: maxWidth,
            child: Text(
              widget.text,
              style: widget.style?.copyWith(overflow: TextOverflow.ellipsis),
              textAlign: widget.textAlign,
              maxLines: 1,
            ),
          );
        }

        // 🔄 MARQUEE
        return SizedBox(
          height: widget.height,
          width: maxWidth,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final distance = _cachedTextWidth + widget.gap;
              final offset = _controller.value * distance;

              return _HorizontalFadeMask(
                offset: offset,
                child: ClipRect(
                  child: Stack(
                    children: [
                      Transform.translate(
                        offset: Offset(-offset, 0),
                        child: OverflowBox(
                          maxWidth: double.infinity,
                          alignment: Alignment.centerLeft,
                          // 🔥 Aseguramos que NO tenga ellipsis mientras scrollea
                          child: Text(
                            widget.text,
                            style: widget.style?.copyWith(overflow: TextOverflow.visible),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(distance - offset, 0),
                        child: OverflowBox(
                          maxWidth: double.infinity,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.text,
                            style: widget.style?.copyWith(overflow: TextOverflow.visible),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _HorizontalFadeMask extends StatelessWidget {
  final Widget child;
  final double offset;

  const _HorizontalFadeMask({
    required this.child,
    required this.offset,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        final leftColor = (offset > 2) ? Colors.transparent : Colors.black;

        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            leftColor,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: const [0.0, 0.02, 0.98, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}
