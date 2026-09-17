import 'dart:convert';
import 'dart:math'; // Added for pagination math
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';

class RouteOptimizationTab extends StatefulWidget {
  final String backendUrl;
  final VoidCallback onSyncAction;

  const RouteOptimizationTab({
    super.key,
    required this.backendUrl,
    required this.onSyncAction,
  });

  @override
  State<RouteOptimizationTab> createState() => _RouteOptimizationTabState();
}

class _RouteOptimizationTabState extends State<RouteOptimizationTab> {
  bool _isLoading = true;
  Map<String, dynamic>? _mlPayload;

  // Filter States
  String _timeFilter = 'all'; // 'all', 'today', 'week', 'month', 'date'
  DateTime? _customDate;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  // UI Interactive States
  int? _selectedClusterId;
  String _tripSearchQuery = '';

  // Pagination States
  int _currentPage = 0;
  final int _itemsPerPage = 10;

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

  @override
  void initState() {
    super.initState();
    _fetchClusterData();
  }

  Future<void> _fetchClusterData() async {
    setState(() => _isLoading = true);
    try {
      String queryParams = 'filter=$_timeFilter';
      if (_timeFilter == 'date' && _customDate != null) {
        final dStr =
            '${_customDate!.year}-${_customDate!.month.toString().padLeft(2, '0')}-${_customDate!.day.toString().padLeft(2, '0')}';
        queryParams += '&date=$dStr';
      } else if (_timeFilter == 'month') {
        queryParams += '&month=$_selectedMonth&year=$_selectedYear';
      }

      final baseUrl = widget.backendUrl.endsWith('/')
          ? widget.backendUrl.substring(0, widget.backendUrl.length - 1)
          : widget.backendUrl;

      final res = await http.get(
        Uri.parse('$baseUrl/routes/cluster?$queryParams'),
      );

      if (res.statusCode == 200 && mounted) {
        setState(() {
          _mlPayload = jsonDecode(res.body);
          _selectedClusterId = null;
          _currentPage = 0; // Reset pagination on new data
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Cluster fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getClusterColor(String label) {
    if (label.contains('Optimal')) return const Color(0xFF10B981);
    if (label.contains('Departure')) return const Color(0xFFF97316);
    if (label.contains('Transit') || label.contains('Traffic')) {
      return const Color(0xFF3B82F6);
    }
    return const Color(0xFFEF4444);
  }

  IconData _getClusterIcon(String label) {
    if (label.contains('Optimal')) return Icons.check_circle_outline;
    if (label.contains('Departure')) return Icons.garage_outlined;
    if (label.contains('Transit') || label.contains('Traffic')) {
      return Icons.traffic_outlined;
    }
    return Icons.warning_amber_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 700;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    final clusters = _mlPayload?['clusters'] ?? [];
    final recommendations = _mlPayload?['recommendations'] ?? [];
    final allTrips = (_mlPayload?['trips'] as List<dynamic>?) ?? [];

    final filteredTrips = allTrips.where((t) {
      final matchesCluster =
          _selectedClusterId == null || t['cluster_id'] == _selectedClusterId;
      final q = _tripSearchQuery.toLowerCase();
      final matchesQuery =
          q.isEmpty ||
          (t['route_name'] ?? '').toString().toLowerCase().contains(q) ||
          (t['driver_name'] ?? '').toString().toLowerCase().contains(q) ||
          (t['plate_number'] ?? '').toString().toLowerCase().contains(q) ||
          (t['trip_id'] ?? '').toString().toLowerCase().contains(q);
      return matchesCluster && matchesQuery;
    }).toList();

    return Skeletonizer(
      enabled: _isLoading,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildRouteHeader(textColor, isDark),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton.filledTonal(
                          onPressed: _fetchClusterData,
                          icon: const Icon(Icons.sync, size: 20),
                          tooltip: 'Recalculate Model',
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: _buildRouteHeader(textColor, isDark)),
                      IconButton.filledTonal(
                        onPressed: _fetchClusterData,
                        icon: const Icon(Icons.sync, size: 20),
                        tooltip: 'Recalculate Model',
                      ),
                    ],
                  ),
            const SizedBox(height: 20),

            _buildFilterToolbar(isDark, cardBg),
            const SizedBox(height: 24),

            if (!_isLoading &&
                (_mlPayload == null ||
                    _mlPayload!['status'] == 'Insufficient Data'))
              _buildInsufficientDataCard(cardBg, textColor)
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 900;
                  return isMobile
                      ? Column(
                          children: clusters
                              .map<Widget>(
                                (c) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildClusterCard(c, isDark),
                                ),
                              )
                              .toList(),
                        )
                      : Row(
                          children: clusters
                              .map<Widget>(
                                (c) => Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: c == clusters.last ? 0 : 16,
                                    ),
                                    child: _buildClusterCard(c, isDark),
                                  ),
                                ),
                              )
                              .toList(),
                        );
                },
              ),
              const SizedBox(height: 32),

              Text(
                "Actionable Dispatch Recommendations",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 12),
              _buildRecommendationsView(recommendations, isDark, cardBg),
              const SizedBox(height: 32),

              _buildTripBreakdownSection(
                filteredTrips,
                isDark,
                cardBg,
                textColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRouteHeader(Color textColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'K-Means Route Delay Clusters',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          'Unsupervised grouping of schedule variances and route anomalies.',
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
            fontSize: 13,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildFilterToolbar(bool isDark, Color cardBg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(
            Icons.filter_list_rounded,
            size: 20,
            color: Color(0xFF64748B),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All Time')),
                ButtonSegment(value: 'today', label: Text('Today')),
                ButtonSegment(value: 'week', label: Text('This Week')),
                ButtonSegment(value: 'month', label: Text('Month')),
                ButtonSegment(value: 'date', label: Text('Specific Day')),
              ],
              selected: {_timeFilter},
              onSelectionChanged: (val) {
                setState(() => _timeFilter = val.first);
                if (_timeFilter == 'date' && _customDate == null) {
                  _pickCustomDate();
                } else {
                  _fetchClusterData();
                }
              },
            ),
          ),
          if (_timeFilter == 'month') ...[
            DropdownButton<int>(
              value: _selectedMonth,
              items: List.generate(
                12,
                (i) =>
                    DropdownMenuItem(value: i + 1, child: Text(_monthNames[i])),
              ),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedMonth = val);
                  _fetchClusterData();
                }
              },
            ),
            DropdownButton<int>(
              value: _selectedYear,
              items: [2025, 2026, 2027]
                  .map(
                    (y) =>
                        DropdownMenuItem(value: y, child: Text(y.toString())),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedYear = val);
                  _fetchClusterData();
                }
              },
            ),
          ],
          if (_timeFilter == 'date')
            ActionChip(
              avatar: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                _customDate == null
                    ? "Pick Date"
                    : "${_customDate!.year}-${_customDate!.month.toString().padLeft(2, '0')}-${_customDate!.day.toString().padLeft(2, '0')}",
              ),
              onPressed: _pickCustomDate,
            ),
        ],
      ),
    );
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2027),
    );
    if (picked != null) {
      setState(() => _customDate = picked);
      _fetchClusterData();
    }
  }

  Widget _buildClusterCard(Map<String, dynamic> cluster, bool isDark) {
    final int clusterId = cluster['cluster_id'];
    final String label = cluster['label'];
    final bool isSelected = _selectedClusterId == clusterId;
    final Color themeColor = _getClusterColor(label);
    final IconData icon = _getClusterIcon(label);

    return InkWell(
      onTap: () {
        setState(() {
          _selectedClusterId = isSelected ? null : clusterId;
          _currentPage = 0; // Reset pagination when filter changes
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? themeColor
                : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: themeColor.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themeColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: themeColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              cluster['description'] ?? '',
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
                fontSize: 12,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Divider(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
            ),
            const SizedBox(height: 8),
            _statRow("Trip Volume", "${cluster['count']} trips", isDark),
            _statRow(
              "Avg Departure Delay",
              "${cluster['avg_departure_delay_mins']} min",
              isDark,
            ),
            _statRow(
              "Avg Arrival Delay",
              "${cluster['avg_arrival_delay_mins']} min",
              isDark,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                isSelected ? "✓ Active Filter" : "Click to isolate trips",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? themeColor : Colors.grey.shade400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationsView(
    List<dynamic> recommendations,
    bool isDark,
    Color cardBg,
  ) {
    if (recommendations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
        child: const Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF10B981)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'All routes operating within optimal schedule thresholds.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: recommendations.map<Widget>((r) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lightbulb, color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['route'],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      "${r['insight']} → ${r['action']}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTripBreakdownSection(
    List<dynamic> trips,
    bool isDark,
    Color cardBg,
    Color textColor,
  ) {
    // Math for Pagination
    int totalPages = max(1, (trips.length / _itemsPerPage).ceil());
    int startIndex = _currentPage * _itemsPerPage;
    int endIndex = min(startIndex + _itemsPerPage, trips.length);
    List<dynamic> paginatedTrips = trips.isEmpty
        ? []
        : trips.sublist(startIndex, endIndex);

    final isMobile = MediaQuery.of(context).size.width < 700;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTripBreakdownTitle(trips, isDark, textColor),
                      const SizedBox(height: 12),
                      _buildTripSearchField(isDark),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildTripBreakdownTitle(
                          trips,
                          isDark,
                          textColor,
                        ),
                      ),
                      _buildTripSearchField(isDark),
                    ],
                  ),
          ),
          Divider(
            height: 1,
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),

          if (trips.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text("No trips match the current criteria."),
              ),
            )
          else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: paginatedTrips.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              ),
              itemBuilder: (context, idx) {
                final t = paginatedTrips[idx];
                final String label = t['cluster_label'] ?? 'Cluster';
                final Color themeColor = _getClusterColor(label);

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: themeColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: themeColor.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TRIP-${t['trip_id'] ?? 'N/A'} • ${t['route_name'] ?? 'Route'}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            Text(
                              "${t['schedule_date']} • ${t['driver_name']} (${t['plate_number']})",
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Depart Delay: ${t['dep_delay']} min",
                              style: TextStyle(
                                fontSize: 12,
                                color: t['dep_delay'] > 15
                                    ? const Color(0xFFEF4444)
                                    : (isDark
                                          ? Colors.grey.shade300
                                          : Colors.black87),
                              ),
                            ),
                            Text(
                              "Arrival Delay: ${t['arr_delay']} min",
                              style: TextStyle(
                                fontSize: 12,
                                color: t['arr_delay'] > 20
                                    ? const Color(0xFFEF4444)
                                    : (isDark
                                          ? Colors.grey.shade300
                                          : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "${t['duration']} mins",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // --- PAGINATION FOOTER CONTROLS ---
            Divider(
              height: 1,
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${startIndex + 1} - $endIndex of ${trips.length} trips',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : const Color(0xFF64748B),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        splashRadius: 20,
                        onPressed: _currentPage > 0
                            ? () => setState(() => _currentPage--)
                            : null,
                        color: _currentPage > 0
                            ? const Color(0xFF3B82F6)
                            : Theme.of(context).disabledColor,
                      ),
                      Text(
                        'Page ${_currentPage + 1} of $totalPages',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        splashRadius: 20,
                        onPressed: _currentPage < totalPages - 1
                            ? () => setState(() => _currentPage++)
                            : null,
                        color: _currentPage < totalPages - 1
                            ? const Color(0xFF3B82F6)
                            : Theme.of(context).disabledColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTripBreakdownTitle(
    List<dynamic> trips,
    bool isDark,
    Color textColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Classified Trip Breakdown (${trips.length})',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          _selectedClusterId != null
              ? 'Showing isolated cluster trips'
              : 'Showing all trips across all delay clusters',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildTripSearchField(bool isDark) {
    return SizedBox(
      width: MediaQuery.of(context).size.width < 700 ? double.infinity : 240,
      height: 38,
      child: TextField(
        onChanged: (v) => setState(() {
          _tripSearchQuery = v;
          _currentPage = 0;
        }),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search route, driver, plate...',
          prefixIcon: const Icon(Icons.search, size: 18),
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildInsufficientDataCard(Color cardBg, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.bubble_chart_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            "Insufficient Data for This Timeframe",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _mlPayload?['message'] ??
                "At least 3 completed trips with actual timestamps are required to generate clusters.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
