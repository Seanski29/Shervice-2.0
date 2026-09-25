import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../layouts/enterprise/enterprise_theme.dart';

class FleetOverviewTab extends StatefulWidget {
  final List<dynamic> vehicles;
  final List<dynamic> drivers;
  final List<dynamic> trips;
  final List<dynamic> maintenanceLogs;
  final VoidCallback onSyncAction;
  final VoidCallback? onReload;

  const FleetOverviewTab({
    super.key,
    required this.vehicles,
    required this.drivers,
    required this.trips,
    required this.maintenanceLogs,
    required this.onSyncAction,
    this.onReload,
  });

  @override
  State<FleetOverviewTab> createState() => _FleetOverviewTabState();
}

class _FleetOverviewTabState extends State<FleetOverviewTab> {
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  String _trendMode = 'Auto';

  final List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  List<int> _availableYears = [];

  @override
  void initState() {
    super.initState();
    _extractAvailableYears();
  }

  void _extractAvailableYears() {
    Set<int> years = {DateTime.now().year};
    for (var t in widget.trips) {
      DateTime? d = DateTime.tryParse((t['schedule_date'] ?? '').toString());
      if (d != null) years.add(d.year);
    }
    _availableYears = years.toList()..sort((a, b) => b.compareTo(a));
  }

