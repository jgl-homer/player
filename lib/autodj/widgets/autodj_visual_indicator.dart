import 'package:flutter/material.dart';

import '../services/autodj_controller.dart';

class AutoDjVisualIndicator extends StatelessWidget {
  final AutoDjController controller;

  const AutoDjVisualIndicator({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.settings.enabled ||
            !controller.settings.visualEffects) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<Duration>(
          stream: controller.primary.positionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? controller.primary.position;
            final pulse = controller.visualPulse(position);
            final transition = controller.transitionProgress(position);
            final active = controller.status == AutoDjStatus.mixing;
            final color = Color.lerp(
              Colors.tealAccent.withAlpha(90),
              Colors.purpleAccent,
              pulse,
            )!;
            return Semantics(
              label: active
                  ? 'AutoDJ mezclando ${(transition * 100).round()} por ciento'
                  : 'AutoDJ preparado',
              child: Container(
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Colors.white10,
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    Expanded(
                      flex: active ? ((1 - transition) * 100).round() : 100,
                      child: ColoredBox(
                        color: color.withValues(
                          alpha: 0.35 + pulse * 0.65,
                        ),
                      ),
                    ),
                    if (active)
                      Expanded(
                        flex: (transition * 100).round().clamp(1, 100),
                        child: ColoredBox(
                          color: Colors.purpleAccent.withValues(
                            alpha: 0.45 +
                                controller.visualEnergy.clamp(0, 1) * 0.55,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
