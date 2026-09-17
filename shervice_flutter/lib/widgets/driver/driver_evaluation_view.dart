import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DriverEvaluationView extends StatefulWidget {
  final String driverUuid;
  final String backendUrl;

  const DriverEvaluationView({
    super.key,
    required this.driverUuid,
    required this.backendUrl,
  });

  @override
  State<DriverEvaluationView> createState() => _DriverEvaluationViewState();
}

class _DriverEvaluationViewState extends State<DriverEvaluationView> {
  bool _isLoading = true;
  String? _errorMessage;
  int? _expandedIndex;

  List<dynamic> _rawEvals = [];

  // --- Clean Inline Filter State ---
  int? _selectedYear;
  int? _selectedMonth;

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

  double _overallRating = 0.0;
  double _punctualityAvg = 0.0;
  double _safetyAvg = 0.0;
  double _professionalismAvg = 0.0;
  int _filteredEvaluationCount = 0;

  String _mlClassification = 'Analyzing...';
  Color _mlBadgeColor = const Color(0xFF64748B);
  IconData _mlIcon = Icons.analytics_outlined;

  List<Map<String, dynamic>> _groupedTrips = [];

  int _currentPage = 0;
  final int _itemsPerPage = 5;
  String _currentSort = 'Date (Newest)';
  final List<String> _sortOptions = [
    'Date (Newest)',
    'Date (Oldest)',
    'Highest Rating',
    'Lowest Rating',
  ];

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _selectedMonth = DateTime.now().month;
    _fetchEvaluations();
  }

  Future<void> _fetchEvaluations() async {
    try {
      final res = await http.get(
        Uri.parse('${widget.backendUrl}/evaluate/driver/${widget.driverUuid}'),
      );

      if (mounted) {
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          _rawEvals = data['data'] ?? data['evaluations'] ?? [];

          Set<int> years = {DateTime.now().year};
          for (var e in _rawEvals) {
            DateTime? dt = DateTime.tryParse(
              (e['submit_date'] ?? e['created_at'] ?? '').toString(),
            );
            if (dt != null) years.add(dt.year);
          }
          _availableYears = years.toList()..sort((a, b) => b.compareTo(a));

          _recomputeForHorizon();
        } else if (res.statusCode == 404) {
          setState(() {
            _rawEvals = [];
            _groupedTrips = [];
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Failed to load evaluations.';
            _isLoading = false;
          });
        }
      }

      try {
        final mlRes = await http.get(
          Uri.parse(
            '${widget.backendUrl}/drivers/classify/${widget.driverUuid}?cb=${DateTime.now().millisecondsSinceEpoch}',
          ),
        );
        if (mlRes.statusCode == 200 && mounted) {
          final mlData = jsonDecode(mlRes.body);
          final String classification =
              mlData['classification'] ?? 'Insufficient Data';
          Color badgeColor = const Color(0xFF64748B);
          IconData badgeIcon = Icons.info_outline;

          if (classification == 'Consistent Performer') {
            badgeColor = const Color(0xFF10B981);
            badgeIcon = Icons.verified;
          } else if (classification == 'Aggressive Driving Risk' ||
              classification == 'Needs Review') {
            badgeColor = const Color(0xFFEF4444);
            badgeIcon = Icons.warning_amber_rounded;
          } else if (classification == 'Tardiness Risk' ||
              classification == 'Unprofessional Conduct') {
            badgeColor = const Color(0xFFF97316);
            badgeIcon = Icons.access_time_filled;
          }
          setState(() {
            _mlClassification = classification;
            _mlBadgeColor = badgeColor;
            _mlIcon = badgeIcon;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _mlClassification = 'Network Error');
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _errorMessage = 'Network error.';
          _isLoading = false;
        });
    }
  }

  void _recomputeForHorizon() {
    List<dynamic> targetEvals = _rawEvals.where((e) {
      if (_selectedYear == null) return true; // All Time
      DateTime? dt = DateTime.tryParse(
        (e['submit_date'] ?? e['created_at'] ?? '').toString(),
      );
      if (dt == null) return false;
      if (_selectedMonth == null)
        return dt.year == _selectedYear; // Entire Year
      return dt.year == _selectedYear &&
          dt.month == _selectedMonth; // Specific Month
    }).toList();

    _filteredEvaluationCount = targetEvals.length;
    double cumTotalScore = 0.0, cumPunct = 0.0, cumSafe = 0.0, cumProf = 0.0;

    Map<String, List<dynamic>> tripGroups = {};
    for (var e in targetEvals) {
      final p = (e['punctuality_score'] as num?)?.toDouble() ?? 5.0;
      final s = (e['safety_score'] as num?)?.toDouble() ?? 5.0;
      final pr = (e['professionalism_score'] as num?)?.toDouble() ?? 5.0;
      cumPunct += p;
      cumSafe += s;
      cumProf += pr;
      cumTotalScore += (p + s + pr) / 3.0;

      String tripId = e['trip_id']?.toString() ?? 'Unassigned';
      tripGroups.putIfAbsent(tripId, () => []).add(e);
    }

    List<Map<String, dynamic>> compiledTrips = [];
    for (var entry in tripGroups.entries) {
      final tId = entry.key;
      final tripEvals = entry.value;
      double tPunct = 0.0, tSafe = 0.0, tProf = 0.0;
      for (var te in tripEvals) {
        tPunct += (te['punctuality_score'] as num?)?.toDouble() ?? 5.0;
        tSafe += (te['safety_score'] as num?)?.toDouble() ?? 5.0;
        tProf += (te['professionalism_score'] as num?)?.toDouble() ?? 5.0;
      }
      int tCount = tripEvals.length;
      compiledTrips.add({
        'trip_id': tId,
        'date': tripEvals.first['submit_date'] ?? 'Unknown Date',
        'eval_count': tCount,
        'avg_punctuality': tPunct / tCount,
        'avg_safety': tSafe / tCount,
        'avg_professionalism': tProf / tCount,
        'overall_avg': ((tPunct + tSafe + tProf) / tCount) / 3.0,
        'passenger_reviews': tripEvals,
      });
    }

    setState(() {
      _overallRating = _filteredEvaluationCount == 0
          ? 0.0
          : (cumTotalScore / _filteredEvaluationCount);
      _punctualityAvg = _filteredEvaluationCount == 0
          ? 0.0
          : (cumPunct / _filteredEvaluationCount);
      _safetyAvg = _filteredEvaluationCount == 0
          ? 0.0
          : (cumSafe / _filteredEvaluationCount);
      _professionalismAvg = _filteredEvaluationCount == 0
          ? 0.0
          : (cumProf / _filteredEvaluationCount);

      _groupedTrips = compiledTrips;
      _currentPage = 0;
      _expandedIndex = null;
      _applySort();
      _isLoading = false;
    });
  }

  void _applySort() {
    _groupedTrips.sort((a, b) {
      if (_currentSort.contains('Date')) {
        DateTime dateA =
            DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
        DateTime dateB =
            DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
        return _currentSort == 'Date (Newest)'
            ? dateB.compareTo(dateA)
            : dateA.compareTo(dateB);
      } else {
        double scoreA = a['overall_avg'] ?? 0.0;
        double scoreB = b['overall_avg'] ?? 0.0;
        return _currentSort == 'Highest Rating'
            ? scoreB.compareTo(scoreA)
            : scoreA.compareTo(scoreB);
      }
    });
  }

  void _onSortChanged(String? newValue) {
    if (newValue != null && newValue != _currentSort) {
      setState(() {
        _currentSort = newValue;
        _currentPage = 0;
        _expandedIndex = null;
        _applySort();
      });
    }
  }

  int get _totalPages => max(1, (_groupedTrips.length / _itemsPerPage).ceil());
  List<Map<String, dynamic>> get _paginatedTrips {
    if (_groupedTrips.isEmpty) return [];
    int start = _currentPage * _itemsPerPage;
    return _groupedTrips.sublist(
      start,
      min(start + _itemsPerPage, _groupedTrips.length),
    );
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1)
      setState(() {
        _currentPage++;
        _expandedIndex = null;
      });
  }

  void _prevPage() {
    if (_currentPage > 0)
      setState(() {
        _currentPage--;
        _expandedIndex = null;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    if (_errorMessage != null)
      return Center(
        child: Text(
          _errorMessage!,
          style: TextStyle(color: theme.colorScheme.error),
        ),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- INLINE DROPDOWN FILTERS ---
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedYear != null) ...[
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedMonth,
                        dropdownColor: isDark
                            ? const Color(0xFF1E293B)
                            : Colors.white,
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
                            value: null,
                            child: Text("All Months"),
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
                          setState(() => _selectedMonth = val);
                          _recomputeForHorizon();
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
                  ],
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedYear,
                      dropdownColor: isDark
                          ? const Color(0xFF1E293B)
                          : Colors.white,
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
                          value: null,
                          child: Text("All Time"),
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
                          _selectedYear = val;
                          if (val == null) _selectedMonth = null;
                        });
                        _recomputeForHorizon();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // --- SCORE CARD ---
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.blue.withOpacity(0.05)
                : theme.colorScheme.primaryContainer.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.blue.withOpacity(0.2)
                  : theme.colorScheme.primary.withOpacity(0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                children: [
                  Text(
                    _overallRating.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.blue.shade300
                          : Colors.blue.shade900,
                      height: 1,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (index) => Icon(
                        index < _overallRating.round()
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_filteredEvaluationCount Review${_filteredEvaluationCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: isDark
                          ? Colors.blue.shade400
                          : Colors.blue.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _mlBadgeColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _mlBadgeColor.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_mlIcon, color: _mlBadgeColor, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          _mlClassification.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: _mlBadgeColor,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildMetricBar('Safety Avg', _safetyAvg, isDark),
                    const SizedBox(height: 8),
                    _buildMetricBar('Punctuality Avg', _punctualityAvg, isDark),
                    const SizedBox(height: 8),
                    _buildMetricBar(
                      'Professionalism Avg',
                      _professionalismAvg,
                      isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // --- SORTING & HEADER ROW ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TRIP LOGS (${_groupedTrips.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
              ),
            ),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border.all(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _currentSort,
                  dropdownColor: theme.cardColor,
                  icon: Icon(
                    Icons.sort,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  items: _sortOptions
                      .map(
                        (String opt) =>
                            DropdownMenuItem(value: opt, child: Text(opt)),
                      )
                      .toList(),
                  onChanged: _onSortChanged,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // --- TRIP LIST ---
        Expanded(
          child: _groupedTrips.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.rate_review_outlined,
                        size: 48,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No evaluations found.',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _paginatedTrips.length,
                  itemBuilder: (context, index) {
                    final trip = _paginatedTrips[index];
                    final bool isExpanded = _expandedIndex == index;
                    final String tripId = trip['trip_id'] == 'Unassigned'
                        ? 'Unassigned Trip'
                        : '#TRP-${trip['trip_id']}';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isExpanded
                              ? const Color(0xFF3B82F6)
                              : (isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade300),
                          width: isExpanded ? 1.5 : 1.0,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(
                          () => _expandedIndex = isExpanded ? null : index,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF3B82F6,
                                          ).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.directions_bus,
                                          size: 18,
                                          color: Color(0xFF3B82F6),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tripId,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${trip['date']} • ${trip['eval_count']} review(s)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.grey.shade400
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.green.withOpacity(0.15)
                                              : Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              trip['overall_avg']
                                                  .toStringAsFixed(1),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: isDark
                                                    ? Colors.green.shade400
                                                    : Colors.green,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.star,
                                              color: isDark
                                                  ? Colors.green.shade400
                                                  : Colors.green,
                                              size: 14,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Icon(
                                        isExpanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        color: isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (isExpanded) ...[
                                const SizedBox(height: 16),
                                Divider(
                                  height: 1,
                                  color: isDark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade200,
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildMiniTripScore(
                                      'Trip Safety',
                                      trip['avg_safety'],
                                      isDark,
                                    ),
                                    _buildMiniTripScore(
                                      'Trip Punctuality',
                                      trip['avg_punctuality'],
                                      isDark,
                                    ),
                                    _buildMiniTripScore(
                                      'Trip Professionalism',
                                      trip['avg_professionalism'],
                                      isDark,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'PASSENGER REVIEWS (${trip['eval_count']})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.grey.shade500
                                        : Colors.grey.shade400,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...(trip['passenger_reviews'] as List).map((
                                  review,
                                ) {
                                  final double indAvg =
                                      (((review['safety_score'] as num?)
                                                  ?.toDouble() ??
                                              5.0) +
                                          ((review['punctuality_score'] as num?)
                                                  ?.toDouble() ??
                                              5.0) +
                                          ((review['professionalism_score']
                                                      as num?)
                                                  ?.toDouble() ??
                                              5.0)) /
                                      3;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF1E293B)
                                          : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.grey.shade800
                                            : Colors.grey.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withOpacity(
                                              0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            '${indAvg.toStringAsFixed(1)} ★',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            review['comments']
                                                    ?.toString()
                                                    .trim() ??
                                                'No commentary provided.',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontStyle: FontStyle.italic,
                                              color: isDark
                                                  ? Colors.grey.shade300
                                                  : const Color(0xFF334155),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // --- PAGINATION CONTROLS ---
        if (_totalPages > 0)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${(_currentPage * _itemsPerPage) + 1} - ${min((_currentPage + 1) * _itemsPerPage, _groupedTrips.length)} of ${_groupedTrips.length} trips',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _currentPage > 0 ? _prevPage : null,
                      color: _currentPage > 0
                          ? theme.colorScheme.primary
                          : theme.disabledColor,
                    ),
                    Text(
                      'Page ${_currentPage + 1} of $_totalPages',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _currentPage < _totalPages - 1
                          ? _nextPage
                          : null,
                      color: _currentPage < _totalPages - 1
                          ? theme.colorScheme.primary
                          : theme.disabledColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMiniTripScore(String label, double score, bool isDark) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              score.toStringAsFixed(1),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                5,
                (i) => Icon(
                  i < score.round() ? Icons.star : Icons.star_border,
                  size: 14,
                  color: i < score.round()
                      ? Colors.amber.shade600
                      : Colors.grey.shade400,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricBar(String label, double average, bool isDark) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.blue.shade200 : Colors.blue.shade900,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: average / 5,
              backgroundColor: isDark ? Colors.grey.shade800 : Colors.white,
              color: Colors.amber,
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 24,
          child: Text(
            average.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.blue.shade200 : Colors.blue.shade900,
            ),
          ),
        ),
      ],
    );
  }
}
