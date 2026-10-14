import 'package:flutter/material.dart';

class LibrarySortOption {
  final String value;
  final String label;
  final IconData icon;

  const LibrarySortOption(this.value, this.label, this.icon);
}

class LibrarySortMenu extends StatelessWidget {
  final String value;
  final List<LibrarySortOption> options;
  final ValueChanged<String> onSelected;

  const LibrarySortMenu({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );
    return PopupMenuButton<String>(
      tooltip: 'Ordenar por',
      initialValue: selected.value,
      onSelected: onSelected,
      color: const Color(0xFF252525),
      icon: const Icon(Icons.sort_rounded, color: Colors.white70, size: 20),
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          height: 36,
          child: Text(
            'Ordenar por',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        for (final option in options)
          PopupMenuItem<String>(
            value: option.value,
            child: Row(
              children: [
                Icon(
                  option.icon,
                  size: 19,
                  color: option.value == selected.value
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white70,
                ),
                const SizedBox(width: 12),
                Text(option.label),
              ],
            ),
          ),
      ],
    );
  }
}
