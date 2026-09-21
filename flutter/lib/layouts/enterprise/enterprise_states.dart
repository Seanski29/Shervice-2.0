import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/enterprise_theme.dart';

class EnterpriseSummaryCard extends StatelessWidget {
  const EnterpriseSummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(minHeight: 112), // Minimum height to prevent overflow
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min, // Prevents pixel overflow inside flexible grids
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 28,
              height: 1.0, // Tightly constraints the text height bounds to prevent overflow
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EnterpriseSummaryCardSkeleton extends StatelessWidget {
  const EnterpriseSummaryCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark
        ? EnterpriseColors.darkSurfaceMuted
        : const Color(0xFFD8DEE8);
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.7) : const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? EnterpriseColors.darkBorder : const Color(0xFFD0D5DD),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                FractionallySizedBox(
                  widthFactor: 0.8,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EnterpriseTableSkeleton extends StatelessWidget {
  const EnterpriseTableSkeleton({super.key, this.rows = 7, this.columns = 5});

  final int rows;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.brightness == Brightness.dark
        ? EnterpriseColors.darkSurfaceMuted
        : EnterpriseColors.lightSurfaceMuted;
    final highlightColor = theme.brightness == Brightness.dark
        ? EnterpriseColors.darkBorder
        : const Color(0xFFE4E7EC);

    return Semantics(
      label: 'Loading table data',
      liveRegion: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.35, end: 0.8),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOut,
        builder: (context, opacity, child) {
          final headColor = highlightColor.withValues(alpha: opacity);
          final rowColor = baseColor.withValues(alpha: opacity);
          return Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 30,
                          decoration: BoxDecoration(
                            color: headColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 88,
                        height: 28,
                        decoration: BoxDecoration(
                          color: headColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 42,
                  color: theme.brightness == Brightness.dark
                      ? EnterpriseColors.darkSurfaceMuted
                      : EnterpriseColors.lightSurfaceMuted,
                  child: Row(
                    children: List.generate(columns, (index) {
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: index == 0 ? 12 : 0,
                            right: 12,
                          ),
                          child: Container(
                            height: 12,
                            width: 80,
                            decoration: BoxDecoration(
                              color: headColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                for (var index = 0; index < rows; index++)
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: rowColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(width: 12),
                        for (var col = 0; col < columns - 1; col++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  height: 10,
                                  width: col == 0 ? 120 : 90,
                                  decoration: BoxDecoration(
                                    color: rowColor,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 6,
                      width: 160,
                      decoration: BoxDecoration(
                        color: headColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class EnterpriseFormSkeleton extends StatelessWidget {
  const EnterpriseFormSkeleton({super.key, this.fields = 4});

  final int fields;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? EnterpriseColors.darkSurfaceMuted
        : EnterpriseColors.lightSurfaceMuted;
    return Semantics(
      label: 'Loading form',
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < fields; index++) ...[
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.22,
              child: Container(height: 10, color: color),
            ),
            const SizedBox(height: 6),
            Container(
              height: 38,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class EnterpriseLoadingIndicator extends StatelessWidget {
  const EnterpriseLoadingIndicator({
    super.key,
    this.color,
    this.strokeWidth = 2,
  });

  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final skeletonColor =
        color?.withValues(alpha: 0.55) ??
        (Theme.of(context).brightness == Brightness.dark
            ? EnterpriseColors.darkBorder
            : const Color(0xFFD0D5DD));
    return Semantics(
      label: 'Loading',
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: strokeWidth + 4,
            decoration: BoxDecoration(
              color: skeletonColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 36,
            height: strokeWidth + 4,
            decoration: BoxDecoration(
              color: skeletonColor.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class EnterpriseEmptyState extends StatelessWidget {
  const EnterpriseEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 25),
          ),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({
    required this.columns,
    required this.height,
    required this.color,
  });

  final int columns;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          for (var index = 0; index < columns; index++) ...[
            Expanded(
              flex: index == 1 ? 2 : 1,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: index.isEven ? 0.72 : 0.9,
                child: Container(
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            if (index < columns - 1) const SizedBox(width: 18),
          ],
        ],
      ),
    );
  }
}

abstract final class EnterpriseToasts {
  static void success(BuildContext context, String message) {
    _show(
      context,
      message,
      EnterpriseColors.success,
      Icons.check_circle_outline,
    );
  }

  static void error(BuildContext context, String message) {
    _show(context, message, EnterpriseColors.danger, Icons.error_outline);
  }

  static void warning(BuildContext context, String message) {
    _show(context, message, EnterpriseColors.warning, Icons.warning_amber);
  }

  static void information(BuildContext context, String message) {
    _show(context, message, EnterpriseColors.information, Icons.info_outline);
  }

  static void _show(
    BuildContext context,
    String message,
    Color color,
    IconData icon,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showEnterpriseDestructiveConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  String confirmationText = 'DELETE',
}) async {
  final controller = TextEditingController();
  var valid = false;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              onChanged: (value) => setDialogState(
                () => valid = value.trim() == confirmationText,
              ),
              decoration: InputDecoration(
                labelText: 'Type $confirmationText to confirm',
                helperText: 'This second step prevents accidental data loss.',
                errorText: controller.text.isNotEmpty && !valid
                    ? 'Confirmation text does not match.'
                    : null,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: valid ? () => Navigator.pop(dialogContext, true) : null,
            style: FilledButton.styleFrom(
              backgroundColor: EnterpriseColors.danger,
            ),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return confirmed ?? false;
}