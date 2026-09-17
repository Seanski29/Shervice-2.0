import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import 'route_optimization_tab.dart';
import '../../../constant.dart';

import 'fleet_overview_tab.dart';
import 'driver_performance_tab.dart';
import 'vehicle_ml_tab.dart';
import 'company_analytics_tab.dart';

class SharedAnalyticsHub extends StatefulWidget {
  const SharedAnalyticsHub({super.key});

  @override
  State<SharedAnalyticsHub> createState() => _SharedAnalyticsHubState();
}

class _SharedAnalyticsHubState extends State<SharedAnalyticsHub> {
  int _activeTab = 0;
  bool _isLoading = true;

  List<dynamic> _allDrivers = [];
  List<dynamic> _allVehicles = [];
  List<dynamic> _allTrips = [];
  List<dynamic> _allMaintenanceLogs = [];

  final Set<int> _visitedTabs = {0};

  @override
  void initState() {
    super.initState();
    _fetchGlobalAnalyticsPayload();
  }

  Future<void> _fetchGlobalAnalyticsPayload() async {
    setState(() => _isLoading = true);
    try {
      final cleanBaseUrl = backendUrl.endsWith('/')
          ? backendUrl.substring(0, backendUrl.length - 1)
          : backendUrl;

      // 1. Fetch all primary endpoints concurrently
      final results = await Future.wait([
        http
            .get(Uri.parse('$cleanBaseUrl/test-db'))
            .timeout(const Duration(seconds: 10)),
        http
            .get(Uri.parse('$cleanBaseUrl/trips'))
            .timeout(const Duration(seconds: 10)),
        http
            .get(Uri.parse('$cleanBaseUrl/vehicles/maintenance'))
            .timeout(const Duration(seconds: 10)),
        http
            .get(Uri.parse('$cleanBaseUrl/vehicles'))
            .timeout(const Duration(seconds: 10)),
        http
            .get(Uri.parse('$cleanBaseUrl/dashboard/metrics'))
            .timeout(const Duration(seconds: 10)),
      ]);

      final dRes = results[0];
      final tRes = results[1];
      final mRes = results[2];
      final vRes = results[3];
      // 2. Parse Trips
      List<dynamic> trips = [];
      if (tRes.statusCode == 200) {
        final tData = jsonDecode(tRes.body);
        trips = tData is List
            ? tData
            : (tData['trips'] ?? tData['sample_data_payload'] ?? []);
        _allTrips = trips;
      }

      // 3. Parse Maintenance Logs
      if (mRes.statusCode == 200) {
        final mData = jsonDecode(mRes.body);
        _allMaintenanceLogs = mData['data'] ?? mData['logs'] ?? [];
      }

      // 4. Parse Vehicles
      if (vRes.statusCode == 200) {
        List<dynamic> vehicles = jsonDecode(vRes.body)['data'] ?? [];
        for (var v in vehicles) {
          v['live_risk_score'] =
              double.tryParse(
                (v['risk_score'] ?? v['live_risk_score'] ?? '0').toString(),
              ) ??
              0.0;
        }
        _allVehicles = vehicles;
      }

      // 5. Parse Drivers & Compute True Rating from Completed Trips
      if (dRes.statusCode == 200) {
        List<dynamic> rawDrivers =
            jsonDecode(dRes.body)['sample_data_payload'] ?? [];

        // PERF: Aggregate trip ratings once, reducing driver rating lookup from
        // O(drivers * trips) scans to O(drivers + trips) hash-map lookups.
        final Map<String, List<double>> ratingTotalsByDriver = {};
        final Set<String> driversWithTrips = {};
        for (final trip in trips) {
          final driverId = (trip['user_id'] ?? '').toString();
          if (driverId.isEmpty) continue;
          driversWithTrips.add(driverId);
          final rating = double.tryParse(
            (trip['rating'] ?? trip['evaluation_score'] ?? trip['csat'] ?? '')
                .toString(),
          );
          if (rating == null || rating <= 0) continue;
          final totals = ratingTotalsByDriver.putIfAbsent(
            driverId,
            () => [0.0, 0.0],
          );
          totals[0] += rating;
          totals[1] += 1.0;
        }

        for (var d in rawDrivers) {
          final String dUid = (d['user_id'] ?? d['id'] ?? '').toString();

          // Check if driver has an existing rating in payload
          double existingRating =
              double.tryParse(
                (d['rating'] ?? d['average_rating'] ?? '0').toString(),
              ) ??
              0.0;

          // If 0, compute rating from trips linked to this driver
          if (existingRating == 0.0 && trips.isNotEmpty) {
            final totals = ratingTotalsByDriver[dUid];
            if (totals != null && totals[1] > 0) {
              existingRating = totals[0] / totals[1];
            } else {
              // Preserve the existing fallback distinction for drivers with trips.
              existingRating = driversWithTrips.contains(dUid) ? 4.6 : 4.5;
            }
          }

          d['rating'] = existingRating > 0 ? existingRating : 4.5;
          d['ml_classification'] =
              d['classification'] ?? 'Consistent Performer';
        }

        _allDrivers = rawDrivers;

        if (mounted) {
          setState(() => _isLoading = false);
        }

        // Non-blocking enrichment loop
        unawaited(_enrichDriverClassifications(cleanBaseUrl, rawDrivers));
        return;
      }
    } catch (e) {
      debugPrint("Global Analytics Fetch Error: $e");
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _enrichDriverClassifications(
    String cleanBaseUrl,
    List<dynamic> drivers,
  ) async {
    const int chunkSize = 6;
    for (int i = 0; i < drivers.length; i += chunkSize) {
      if (!mounted) return;
      final chunk = drivers.sublist(
        i,
        (i + chunkSize > drivers.length) ? drivers.length : i + chunkSize,
      );

      await Future.wait(
        chunk.map((d) async {
          final String dId = (d['user_id'] ?? d['id'] ?? '').toString();
          if (dId.isEmpty) return;
          try {
            final res = await http
                .get(Uri.parse('$cleanBaseUrl/drivers/classify/$dId'))
                .timeout(const Duration(seconds: 4));
            if (res.statusCode == 200 && mounted) {
              final parsed = jsonDecode(res.body);
              d['ml_classification'] =
                  parsed['classification'] ?? d['ml_classification'];

              var ratingVal = parsed['rating'] ?? parsed['average_rating'];
              if (ratingVal != null) {
                double? parsedRating = double.tryParse(ratingVal.toString());
                if (parsedRating != null && parsedRating > 0) {
                  d['rating'] = parsedRating;
                }
              }
            }
          } catch (_) {}
        }),
      );

      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _handleManualSync() async {
    setState(() => _isLoading = true);
    try {
      final cleanBaseUrl = backendUrl.endsWith('/')
          ? backendUrl.substring(0, backendUrl.length - 1)
          : backendUrl;

      // Increased timeout to 45 seconds for ML regression on all 30+ fleet vehicles
      await http
          .post(Uri.parse('$cleanBaseUrl/vehicles/predict/fleet-sweep'))
          .timeout(const Duration(seconds: 45));
      await _fetchGlobalAnalyticsPayload();
    } catch (e) {
      debugPrint("Manual sweep failed: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Skeletonizer(
        enabled: _isLoading && _allVehicles.isEmpty,
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _buildNavigationTabs(isDark)),
                  const SizedBox(width: 12),
                  _buildSweepButton(),
                ],
              ),
              const SizedBox(height: 8),

              Expanded(
                child: _isLoading && _allVehicles.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : IndexedStack(
                        index: _activeTab,
                        children: [
                          FleetOverviewTab(
                            vehicles: _allVehicles,
                            drivers: _allDrivers,
                            trips: _allTrips,
                            maintenanceLogs: _allMaintenanceLogs,
                            onSyncAction: _handleManualSync,
                            onReload: _fetchGlobalAnalyticsPayload,
                          ),
                          _visitedTabs.contains(1)
                              ? DriverPerformanceTab(
                                  drivers: _allDrivers,
                                  backendUrl: backendUrl,
                                  onSyncAction: _handleManualSync,
                                )
                              : const SizedBox.shrink(),
                          _visitedTabs.contains(2)
                              ? VehicleMlTab(
                                  vehicles: _allVehicles,
                                  backendUrl: backendUrl,
                                  onSyncAction: _handleManualSync,
                                )
                              : const SizedBox.shrink(),
                          _visitedTabs.contains(3)
                              ? RouteOptimizationTab(
                                  backendUrl: backendUrl,
                                  onSyncAction: _handleManualSync,
                                )
                              : const SizedBox.shrink(),
                          _visitedTabs.contains(4)
                              ? CompanyAnalyticsTab(
                                  trips: _allTrips,
                                  drivers: _allDrivers,
                                )
                              : const SizedBox.shrink(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationTabs(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
        border: isDark ? Border.all(color: Colors.grey.shade800) : null,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildNavTab(0, 'Fleet', Icons.dashboard, isDark),
            _buildNavTab(1, 'Drivers', Icons.person, isDark),
            _buildNavTab(2, 'Vehicle ML', Icons.directions_bus, isDark),
            _buildNavTab(3, 'Routes', Icons.alt_route, isDark),
            _buildNavTab(4, 'Company', Icons.business, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildSweepButton() {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _handleManualSync,
      icon: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.memory, size: 18),
      label: const Text('Run AI Sweep'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildNavTab(int index, String label, IconData icon, bool isDark) {
    final bool isActive = _activeTab == index;
    final Color activeBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color inactiveText = isDark
        ? Colors.grey.shade500
        : const Color(0xFF64748B);

    return SizedBox(
      width: 124,
      child: InkWell(
        onTap: () {
          setState(() {
            _activeTab = index;
            _visitedTabs.add(index);
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: isDark ? Colors.black45 : Colors.black12,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? const Color(0xFF3B82F6) : inactiveText,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                      fontSize: 13,
                      color: isActive ? const Color(0xFF3B82F6) : inactiveText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
