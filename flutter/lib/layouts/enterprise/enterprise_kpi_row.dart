import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'enterprise_theme.dart';
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
    final isDark = theme.brightness == Brightness.dark;
    final fill = Color.lerp(theme.cardColor, accent, isDark ? 0.18 : 0.07)!;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : EnterpriseColors.substitute;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shadowColor: accent.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.38)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 116,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: fill,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(metric.icon, size: 20, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      metric.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFamily: GoogleFonts.montserrat().fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      metric.value,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                metric.subTitle,
                textAlign: TextAlign.center,
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
