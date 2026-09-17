import 'dart:math';
import 'package:flutter/material.dart';

class UniversalPagination extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int itemsPerPage;
  final VoidCallback? onNextPage;
  final VoidCallback? onPrevPage;
  final String itemName;

  const UniversalPagination({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.itemsPerPage,
    required this.onNextPage,
    required this.onPrevPage,
    this.itemName = 'items',
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (totalItems == 0) return const SizedBox.shrink();

    final int startItem = (currentPage * itemsPerPage) + 1;
    final int endItem = min((currentPage + 1) * itemsPerPage, totalItems);
    final int displayTotalPages = max(1, totalPages);

    return Wrap(
      alignment: WrapAlignment.start, // Changed from spaceBetween to start
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            'Showing $startItem - $endItem of $totalItems $itemName',
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
              fontSize: 13,
            ),
            softWrap: true,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: onPrevPage,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Previous'),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.blue.withValues(alpha: 0.15)
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${currentPage + 1} / $displayTotalPages',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.blue.shade300 : const Color(0xFF3B82F6),
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onNextPage,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }
}