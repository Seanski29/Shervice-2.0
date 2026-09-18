import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DriverEvaluationView extends StatefulWidget {
  final String driverId;
  final String backendUrl;

  const DriverEvaluationView({
    super.key,
    required this.driverId,
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
  List<dynamic> _rawTrips = [];
  List<dynamic> _rawAttendance = [];

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
  int _filteredTripCount = 0;

  int _presentCount = 0;
  int _halfDayCount = 0;
  int _absentCount = 0;
  int _totalMinutesLate = 0;

  String _mlClassification = 'Analyzing...';
  Color _mlBadgeColor = const Color(0xFF64748B);
  IconData _mlIcon = Icons.analytics_outlined;

  List<Map<String, dynamic>> _processedEvals = [];

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
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final evalRes = await http.get(
        Uri.parse('${widget.backendUrl}/evaluate/driver/${widget.driverId}'),
      );

      final tripsRes = await http.get(
        Uri.parse('${widget.backendUrl}/schedules/driver/${widget.driverId}'),
      );

      // Fetch Attendance Data
      String attendanceUrl = widget.backendUrl.contains('/api')
          ? '${widget.backendUrl}/admin/attendance'
          : '${widget.backendUrl}/api/admin/attendance';

      final attendanceRes = await http.get(Uri.parse(attendanceUrl));

      if (mounted) {
        if (evalRes.statusCode == 200) {
          final data = jsonDecode(evalRes.body);
          _rawEvals = data['data'] ?? data['evaluations'] ?? [];
        }
        if (tripsRes.statusCode == 200) {
          final data = jsonDecode(tripsRes.body);
          _rawTrips = data['data'] ?? [];
        }
        if (attendanceRes.statusCode == 200) {
          final data = jsonDecode(attendanceRes.body);
          final allAttendance = data['data'] ?? data['attendance'] ?? [];
          // Filter to only this driver's attendance
          _rawAttendance = allAttendance
              .where((a) => a['driver_id'].toString() == widget.driverId)
              .toList();
        }

        Set<int> years = {DateTime.now().year};

        for (var e in _rawEvals) {
          DateTime? dt = DateTime.tryParse(
            (e['submit_date'] ?? e['created_at'] ?? '').toString(),
          );
          if (dt != null) years.add(dt.year);
        }
        for (var t in _rawTrips) {
          DateTime? dt = DateTime.tryParse(
            (t['schedule_date'] ?? t['date'] ?? '').toString(),
          );
          if (dt != null) years.add(dt.year);
        }
        for (var a in _rawAttendance) {
          DateTime? dt = DateTime.tryParse(
            (a['work_date'] ?? a['date'] ?? '').toString(),
          );
          if (dt != null) years.add(dt.year);
        }

        _availableYears = years.toList()..sort((a, b) => b.compareTo(a));
        _recomputeForHorizon();
      }

      try {
        final mlRes = await http.get(
          Uri.parse(
            '${widget.backendUrl}/drivers/classify/${widget.driverId}?cb=${DateTime.now().millisecondsSinceEpoch}',
          ),
        );
        if (mlRes.statusCode == 200 && mounted) {
          final mlData = jsonDecode(mlRes.body);
          final String classification =
              mlData['classification'] ?? 'Insufficient Data';
          Color badgeColor = const Color(0xFF64748B);
          IconData badgeIcon = Icons.info_outline;

          // Updated styling aligned with updated classifications
          if (classification == 'Consistent Performer' ||
              classification == 'Elite Performer') {
            badgeColor = const Color(0xFF10B981);
            badgeIcon = Icons.verified;
          } else if (classification == 'Aggressive Driving Risk' ||
              classification == 'Safety Risk' ||
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
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error.';
          _isLoading = false;
        });
      }
    }
  }

  void _recomputeForHorizon() {
    // 1. Filter Evaluations
    List<dynamic> targetEvals = _rawEvals.where((e) {
      if (_selectedYear == null) return true;
      DateTime? dt = DateTime.tryParse(
        (e['submit_date'] ?? e['created_at'] ?? '').toString(),
      );
      if (dt == null) return false;
      if (_selectedMonth == null) return dt.year == _selectedYear;
      return dt.year == _selectedYear && dt.month == _selectedMonth;
    }).toList();

    // 2. Filter Trips
    _filteredTripCount = _rawTrips.where((t) {
      if (_selectedYear == null) return true;
      DateTime? dt = DateTime.tryParse(
        (t['schedule_date'] ?? t['date'] ?? '').toString(),
      );
      if (dt == null) return false;
      if (_selectedMonth == null) return dt.year == _selectedYear;
      return dt.year == _selectedYear && dt.month == _selectedMonth;
    }).length;

    // 3. Filter and Calculate Attendance
    List<dynamic> targetAttendance = _rawAttendance.where((a) {
      if (_selectedYear == null) return true;
      DateTime? dt = DateTime.tryParse(
        (a['work_date'] ?? a['date'] ?? '').toString(),
      );
      if (dt == null) return false;
      if (_selectedMonth == null) return dt.year == _selectedYear;
      return dt.year == _selectedYear && dt.month == _selectedMonth;
    }).toList();

    int tempPresent = 0;
    int tempHalf = 0;
    int tempAbsent = 0;
    int tempLateMins = 0;

    for (var a in targetAttendance) {
      String note = (a['note'] ?? '').toString().toLowerCase();
      int lateMins = (a['total_minutes_late'] as num?)?.toInt() ?? 0;
      tempLateMins += lateMins;

      if (note.contains('absent')) {
        tempAbsent++;
      } else if (note.contains('half day')) {
        tempHalf++;
      } else {
        tempPresent++;
      }
    }

    _filteredEvaluationCount = targetEvals.length;
    double cumTotalScore = 0.0, cumPunct = 0.0, cumSafe = 0.0, cumProf = 0.0;

    List<Map<String, dynamic>> compiledEvals = [];

    for (var e in targetEvals) {
      final p = (e['punctuality_score'] as num?)?.toDouble() ?? 5.0;
      final s = (e['safety_score'] as num?)?.toDouble() ?? 5.0;
      final pr = (e['professionalism_score'] as num?)?.toDouble() ?? 5.0;

      cumPunct += p;
      cumSafe += s;
      cumProf += pr;
      cumTotalScore += (p + s + pr) / 3.0;

      compiledEvals.add({
        'eval_id': e['evaluation_id']?.toString() ?? 'N/A',
        'date': e['submit_date'] ?? 'Unknown Date',
        'overall_avg': (p + s + pr) / 3.0,
        'avg_punctuality': p,
        'avg_safety': s,
        'avg_professionalism': pr,
        'comments':
            e['comments']?.toString().trim() ?? 'No commentary provided.',
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

      _presentCount = tempPresent;
      _halfDayCount = tempHalf;
      _absentCount = tempAbsent;
      _totalMinutesLate = tempLateMins;

      _processedEvals = compiledEvals;
      _currentPage = 0;
      _expandedIndex = null;
      _applySort();
      _isLoading = false;
    });
  }

  void _applySort() {
    _processedEvals.sort((a, b) {
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

  void _openSubmitEvaluationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StaffSubmitEvaluationDialog(
        driverId: widget.driverId,
        backendUrl: widget.backendUrl,
      ),
    ).then((success) {
      if (success == true) {
        _fetchData();
      }
    });
  }

  int get _totalPages =>
      max(1, (_processedEvals.length / _itemsPerPage).ceil());
  List<Map<String, dynamic>> get _paginatedEvals {
    if (_processedEvals.isEmpty) return [];
    int start = _currentPage * _itemsPerPage;
    return _processedEvals.sublist(
      start,
      min(start + _itemsPerPage, _processedEvals.length),
    );
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      setState(() {
        _currentPage++;
        _expandedIndex = null;
      });
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
        _expandedIndex = null;
      });
    }
  }

  Widget _buildAttendanceStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? color.withOpacity(0.1) : color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: TextStyle(color: theme.colorScheme.error),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton.icon(
              onPressed: _openSubmitEvaluationDialog,
              icon: const Icon(
                Icons.star_rate_rounded,
                color: Colors.white,
                size: 18,
              ),
              label: const Text(
                'Evaluate Driver',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
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
                  Text(
                    '$_filteredTripCount Trip${_filteredTripCount == 1 ? '' : 's'} Made',
                    style: TextStyle(
                      color: isDark
                          ? Colors.blue.shade400
                          : Colors.blue.shade700,
                      fontWeight: FontWeight.w800,
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

        const SizedBox(height: 12),

        // ATTENDANCE STATS ROW
        Row(
          children: [
            _buildAttendanceStatCard(
              'Present',
              '$_presentCount',
              Icons.check_circle_outline,
              Colors.green,
              isDark,
            ),
            const SizedBox(width: 12),
            _buildAttendanceStatCard(
              'Half Day',
              '$_halfDayCount',
              Icons.timelapse,
              Colors.orange,
              isDark,
            ),
            const SizedBox(width: 12),
            _buildAttendanceStatCard(
              'Absent',
              '$_absentCount',
              Icons.cancel_outlined,
              Colors.red,
              isDark,
            ),
            const SizedBox(width: 12),
            _buildAttendanceStatCard(
              'Mins Late',
              '$_totalMinutesLate',
              Icons.timer_off_outlined,
              Colors.deepOrange,
              isDark,
            ),
          ],
        ),

        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'EVALUATION LOGS (${_processedEvals.length})',
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

        Expanded(
          child: _processedEvals.isEmpty
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
                  itemCount: _paginatedEvals.length,
                  itemBuilder: (context, index) {
                    final eval = _paginatedEvals[index];
                    final bool isExpanded = _expandedIndex == index;

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
                                          Icons.assignment_ind,
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
                                            'Staff Evaluation',
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
                                            'Date Submitted: ${eval['date']}',
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
                                              eval['overall_avg']
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
                                      'Safety',
                                      eval['avg_safety'],
                                      isDark,
                                    ),
                                    _buildMiniTripScore(
                                      'Punctuality',
                                      eval['avg_punctuality'],
                                      isDark,
                                    ),
                                    _buildMiniTripScore(
                                      'Professionalism',
                                      eval['avg_professionalism'],
                                      isDark,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'STAFF REMARKS',
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
                                Container(
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
                                  child: Text(
                                    eval['comments'],
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
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        if (_totalPages > 0)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${(_currentPage * _itemsPerPage) + 1} - ${min((_currentPage + 1) * _itemsPerPage, _processedEvals.length)} of ${_processedEvals.length} entries',
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

class StaffSubmitEvaluationDialog extends StatefulWidget {
  final String driverId;
  final String backendUrl;

  const StaffSubmitEvaluationDialog({
    super.key,
    required this.driverId,
    required this.backendUrl,
  });

  @override
  State<StaffSubmitEvaluationDialog> createState() =>
      _StaffSubmitEvaluationDialogState();
}

class _StaffSubmitEvaluationDialogState
    extends State<StaffSubmitEvaluationDialog> {
  int _safety = 5;
  int _punctuality = 5;
  int _professionalism = 5;
  final TextEditingController _commentsController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitEvaluation() async {
    setState(() => _isSubmitting = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.backendUrl}/evaluate/staff-submit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "driver_id": widget.driverId,
          "safety_score": _safety,
          "punctuality_score": _punctuality,
          "professionalism_score": _professionalism,
          "comments": _commentsController.text.trim(),
        }),
      );

      if (res.statusCode == 200 && mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver evaluated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        final decoded = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(decoded['message'] ?? 'Failed to submit evaluation.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildStarRow(
    String label,
    int value,
    ValueChanged<int> onChanged,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Row(
            children: List.generate(5, (index) {
              return IconButton(
                onPressed: () => onChanged(index + 1),
                icon: Icon(
                  index < value ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 28,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Evaluate Driver',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Submit an internal staff evaluation for the designated operational period.',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              _buildStarRow(
                'Safety',
                _safety,
                (v) => setState(() => _safety = v),
                isDark,
              ),
              _buildStarRow(
                'Punctuality',
                _punctuality,
                (v) => setState(() => _punctuality = v),
                isDark,
              ),
              _buildStarRow(
                'Professionalism',
                _professionalism,
                (v) => setState(() => _professionalism = v),
                isDark,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _commentsController,
                maxLines: 3,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Staff Remarks (Optional)',
                  labelStyle: TextStyle(
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF0F172A)
                      : Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitEvaluation,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Submit Evaluation',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }
}
