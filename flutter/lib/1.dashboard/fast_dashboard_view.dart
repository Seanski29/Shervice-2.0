import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constant.dart';
import '../layouts/enterprise/deferred_screen.dart';
import '../layouts/enterprise/enterprise_theme.dart';
import 'shared_dashboard_view.dart' deferred as full_dashboard;

class FastDashboardView extends StatefulWidget {
  const FastDashboardView({super.key, required this.showClientTrips});

  final bool showClientTrips;

  @override
  State<FastDashboardView> createState() => _FastDashboardViewState();
}

class _FastDashboardViewState extends State<FastDashboardView> {
  bool _loading = true;
  bool _showFullDashboard = false;
  String? _error;
  Map<String, dynamic> _metrics = {};

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$backendUrl/dashboard/metrics'))
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded is! Map) {
        throw StateError('Dashboard metrics failed.');
      }
      final payload = Map<String, dynamic>.from(decoded);
      if (payload['success'] != true) {
        throw StateError('Dashboard metrics were not successful.');
      }
      if (!mounted) return;
      setState(() {
        _metrics = Map<String, dynamic>.from(payload['metrics'] ?? {});
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not sync dashboard metrics.';
        _loading = false;
      });
    }
  }

  int _readInt(String primary, [String? fallback]) {
    final value = _metrics[primary] ?? (fallback == null ? null : _metrics[fallback]);
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_showFullDashboard) {
      return DeferredScreen(
        loader: full_dashboard.loadLibrary,
        builder: () => full_dashboard.SharedDashboardView(
          showClientTrips: widget.showClientTrips,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMetrics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _loadMetrics,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('Refresh'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EnterpriseColors.danger.withValues(alpha: 0.08),
                border: Border.all(
                  color: EnterpriseColors.danger.withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: EnterpriseColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_loading)
            const _FastDashboardSkeleton()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 700;
                final spacing = compact ? 12.0 : 16.0;
                final columns = constraints.maxWidth > 900
                    ? 2
                    : constraints.maxWidth > 640
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (spacing * (columns - 1))) /
                    columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    _MetricCard(
                      width: width,
                      title: 'Total Trips',
                      value: _readInt('totalTrips', 'ongoingTrips').toString(),
                      subtitle: 'Complete amount of trips',
                      icon: Icons.route,
                      color: const Color(0xFF3B82F6),
                    ),
                    _MetricCard(
                      width: width,
                      title: 'Total Passengers',
                      value: _readInt('totalPassengers').toString(),
                      subtitle: 'Total number of passengers',
                      icon: Icons.groups_outlined,
                      color: const Color(0xFF8B5CF6),
                    ),
                    _MetricCard(
                      width: width,
                      title: 'Active Drivers',
                      value: _readInt('activeDrivers', 'totalDrivers')
                          .toString(),
                      subtitle: 'Number of active drivers',
                      icon: Icons.people_alt,
                      color: const Color(0xFF06B6D4),
                    ),
                    _MetricCard(
                      width: width,
                      title: 'Active Vehicles',
                      value: _readInt('activeVehicles').toString(),
                      subtitle: 'Number of active vehicles',
                      icon: Icons.directions_car,
                      color: const Color(0xFF10B981),
                    ),
                    _MetricCard(
                      width: width,
                      title: 'Maintenance Alerts',
                      value: _readInt('maintenanceAlerts').toString(),
                      subtitle: 'Vehicles requiring maintenance',
                      icon: Icons.build_circle,
                      color: const Color(0xFFEF4444),
                    ),
                  ],
                );
              },
            ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => setState(() => _showFullDashboard = true),
              icon: const Icon(Icons.query_stats_outlined, size: 18),
              label: const Text('Load full dashboard'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FastDashboardSkeleton extends StatelessWidget {
  const _FastDashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).brightness == Brightness.dark
        ? EnterpriseColors.darkSurfaceMuted
        : const Color(0xFFE4E7EC);
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: List.generate(
        5,
        (_) => Container(
          width: 420,
          height: 138,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final double width;
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade400
        : Colors.grey.shade600;
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 138),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(icon, color: color, size: 22),
          ),
          SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
