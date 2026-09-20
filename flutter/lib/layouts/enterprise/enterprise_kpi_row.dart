import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/enterprise_theme.dart';
import '../../widgets/shared/shared_dashboard_metric.dart';

class EnterpriseKpiRow extends StatelessWidget {
  const EnterpriseKpiRow({super.key, required this.metrics, this.onMetricTap});

  final List<DashboardMetric> metrics;
  final ValueChanged<DashboardMetric>? onMetricTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = EnterpriseSpacing.md;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1200.0;
        final columns = availableWidth >= 1200
            ? 5
            : availableWidth >= 850
            ? 3
            : availableWidth >= 560
            ? 2
            : 1;
        final cardWidth = (availableWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: cardWidth,
                child: _KpiCard(
                  metric: metric,
                  onTap: onMetricTap == null
                      ? null
                      : () => onMetricTap!(metric),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.metric, this.onTap});

  final DashboardMetric metric;
  final VoidCallback? onTap;

  Color get _accentColor {
    return switch (metric.title.toLowerCase()) {
      'fleet health' => EnterpriseColors.fleetHealth,
      'base volume' => EnterpriseColors.baseVolume,
      'driver alerts' => EnterpriseColors.driverAlerts,
      'k-means clusters' => EnterpriseColors.kMeansClusters,
      'payroll' => EnterpriseColors.payroll,
      'maintenance alerts' => EnterpriseColors.maintenanceAlerts,
      _ => metric.baseColor,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shadowColor: accent.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 116,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(left: BorderSide(color: accent, width: 4)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                metric.icon,
                size: 22,
                color: theme.brightness == Brightness.dark
                    ? accent
                    : EnterpriseColors.main,
              ),
              const SizedBox(height: 6),
              Text(
                metric.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontFamily: GoogleFonts.montserrat().fontFamily,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                metric.subTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
