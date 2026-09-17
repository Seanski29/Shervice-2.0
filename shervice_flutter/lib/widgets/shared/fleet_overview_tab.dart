import 'dart:math';
import 'package:flutter/material.dart';

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
  // --- Clean Inline Filter State ---
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

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
    // Default to the current month and year for immediate relevance.
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    // --- Filter Data based on Dropdowns ---
    List<dynamic> fTrips = widget.trips.where((t) {
      if (_selectedYear == 0) return true; // All Time
      DateTime? d = DateTime.tryParse((t['schedule_date'] ?? '').toString());
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
    double totalDist = fTrips.fold(
      0.0,
      (s, t) => s + _parseDouble(t['route_distance']),
    );
    int totalPax = fTrips.fold(
      0,
      (s, t) =>
          s + (int.tryParse(t['passenger_count']?.toString() ?? '0') ?? 0),
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
    bool isLongTerm = _selectedMonth == 0;
    Map<String, int> timeBuckets = {};

    for (var t in fTrips) {
      String fullDate = t['schedule_date']?.toString().split(' ').first ?? '';
      if (fullDate.length >= 10) {
        String bucketKey = isLongTerm
            ? fullDate.substring(0, 7)
            : fullDate.substring(5);
        timeBuckets[bucketKey] = (timeBuckets[bucketKey] ?? 0) + 1;
      }
    }

    var sortedKeys = timeBuckets.keys.toList()..sort();
    var displayKeys = isLongTerm
        ? sortedKeys
        : (sortedKeys.reversed.take(15).toList()..sort());
    List<MapEntry<String, int>> tripVolData = displayKeys
        .map((k) => MapEntry(k, timeBuckets[k]!))
        .toList();

    Map<String, int> routeCounts = {};
    for (var t in fTrips) {
      String r = t['route_name'] ?? 'Unknown Route';
      routeCounts[r] = (routeCounts[r] ?? 0) + 1;
    }
    var sortedRoutes = routeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    List<MapEntry<String, int>> topRoutesData = sortedRoutes.take(5).toList();

    Map<String, int> maintCounts = {};
    for (var m in fMaint) {
      String c = m['category'] ?? 'General';
      maintCounts[c] = (maintCounts[c] ?? 0) + 1;
    }
    var sortedMaint = maintCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    List<MapEntry<String, int>> maintData = sortedMaint.take(5).toList();

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
                  'Total Distance',
                  '${totalDist.toStringAsFixed(0)} km',
                  Icons.route,
                  const Color(0xFF3B82F6),
                  isDark,
                ),
                _buildKpiCard(
                  'Passengers Received',
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
                  'Average CSAT',
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
                      'Trip Volume Trend',
                      tripVolData,
                      const Color(0xFF3B82F6),
                      isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildRiskDistributionBar(widget.vehicles, isDark),
                    const SizedBox(height: 16),
                    _buildHorizontalBarChart(
                      'High-Demand Routes',
                      topRoutesData,
                      const Color(0xFF8B5CF6),
                      isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildHorizontalBarChart(
                      'Maintenance Categories',
                      maintData,
                      const Color(0xFFEF4444),
                      isDark,
                    ),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildLineChart(
                            'Trip Volume Trend',
                            tripVolData,
                            const Color(0xFF3B82F6),
                            isDark,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _buildRiskDistributionBar(
                            widget.vehicles,
                            isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildHorizontalBarChart(
                              'High-Demand Routes',
                              topRoutesData,
                              const Color(0xFF8B5CF6),
                              isDark,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildHorizontalBarChart(
                              'Maintenance by Category',
                              maintData,
                              const Color(0xFFEF4444),
                              isDark,
                            ),
                          ),
                        ],
                      ),
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
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
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
                    "Trips Completed",
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
        colors: [lineColor.withOpacity(0.35), lineColor.withOpacity(0.0)],
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
