import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/enterprise_theme.dart';
import 'dashboard_metric.dart';

class EnterpriseKpiRow extends StatelessWidget {
  const EnterpriseKpiRow({super.key, required this.metrics, this.onMetricTap});

  final List<DashboardMetric> metrics;
  final ValueChanged<DashboardMetric>? onMetricTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = EnterpriseSpacing.md;
        final cardWidth = metrics.isEmpty
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (metrics.length - 1)) /
                  metrics.length;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                SizedBox(
                  width: cardWidth.clamp(148.0, 260.0),
                  child: _KpiCard(
                    metric: metrics[index],
                    onTap: onMetricTap == null
                        ? null
                        : () => onMetricTap!(metrics[index]),
                  ),
                ),
                if (index != metrics.length - 1) SizedBox(width: gap),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.metric, this.onTap});

  final DashboardMetric metric;
  final VoidCallback? onTap;

  LinearGradient get _gradient {
    final color = switch (metric.title.toLowerCase()) {
      'fleet health' => EnterpriseColors.fleetHealth,
      'base volume' => EnterpriseColors.baseVolume,
      'driver alerts' => EnterpriseColors.driverAlerts,
      'k-means clusters' => EnterpriseColors.kMeansClusters,
      'payroll' => EnterpriseColors.payroll,
      'maintenance alerts' => EnterpriseColors.maintenanceAlerts,
      _ => metric.baseColor,
    };
    return EnterpriseGradients.fadingToWhite(color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: EnterpriseColors.substitute, width: 1.2),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 116,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(gradient: _gradient),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(metric.icon, size: 22, color: EnterpriseColors.main),
              const SizedBox(height: 6),
              Text(
                metric.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: EnterpriseColors.main,
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
                  color: EnterpriseColors.main,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                metric.subTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: EnterpriseColors.main.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
