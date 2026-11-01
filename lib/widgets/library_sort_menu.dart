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
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: false,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.tune_rounded,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ordenar biblioteca',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Elige cómo quieres ver tus canciones',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showIgnoreArticles)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SwitchListTile(
                    value: ignoreArticles,
                    onChanged: (enabled) {
                      onIgnoreArticlesChanged?.call(enabled);
                      Navigator.pop(sheetContext);
                    },
                    secondary: Icon(
                      Icons.format_clear_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      'Ignorar artículos',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'El, La, Los, Las, Un, Una, A, An, The…',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 18),
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = option.matches(value);
                  final isDescending = option.reverseValue == value;
                  final colors = Theme.of(context).colorScheme;
                  final color =
                      isSelected ? colors.primary : colors.onSurfaceVariant;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Material(
                      color: isSelected
                          ? colors.primary.withValues(alpha: 0.12)
                          : colors.surfaceContainerHighest
                              .withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          final nextValue =
                              isSelected && option.reverseValue != null
                                  ? (isDescending
                                      ? option.value
                                      : option.reverseValue!)
                                  : option.value;
                          Navigator.pop(sheetContext, nextValue);
                        },
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 62),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? colors.primary.withValues(alpha: 0.55)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.13),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child:
                                    Icon(option.icon, color: color, size: 22),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Text(
                                  option.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? colors.primary
                                        : colors.onSurface,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  isDescending
                                      ? Icons.south_rounded
                                      : Icons.north_rounded,
                                  color: colors.primary,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
