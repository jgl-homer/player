import 'package:flutter/material.dart';

/// Barra de subencabezado que muestra el conteo total de una sección.
/// Se coloca justo arriba del ListView de cada pestaña.
class CountBanner extends StatelessWidget {
  final int count;
  final String label;
  final Widget? trailing;
  final Color backgroundColor;

  const CountBanner({
    super.key,
    required this.count,
    required this.label,
    this.trailing,
    this.backgroundColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: backgroundColor,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count $label',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
