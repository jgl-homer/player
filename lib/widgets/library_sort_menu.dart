import 'package:flutter/material.dart';

class LibrarySortOption {
  final String value;
  final String label;
  final IconData icon;
  final String? reverseValue;

  const LibrarySortOption(
    this.value,
    this.label,
    this.icon, {
    this.reverseValue,
  });

  bool matches(String currentValue) =>
      value == currentValue || reverseValue == currentValue;
}

class LibrarySortMenu extends StatelessWidget {
  final String value;
  final List<LibrarySortOption> options;
  final ValueChanged<String> onSelected;
  final bool showIgnoreArticles;
  final bool ignoreArticles;
  final ValueChanged<bool>? onIgnoreArticlesChanged;
  final IconData icon;

  const LibrarySortMenu({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.showIgnoreArticles = false,
    this.ignoreArticles = false,
    this.onIgnoreArticlesChanged,
    this.icon = Icons.sort_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere(
      (option) => option.matches(value),
      orElse: () => options.first,
    );
    return IconButton(
      tooltip: 'Ordenar por',
      icon: Icon(icon, color: Colors.white70, size: 22),
      onPressed: () => _showSortSheet(context, selected),
    );
  }

  Future<void> _showSortSheet(
    BuildContext context,
    LibrarySortOption selected,
  ) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF222222),
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, 18),
              child: Text(
                'Ordenar por',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            if (showIgnoreArticles)
              SwitchListTile(
                value: ignoreArticles,
                onChanged: (enabled) {
                  onIgnoreArticlesChanged?.call(enabled);
                  Navigator.pop(sheetContext);
                },
                secondary: const Icon(
                  Icons.format_clear_rounded,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Ignorar artículos',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'El, La, Los, Las, Un, Una, A, An, The…',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            if (showIgnoreArticles)
              const Divider(height: 1, color: Colors.white12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = option.matches(value);
                  final isDescending = option.reverseValue == value;
                  final color = isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white70;
                  return ListTile(
                    minTileHeight: 58,
                    leading: Icon(
                      isSelected
                          ? (isDescending
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded)
                          : option.icon,
                      color: color,
                      size: 25,
                    ),
                    title: Text(
                      option.label,
                      style: TextStyle(
                        color: isSelected ? color : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    selectedTileColor: Colors.white.withValues(alpha: 0.06),
                    onTap: () {
                      final nextValue = isSelected &&
                              option.reverseValue != null
                          ? (isDescending ? option.value : option.reverseValue!)
                          : option.value;
                      Navigator.pop(sheetContext, nextValue);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != value) onSelected(chosen);
  }
}