  double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  int _parseInt(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  DateTime? _tripDate(dynamic trip) {
    return DateTime.tryParse(
      (trip['schedule_date'] ?? trip['date'] ?? '').toString().split(' ').first,
    );
  }

  String _trendBucket(DateTime date) {
    final mode = _trendMode == 'Auto'
        ? (_selectedYear == 0
              ? 'Month'
              : _selectedMonth == 0
              ? 'Month'
              : 'Day')
        : _trendMode;
    if (mode == 'Day') {
      return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    if (mode == 'Week') {
      final week = ((date.day - 1) ~/ 7) + 1;
      return '${date.year}-${date.month.toString().padLeft(2, '0')} W$week';
    }
    if (mode == 'Month') {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}';
    }
    return date.year.toString();
  }

  String _trendLabel() {
    final mode = _trendMode == 'Auto'
        ? (_selectedMonth == 0 ? 'Month' : 'Day')
        : _trendMode;
    return 'Trip Volume Trend by $mode';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    // --- Filter Data based on Dropdowns ---
    List<dynamic> fTrips = widget.trips.where((t) {
      if (_selectedYear == 0) return true; // All Time
      DateTime? d = _tripDate(t);
      if (d == null) return false;
      if (_selectedMonth == 0) return d.year == _selectedYear; // All Months
      return d.year == _selectedYear &&
          d.month == _selectedMonth; // Specific Month
    }).toList();

    List<dynamic> fMaint = widget.maintenanceLogs.where((m) {
      if (_selectedYear == 0) return true;
      DateTime? d = DateTime.tryParse(
        (m['incident_date'] ?? m['repair_date'] ?? '').toString(),
      );
      if (d == null) return false;
      if (_selectedMonth == 0) return d.year == _selectedYear;
      return d.year == _selectedYear && d.month == _selectedMonth;
    }).toList();

    // --- KPIs ---
    int totalPax = fTrips.fold(
      0,
      (s, t) => s + _parseInt(t['passenger_count']),
    );

    int readyV = widget.vehicles.where((v) {
      double daysRemaining = (v['live_risk_score'] as num?)?.toDouble() ?? 0.0;
      String st = (v['health_status'] ?? '').toString().toLowerCase();
      return !st.contains('maintenance') &&
          !st.contains('repair') &&
          daysRemaining > 7.0;
    }).length;

    List<dynamic> evaluatedTrips = fTrips
        .where(
          (t) =>
              t['rating'] != null ||
              t['csat'] != null ||
              t['evaluation_score'] != null,
        )
        .toList();

    double csat = 0.0;
    if (evaluatedTrips.isNotEmpty) {
      csat =
          evaluatedTrips.fold(
            0.0,
            (s, t) =>
                s +
                _parseDouble(t['rating'] ?? t['csat'] ?? t['evaluation_score']),
          ) /
          evaluatedTrips.length;
    } else {
      csat = widget.drivers.isEmpty
          ? 0.0
          : widget.drivers.fold(0.0, (s, d) => s + _parseDouble(d['rating'])) /
                widget.drivers.length;
    }

    // --- CHART DATA GROUPING ---
    Map<String, int> timeBuckets = {};

    for (var t in fTrips) {
      final date = _tripDate(t);
      if (date == null) continue;
      final bucketKey = _trendBucket(date);
      timeBuckets[bucketKey] = (timeBuckets[bucketKey] ?? 0) + 1;
    }

    final displayKeys = timeBuckets.keys.toList()..sort();
    List<MapEntry<String, int>> tripVolData = displayKeys
        .map((k) => MapEntry(k, timeBuckets[k]!))
        .toList();

    final monthlyMaintenance = List<int>.filled(12, 0);
    final monthlyRepairs = List<int>.filled(12, 0);
    for (final log in fMaint) {
      final date = DateTime.tryParse(
        (log['incident_date'] ?? log['repair_date'] ?? '').toString(),
      );
      if (date == null) continue;
      final recordType = (log['maintenance_type'] ?? 'maintenance')
          .toString()
          .toLowerCase();
      if (recordType == 'repair') {
        monthlyRepairs[date.month - 1]++;
      } else {
        monthlyMaintenance[date.month - 1]++;
      }
    }

    Map<String, int> maintenanceCategoryCounts = {};
    Map<String, int> repairCategoryCounts = {};
    for (final log in fMaint) {
      final category = (log['category'] ?? 'General').toString().trim();
      final key = category.isEmpty ? 'General' : category;
      final recordType = (log['maintenance_type'] ?? 'maintenance')
          .toString()
          .toLowerCase();
      final counts = recordType == 'repair'
          ? repairCategoryCounts
          : maintenanceCategoryCounts;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final maintenanceCategoryData = maintenanceCategoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final repairCategoryData = repairCategoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Map<String, int> routeCounts = {};
    for (var t in fTrips) {
      String r = (t['route_name'] ?? '').toString().trim();
      if (r.isEmpty) r = 'Unknown Route';
      routeCounts[r] = (routeCounts[r] ?? 0) + 1;
    }
    final routeData = routeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                "Executive Operations Dashboard",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  fontSize: 16,
                ),
              ),
              IconButton(
                tooltip: 'Reload fleet data',
                icon: const Icon(Icons.refresh),
                onPressed: widget.onReload ?? widget.onSyncAction,
              ),
              // --- INLINE DROPDOWN FILTERS ---
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: cardBg,
                  border: Border.all(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedMonth,
                        dropdownColor: cardBg,
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: textColor,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('All months'),
                          ),
                          ...List.generate(
                            12,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text(_monthNames[i]),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedMonth = val);
                          }
                        },
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 16,
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedYear,
                        dropdownColor: cardBg,
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: textColor,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('All time'),
                          ),
                          ..._availableYears.map(
                            (y) => DropdownMenuItem(
                              value: y,
                              child: Text(y.toString()),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            if (val != null) _selectedYear = val;
                          });
                        },
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 16,
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _trendMode,
                        dropdownColor: cardBg,
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: textColor,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Auto',
                            child: Text('Auto trend'),
                          ),
                          DropdownMenuItem(
                            value: 'Day',
                            child: Text('Trips / day'),
                          ),
                          DropdownMenuItem(
                            value: 'Week',
                            child: Text('Trips / week'),
                          ),
                          DropdownMenuItem(
                            value: 'Month',
                            child: Text('Trips / month'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _trendMode = val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          LayoutBuilder(
            builder: (context, kpiConstraints) {
              final cards = [
                _buildKpiCard(
                  'Total Passengers',
                  totalPax.toString(),
                  Icons.people,
                  const Color(0xFF8B5CF6),
                  isDark,
                ),
                _buildKpiCard(
                  'Fleet Readiness',
                  '$readyV / ${widget.vehicles.length}',
                  Icons.check_circle,
                  const Color(0xFF10B981),
                  isDark,
                ),
                _buildKpiCard(
                  'Average Driver Performance Rating',
                  '${csat.toStringAsFixed(1)} ★',
                  Icons.star,
                  const Color(0xFFF59E0B),
                  isDark,
                ),
              ];
              if (kpiConstraints.maxWidth < 700) {
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards
                      .map(
                        (card) => SizedBox(
                          width: (kpiConstraints.maxWidth - 12) / 2,
                          child: card,
                        ),
                      )
                      .toList(),
                );
              }
              return Row(
                children: [
                  for (var index = 0; index < cards.length; index++) ...[
                    if (index > 0) const SizedBox(width: 12),
                    Expanded(child: cards[index]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          LayoutBuilder(
            builder: (context, constraints) {
              bool isMobile = constraints.maxWidth < 800;
              return Column(
                children: [
                  if (isMobile) ...[
                    _buildLineChart(
                      _trendLabel(),
                      tripVolData,
                      const Color(0xFF3B82F6),
                      isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildRiskDistributionPie(widget.vehicles, isDark),
                    const SizedBox(height: 16),
                    _buildRoutePieChart(routeData, isDark),
                    const SizedBox(height: 16),
                    _buildMaintenanceCategorySection(
                      maintenanceCategoryData,
                      repairCategoryData,
                      isDark,
                    ),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildLineChart(
                            _trendLabel(),
                            tripVolData,
                            const Color(0xFF3B82F6),
                            isDark,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _buildRiskDistributionPie(
                            widget.vehicles,
                            isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildRoutePieChart(routeData, isDark)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildMaintenanceCategorySection(
                            maintenanceCategoryData,
                            repairCategoryData,
                            isDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    final fill = Color.lerp(
      isDark ? EnterpriseColors.darkSurface : EnterpriseColors.white,
      color,
      isDark ? 0.18 : 0.07,
    )!;
    return Container(
      height: 116,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.72)
                        : EnterpriseColors.substitute,
                    fontFamily: GoogleFonts.montserrat().fontFamily,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart(
    String title,
    List<MapEntry<String, int>> data,
    Color lineColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: 250,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: lineColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Trips",
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: data.isEmpty
                ? Center(
                    child: Text(
                      "No trip data available for this timeframe",
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      return CustomPaint(
                        size: Size(box.maxWidth, box.maxHeight),
                        painter: _TripLineChartPainter(
                          data: data,
                          lineColor: lineColor,
                          isDark: isDark,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskDistributionBar(List<dynamic> vehicles, bool isDark) {
    int optimal = 0, fair = 0, risk = 0, maint = 0;
    for (var v in vehicles) {
      double daysRemaining = (v['live_risk_score'] as num?)?.toDouble() ?? 0.0;
      String dbStatus = (v['health_status'] ?? '').toString().toLowerCase();
      if (dbStatus.contains('maintenance') ||
          dbStatus.contains('repair') ||
          daysRemaining <= 7.0) {
        maint++;
      } else if (daysRemaining <= 30.0) {
        risk++;
      } else if (daysRemaining <= 90.0) {
        fair++;
      } else {
        optimal++;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      height: 250,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Forecasted Maintenance Cycle Distribution",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 32),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 32,
              child: Row(
                children: [
                  if (optimal > 0)
                    Expanded(
                      flex: optimal,
                      child: Container(color: const Color(0xFF10B981)),
                    ),
                  if (fair > 0)
                    Expanded(
                      flex: fair,
                      child: Container(color: const Color(0xFFF59E0B)),
                    ),
                  if (risk > 0)
                    Expanded(
                      flex: risk,
                      child: Container(color: const Color(0xFFF97316)),
                    ),
                  if (maint > 0)
                    Expanded(
                      flex: maint,
                      child: Container(color: const Color(0xFFEF4444)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _legendItem(
                'Optimal (>90d)',
                optimal,
                const Color(0xFF10B981),
                isDark,
              ),
              _legendItem('Fair (<90d)', fair, const Color(0xFFF59E0B), isDark),
              _legendItem(
                'High Risk (<30d)',
                risk,
                const Color(0xFFF97316),
                isDark,
              ),
              _legendItem(
                'Critical (<7d)',
                maint,
                const Color(0xFFEF4444),
                isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRiskDistributionPie(List<dynamic> vehicles, bool isDark) {
    int optimal = 0, fair = 0, risk = 0, maint = 0;
    for (final vehicle in vehicles) {
      final days = (vehicle['live_risk_score'] as num?)?.toDouble() ?? 0.0;
      final status = (vehicle['health_status'] ?? '').toString().toLowerCase();
      if (status.contains('maintenance') ||
          status.contains('repair') ||
          days <= 7.0) {
        maint++;
      } else if (days <= 30.0) {
        risk++;
      } else if (days <= 90.0) {
        fair++;
      } else {
        optimal++;
      }
    }

    return _buildPieChartCard(
      'Forecasted Maintenance Cycle Distribution',
      [
        MapEntry('Optimal (>90d)', optimal),
        MapEntry('Fair (<90d)', fair),
        MapEntry('High Risk (<30d)', risk),
        MapEntry('Critical (<7d)', maint),
      ],
      const [
        Color(0xFF10B981),
        Color(0xFFF59E0B),
        Color(0xFFF97316),
        Color(0xFFEF4444),
      ],
      isDark,
    );
  }

  Widget _buildRoutePieChart(List<MapEntry<String, int>> routes, bool isDark) {
    return _buildPieChartCard(
      'Routes',
      routes,
      List<Color>.generate(
        routes.length,
        (index) => Colors.primaries[index % Colors.primaries.length],
      ),
      isDark,
    );
  }

  Widget _buildPieChartCard(
    String title,
    List<MapEntry<String, int>> data,
    List<Color> colors,
    bool isDark,
  ) {
    final total = data.fold<int>(0, (sum, item) => sum + item.value);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      padding: const EdgeInsets.all(16),
      height: 250,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: data.isEmpty
                ? Center(
                    child: Text(
                      'No records available.',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, chartConstraints) {
                      final pieWidth = min(
                        260.0,
                        max(120.0, chartConstraints.maxWidth * 0.48),
                      );
                      final pieRadius = min(
                        78.0,
                        max(
                          42.0,
                          min(
                            pieWidth * 0.34,
                            chartConstraints.maxHeight * 0.34,
                          ),
                        ),
                      );
                      final pieDiameter = pieRadius * 2;

                      return Row(
                        children: [
                          SizedBox(
                            width: pieWidth,
                            child: Center(
                              child: SizedBox.square(
                                dimension: pieDiameter,
                                child: PieChart(
                                  PieChartData(
                                    sectionsSpace: 2,
                                    centerSpaceRadius: pieRadius * 0.54,
                                    sections: [
                                      for (
                                        var index = 0;
                                        index < data.length;
                                        index++
                                      )
                                        PieChartSectionData(
                                          value: data[index].value.toDouble(),
                                          color: colors[index],
                                          radius: pieRadius,
                                          title: total == 0
                                              ? ''
                                              : '${(data[index].value * 100 / total).round()}%',
                                          titleStyle: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (
                                    var index = 0;
                                    index < data.length;
                                    index++
                                  )
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 9,
                                            height: 9,
                                            decoration: BoxDecoration(
                                              color: colors[index],
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${data[index].key} (${data[index].value})',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark
                                                    ? Colors.grey.shade300
                                                    : Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceCategorySection(
    List<MapEntry<String, int>> maintenance,
    List<MapEntry<String, int>> repairs,
    bool isDark,
  ) {
    final monthLabel = _selectedMonth == 0
        ? 'All Months'
        : _monthNames[_selectedMonth - 1];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep both category cards beside each other on laptop layouts. The
        // parent row already places this section beside the Routes card.
        // Wrapping below 700 caused the second card to move underneath it.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildHorizontalBarChart(
                'Maintenance Categories - $monthLabel',
                maintenance,
                const Color(0xFFEF4444),
                isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildHorizontalBarChart(
                'Repair Categories - $monthLabel',
                repairs,
                const Color(0xFFF97316),
                isDark,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _legendItem(String label, int count, Color c, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          "$label ($count)",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalBarChart(
    String title,
    List<MapEntry<String, int>> data,
    Color color,
    bool isDark,
  ) {
    int maxVal = data.isEmpty ? 1 : data.map((e) => e.value).reduce(max);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          if (data.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  "No records available.",
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ...data.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          e.value.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: e.value / maxVal,
                        backgroundColor: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade100,
                        color: color,
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthlyMaintenanceChart(
    List<int> maintenance,
    List<int> repairs,
    bool isDark,
  ) {
    final maxValue = max(1, max(maintenance.reduce(max), repairs.reduce(max)));
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monthly Maintenance & Repairs',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _analyticsLegend('Maintenance', const Color(0xFFEF4444), isDark),
              const SizedBox(width: 16),
              _analyticsLegend('Repairs', const Color(0xFFF97316), isDark),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            width: double.infinity,
            child: CustomPaint(
              painter: _MonthlyMaintenancePainter(
                maintenance: maintenance,
                repairs: repairs,
                maxValue: maxValue,
                monthNames: _monthNames,
                isDark: isDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _analyticsLegend(String label, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

class _MonthlyMaintenancePainter extends CustomPainter {
  final List<int> maintenance;
  final List<int> repairs;
  final int maxValue;
  final List<String> monthNames;
  final bool isDark;

  _MonthlyMaintenancePainter({
    required this.maintenance,
    required this.repairs,
    required this.maxValue,
    required this.monthNames,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 28.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final gridPaint = Paint()
      ..color = isDark ? Colors.grey.shade700 : Colors.grey.shade200
      ..strokeWidth = 1;
    final maintenancePaint = Paint()..color = const Color(0xFFEF4444);
    final repairPaint = Paint()..color = const Color(0xFFF97316);
    final labelStyle = TextStyle(
      fontSize: 9,
      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
    );

    for (var line = 0; line <= 3; line++) {
      final y = top + chartHeight * line / 3;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
    }

    final groupWidth = chartWidth / 12;
    final barWidth = groupWidth * 0.22;
    for (var index = 0; index < 12; index++) {
      final center = left + groupWidth * (index + 0.5);
      final maintenanceHeight = chartHeight * maintenance[index] / maxValue;
      final repairHeight = chartHeight * repairs[index] / maxValue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            center - barWidth - 1,
            top + chartHeight - maintenanceHeight,
            barWidth,
            maintenanceHeight,
          ),
          const Radius.circular(3),
        ),
        maintenancePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            center + 1,
            top + chartHeight - repairHeight,
            barWidth,
            repairHeight,
          ),
          const Radius.circular(3),
        ),
        repairPaint,
      );
      final label = monthNames[index].substring(0, 1);
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(center - painter.width / 2, size.height - 20),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyMaintenancePainter oldDelegate) =>
      oldDelegate.maintenance != maintenance ||
      oldDelegate.repairs != repairs ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.isDark != isDark;
}

class _TripLineChartPainter extends CustomPainter {
  final List<MapEntry<String, int>> data;
  final Color lineColor;
  final bool isDark;

  _TripLineChartPainter({
    required this.data,
    required this.lineColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final double bottomPadding = 24.0;
    final double topPadding = 18.0;
    final double chartHeight = size.height - bottomPadding - topPadding;
    final double chartWidth = size.width;

    int maxVal = data.map((e) => e.value).reduce(max);
    if (maxVal == 0) maxVal = 1;

    final gridPaint = Paint()
      ..color = isDark ? Colors.grey.shade800 : Colors.grey.shade200
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i++) {
      double y = topPadding + (chartHeight / 3) * i;
      canvas.drawLine(Offset(0, y), Offset(chartWidth, y), gridPaint);
    }

    final double stepX = data.length > 1
        ? chartWidth / (data.length - 1)
        : chartWidth / 2;
    List<Offset> points = [];
    for (int i = 0; i < data.length; i++) {
      double x = data.length == 1 ? chartWidth / 2 : i * stepX;
      double normalizedY = data[i].value / maxVal;
      double y = topPadding + (chartHeight * (1.0 - normalizedY));
      points.add(Offset(x, y));
    }

    Path fillPath = Path();
    fillPath.moveTo(points.first.dx, size.height - bottomPadding);
    fillPath.lineTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      Offset p0 = points[i];
      Offset p1 = points[i + 1];
      double midX = (p0.dx + p1.dx) / 2;
      fillPath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }
    fillPath.lineTo(points.last.dx, size.height - bottomPadding);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.35),
          lineColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, topPadding, chartWidth, chartHeight));
    canvas.drawPath(fillPath, fillPaint);

    Path path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      Offset p0 = points[i];
      Offset p1 = points[i + 1];
      double midX = (p0.dx + p1.dx) / 2;
      path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : Colors.white;
    final dotBorderPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      Offset pt = points[i];
      canvas.drawCircle(pt, 4.0, dotPaint);
      canvas.drawCircle(pt, 4.0, dotBorderPaint);

      TextPainter valPainter = TextPainter(
        text: TextSpan(
          text: data[i].value.toString(),
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valPainter.paint(
        canvas,
        Offset(pt.dx - (valPainter.width / 2), pt.dy - 14),
      );

      TextPainter labelPainter = TextPainter(
        text: TextSpan(
          text: data[i].key,
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            fontSize: 9.0,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(
          pt.dx - (labelPainter.width / 2),
          size.height - bottomPadding + 6,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TripLineChartPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.isDark != isDark;
}
