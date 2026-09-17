import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import '../../constant.dart';

class StaffTrips extends StatefulWidget {
  final String staffId;

  const StaffTrips({super.key, required this.staffId});

  @override
  State<StaffTrips> createState() => _StaffTripsState();
}

class _StaffTripsState extends State<StaffTrips> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<dynamic> _trips = [];

  String _searchTerm = '';
  String _statusFilter = 'All';
  final List<String> _statusOptions = [
    'All',
    'Scheduled',
    'Ongoing',
    'Completed',
    'Rejected', // Added
    'Expired', // Added
  ];

  String _sortOption = 'Date (Newest)';
  final List<String> _sortOptions = [
    'Date (Newest)',
    'Date (Oldest)',
    'Route Name',
  ];

  DateTime _focusedMonth = DateTime.now();
  DateTime? _filterDate;

  int _currentPage = 0;
  final int _itemsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _fetchStaffLogs();
  }

  Future<void> _fetchStaffLogs() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _isLoading = true;
    });

    try {
      final res = await http.get(
        Uri.parse('$backendUrl/schedules/staff/${widget.staffId}'),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _trips = data['data'] ?? [];
            _currentPage = 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching staff logs: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _isLoading = false;
        });
      }
    }
  }

  List<dynamic> get _filteredAndSortedTrips {
    List<dynamic> filtered = _trips.where((trip) {
      if (_filterDate != null) {
        final dateStr = trip['schedule_date']?.toString() ?? '';
        final todayStr =
            '${_filterDate!.year}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}';
        if (!dateStr.startsWith(todayStr)) return false;
      }

      if (_searchTerm.isNotEmpty) {
        final route = (trip['route_name'] ?? '').toString().toLowerCase();
        final driver = (trip['driver_name'] ?? '').toString().toLowerCase();
        final client = (trip['client_company'] ?? '').toString().toLowerCase();
        final query = _searchTerm.toLowerCase();
        if (!route.contains(query) &&
            !driver.contains(query) &&
            !client.contains(query)) {
          return false;
        }
      }

      if (_statusFilter != 'All') {
        final status = (trip['trip_status'] ?? '').toString().toLowerCase();
        if (_statusFilter == 'Rejected') {
          if (!status.contains('reject') && !status.contains('cancel'))
            return false;
        } else if (!status.contains(_statusFilter.toLowerCase())) {
          return false;
        }
      }

      return true;
    }).toList();

    switch (_sortOption) {
      case 'Date (Newest)':
        filtered.sort((a, b) {
          final da = _parseDate(a['schedule_date']);
          final db = _parseDate(b['schedule_date']);
          if (da == null || db == null) return 0;
          return db.compareTo(da);
        });
        break;
      case 'Date (Oldest)':
        filtered.sort((a, b) {
          final da = _parseDate(a['schedule_date']);
          final db = _parseDate(b['schedule_date']);
          if (da == null || db == null) return 0;
          return da.compareTo(db);
        });
        break;
      case 'Route Name':
        filtered.sort((a, b) {
          final ra = (a['route_name'] ?? '').toString().toLowerCase();
          final rb = (b['route_name'] ?? '').toString().toLowerCase();
          return ra.compareTo(rb);
        });
        break;
    }
    return filtered;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      final text = value.toString().trim();
      if (text.isEmpty) return null;
      try {
        return DateTime.parse(text.split(' ').first);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  List<dynamic> _schedulesForDate(DateTime day) {
    final dateStr =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _trips.where((trip) {
      final tripDate = trip['schedule_date']?.toString() ?? '';
      return tripDate.startsWith(dateStr);
    }).toList();
  }

  int get _totalPages =>
      (_filteredAndSortedTrips.length / _itemsPerPage).ceil();

  List<dynamic> get _paginatedTrips {
    final start = _currentPage * _itemsPerPage;
    final end = min(start + _itemsPerPage, _filteredAndSortedTrips.length);
    if (start >= _filteredAndSortedTrips.length) return [];
    return _filteredAndSortedTrips.sublist(start, end);
  }

  void _goToPage(int page) {
    if (page >= 0 && page < _totalPages) {
      setState(() => _currentPage = page);
    }
  }

  int get _totalTrips => _trips.length;
  int get _todayTrips => _trips.where((t) {
    final dateStr = t['schedule_date']?.toString() ?? '';
    final todayStr =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
    return dateStr.startsWith(todayStr);
  }).length;
  int get _scheduledTrips => _trips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase() == 'scheduled',
      )
      .length;
  int get _ongoingTrips => _trips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase() == 'ongoing',
      )
      .length;
  int get _completedTrips => _trips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase() == 'completed',
      )
      .length;

  // Added Rejected Counter
  int get _rejectedTrips => _trips.where((t) {
    final s = (t['trip_status'] ?? '').toString().toLowerCase();
    return s.contains('reject') || s.contains('cancel');
  }).length;

  // Added Expired Counter
  int get _expiredTrips => _trips.where((t) {
    final s = (t['trip_status'] ?? '').toString().toLowerCase();
    return s.contains('expired');
  }).length;

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('ongoing')) return const Color(0xFFF59E0B);
    if (s.contains('completed')) return const Color(0xFF10B981);
    if (s.contains('reject') || s.contains('cancel'))
      return const Color(0xFFEF4444);
    if (s.contains('expired'))
      return Colors.grey.shade600; // Added grey for expired
    return const Color(0xFF3B82F6);
  }

  String _monthYearFormat(DateTime date) {
    const months = [
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
    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 900;
    final double horizontalPadding = isMobile ? 12.0 : 24.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _fetchStaffLogs,
        child: Skeletonizer(
          enabled: _isLoading,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitleAndSubtitle(isDark),
                          const SizedBox(height: 16),
                          _buildSearchAndFilterRow(isDark, isMobile),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildTitleAndSubtitle(isDark),
                          const Spacer(),
                          _buildSearchAndFilterRow(isDark, isMobile),
                        ],
                      ),
                const SizedBox(height: 24),
                _buildTopSummaryStats(isDark, isMobile),
                const SizedBox(height: 24),
                isMobile
                    ? Column(
                        children: [
                          _buildCompactCalendarGrid(isDark),
                          const SizedBox(height: 16),
                          _buildTripListView(isDark),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: _buildCompactCalendarGrid(isDark),
                          ),
                          const SizedBox(width: 20),
                          Expanded(flex: 2, child: _buildTripListView(isDark)),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleAndSubtitle(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trip History',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'History of trips you have actively assigned.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilterRow(bool isDark, bool isMobile) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: isMobile ? double.infinity : 220,
          height: 44,
          child: TextField(
            onChanged: (value) {
              setState(() {
                _searchTerm = value;
                _currentPage = 0;
              });
            },
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search routes, drivers...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF64748B),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _sortOption,
              icon: const Icon(Icons.sort, size: 18, color: Color(0xFF64748B)),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
              ),
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              items: _sortOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (val) {
                if (val != null)
                  setState(() {
                    _sortOption = val;
                    _currentPage = 0;
                  });
              },
            ),
          ),
        ),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _statusFilter,
              icon: const Icon(
                Icons.filter_alt_outlined,
                size: 18,
                color: Color(0xFF64748B),
              ),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
              ),
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              items: _statusOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (val) {
                if (val != null)
                  setState(() {
                    _statusFilter = val;
                    _currentPage = 0;
                  });
              },
            ),
          ),
        ),
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            border: Border.all(color: Colors.blue.shade600, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            onPressed: _isRefreshing ? null : _fetchStaffLogs,
            icon: const Icon(Icons.refresh, color: Colors.blue, size: 20),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildTopSummaryStats(bool isDark, bool isMobile) {
    // Added Rejected and Expired to the pills array
    final List<Map<String, dynamic>> stats = [
      {
        'label': 'Total Trips',
        'value': _totalTrips.toString(),
        'icon': Icons.inventory_2_outlined,
        'color': isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        'filter': 'All',
      },
      {
        'label': 'Today',
        'value': _todayTrips.toString(),
        'icon': Icons.today,
        'color': const Color(0xFF8B5CF6),
        'filter': 'All',
      },
      {
        'label': 'Scheduled',
        'value': _scheduledTrips.toString(),
        'icon': Icons.schedule,
        'color': const Color(0xFF3B82F6),
        'filter': 'Scheduled',
      },
      {
        'label': 'Ongoing',
        'value': _ongoingTrips.toString(),
        'icon': Icons.play_arrow,
        'color': const Color(0xFFF59E0B),
        'filter': 'Ongoing',
      },
      {
        'label': 'Completed',
        'value': _completedTrips.toString(),
        'icon': Icons.check_circle,
        'color': const Color(0xFF10B981),
        'filter': 'Completed',
      },
      {
        'label': 'Rejected',
        'value': _rejectedTrips.toString(),
        'icon': Icons.cancel_outlined,
        'color': const Color(0xFFEF4444),
        'filter': 'Rejected',
      },
      {
        'label': 'Expired',
        'value': _expiredTrips.toString(),
        'icon': Icons.timer_off_outlined,
        'color': Colors.grey.shade600,
        'filter': 'Expired',
      },
    ];

    Widget buildCard(Map<String, dynamic> stat) {
      final isSelected =
          _statusFilter == stat['filter'] && stat['label'] != 'Today';
      return InkWell(
        onTap: () {
          if (stat['label'] == 'Today') {
            setState(() {
              _filterDate = DateTime.now();
              _currentPage = 0;
            });
          } else {
            setState(() {
              _statusFilter = stat['filter'];
              _currentPage = 0;
            });
          }
        },
        borderRadius: BorderRadius.circular(40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? stat['color'].withValues(alpha: 0.1)
                : (isDark ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: isSelected
                  ? stat['color']
                  : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(stat['icon'], color: stat['color'], size: 28),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    stat['value'],
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      height: 1.1,
                    ),
                  ),
                  Text(
                    stat['label'],
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (isMobile) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: stats.map((stat) => buildCard(stat)).toList(),
      );
    } else {
      return Row(
        children: stats.map((stat) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: stat == stats.last ? 0 : 8.0),
              child: buildCard(stat),
            ),
          );
        }).toList(),
      );
    }
  }

  Widget _buildCompactCalendarGrid(bool isDark) {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final daysInMonth = lastDay.day;
    final firstWeekday = firstDay.weekday % 7;
    final List<String> weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    final headerBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final bodyBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: bodyBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _monthYearFormat(_focusedMonth),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.chevron_left,
                        size: 20,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => setState(
                        () => _focusedMonth = DateTime(
                          _focusedMonth.year,
                          _focusedMonth.month - 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => setState(
                        () => _focusedMonth = DateTime(
                          _focusedMonth.year,
                          _focusedMonth.month + 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.1,
                  mainAxisSpacing: 3,
                  crossAxisSpacing: 3,
                  children: weekdays.map((day) {
                    return Container(
                      decoration: BoxDecoration(
                        color: headerBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor),
                      ),
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.grey.shade400
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 0.95,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: (daysInMonth + firstWeekday),
                  itemBuilder: (context, index) {
                    if (index < firstWeekday) return Container();
                    final day = index - firstWeekday + 1;
                    final date = DateTime(
                      _focusedMonth.year,
                      _focusedMonth.month,
                      day,
                    );
                    final trips = _schedulesForDate(date);
                    final hasTrips = trips.isNotEmpty;

                    final isSelected =
                        _filterDate != null &&
                        _filterDate!.year == date.year &&
                        _filterDate!.month == date.month &&
                        _filterDate!.day == date.day;
                    final isToday =
                        DateTime.now().year == date.year &&
                        DateTime.now().month == date.month &&
                        DateTime.now().day == date.day;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _filterDate = isSelected ? null : date;
                          _currentPage = 0;
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF3B82F6)
                              : (hasTrips
                                    ? (isDark
                                          ? Colors.blue.withValues(alpha: 0.2)
                                          : const Color(0xFFEFF6FF))
                                    : (isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.white)),
                          border: Border.all(
                            color: isToday
                                ? const Color(0xFFF59E0B)
                                : (isSelected
                                      ? const Color(0xFF3B82F6)
                                      : borderColor),
                            width: isToday ? 1.5 : (isSelected ? 1.5 : 1),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            day.toString(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected || isToday
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : (hasTrips
                                        ? const Color(0xFF3B82F6)
                                        : (isDark
                                              ? Colors.grey.shade300
                                              : const Color(0xFF0F172A))),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripListView(bool isDark) {
    final List<dynamic> displayedTrips = _isLoading
        ? List.generate(
            4,
            (index) => {
              'route_name': 'Skeleton Route Data',
              'trip_status': 'Scheduled',
              'schedule_date': '2026-08-28',
              'departure_time': '08:00 AM',
              'estimated_arrival_time': '09:00 AM',
              'driver_name': 'Skeleton Driver Name',
              'plate_number': 'SKL 123',
              'client_company': 'Skeleton Company',
              'passenger_count': 10,
              'route_distance': 15.5,
            },
          )
        : _paginatedTrips;

    final headerBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        color: isDark
                            ? Colors.grey.shade400
                            : const Color(0xFF475569),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _filterDate == null
                              ? 'All Trips'
                              : 'Trips for ${_filterDate!.day}/${_filterDate!.month}/${_filterDate!.year}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.blue.withValues(alpha: 0.2)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_filteredAndSortedTrips.length} results',
                    style: TextStyle(
                      color: isDark
                          ? Colors.blue.shade300
                          : const Color(0xFF3B82F6),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          !_isLoading && displayedTrips.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 40,
                    horizontal: 16,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 48,
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No trips found.',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: displayedTrips.length,
                      itemBuilder: (context, index) {
                        final trip = displayedTrips[index];
                        return _buildTripCard(trip, isDark, borderColor);
                      },
                    ),
                    if (_totalPages > 1 && !_isLoading)
                      _buildPagination(isDark, borderColor),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildTripCard(
    Map<String, dynamic> trip,
    bool isDark,
    Color borderColor,
  ) {
    final String driver = trip['driver_name'] ?? 'Unassigned';
    final String plate = trip['plate_number'] ?? 'N/A';
    final String routeName = trip['route_name'] ?? 'Unknown Route';
    final String company = trip['client_company'] ?? 'Unknown Client';
    final String departure =
        trip['departure_time']?.toString().substring(0, 5) ?? '--:--';
    final String arrival =
        trip['estimated_arrival_time']?.toString().substring(0, 5) ?? '--:--';
    final String passengers = '${trip['passenger_count'] ?? 0} pax';
    final String distance = '${trip['route_distance'] ?? 0} km';

    final String status = trip['trip_status'] ?? 'Scheduled';
    final statusColor = _getStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRIP-${trip['trip_id'] ?? 'N/A'} • $routeName',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _cardIconText(Icons.person_outline, driver, isDark),
                    _cardIconText(Icons.directions_car_outlined, plate, isDark),
                    _cardIconText(
                      Icons.access_time,
                      '$departure → $arrival',
                      isDark,
                    ),
                    _cardIconText(Icons.business_outlined, company, isDark),
                    _cardIconText(Icons.people_outline, passengers, isDark),
                    _cardIconText(Icons.straighten, distance, isDark),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right Content (Status Badge matching admin style)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardIconText(IconData icon, String text, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isDark ? Colors.grey.shade500 : const Color(0xFF64748B),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPagination(bool isDark, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${(_currentPage * _itemsPerPage) + 1}–${min((_currentPage + 1) * _itemsPerPage, _filteredAndSortedTrips.length)} of ${_filteredAndSortedTrips.length}',
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
              fontSize: 12,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.chevron_left,
                  size: 20,
                  color: _currentPage > 0
                      ? const Color(0xFF3B82F6)
                      : Colors.grey.shade400,
                ),
                onPressed: _currentPage > 0
                    ? () => _goToPage(_currentPage - 1)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.2)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_currentPage + 1} / $_totalPages',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? Colors.blue.shade300
                        : const Color(0xFF3B82F6),
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: _currentPage < _totalPages - 1
                      ? const Color(0xFF3B82F6)
                      : Colors.grey.shade400,
                ),
                onPressed: _currentPage < _totalPages - 1
                    ? () => _goToPage(_currentPage + 1)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
