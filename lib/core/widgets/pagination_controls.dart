import 'package:flutter/material.dart';

/// Compact numbered pagination used by long customer lists.
class PaginationControls extends StatelessWidget {
  const PaginationControls({
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    super.key,
  });

  /// Zero based page index.
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    final pages = <int>{0, totalPages - 1};
    for (var page = currentPage - 2; page <= currentPage + 2; page++) {
      if (page >= 0 && page < totalPages) pages.add(page);
    }
    final ordered = pages.toList()..sort();
    final items = <Widget>[];
    var previous = -1;
    for (final page in ordered) {
      if (previous >= 0 && page - previous > 1) {
        items.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 5),
          child: Text('…'),
        ));
      }
      items.add(_PageButton(
        label: '${page + 1}',
        selected: page == currentPage,
        onPressed: () => onPageChanged(page),
      ));
      previous = page;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PageButton(
              label: '‹',
              enabled: currentPage > 0,
              onPressed: () => onPageChanged(currentPage - 1),
            ),
            const SizedBox(width: 6),
            for (final item in items) ...[
              item,
              const SizedBox(width: 6),
            ],
            _PageButton(
              label: '›',
              enabled: currentPage < totalPages - 1,
              onPressed: () => onPageChanged(currentPage + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    const selectedColor = Color(0xFFE9433A);
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(40, 40),
          foregroundColor: selected ? Colors.white : color,
          backgroundColor: selected ? selectedColor : null,
          side: BorderSide(
            color: selected ? selectedColor : color.withValues(alpha: .35),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label),
      ),
    );
  }
}
