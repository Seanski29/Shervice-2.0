import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import 'dart:convert';
import 'dart:math';
import '../../constant.dart';
import '../../widgets/shared/universal_pagination.dart';

class OicTrips extends StatefulWidget {
  final String oicId;

  const OicTrips({super.key, required this.oicId});

  @override
  State<OicTrips> createState() => _OicTripsState();
}

class _OicTripsState extends State<OicTrips> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<dynamic> _trips = [];

  DateTime _focusedMonth = DateTime.now();
  DateTime? _filterDate;

  String _searchTerm = '';
  String _statusFilter = 'All';

  String _sortOption = 'Date (Newest)';
  final List<String> _sortOptions = [
    'Date (Newest)',
    'Date (Oldest)',
    'Route Name',
    'Status (Priority)',
  ];

  int _currentPage = 0;
  final int _itemsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _fetchDeploymentLogs();
  }

  Future<void> _fetchDeploymentLogs() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      if (_trips.isEmpty) _isLoading = true;
    });

    try {
      final res = await http.get(
        Uri.parse('$backendUrl/schedules/oic/${widget.oicId}'),
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
      debugPrint("Error fetching deployment logs: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  String _formatTimeString(dynamic timeVal) {
    if (timeVal == null || timeVal.toString().trim().isEmpty) return '--:--';
    String t = timeVal.toString();
    if (t.length >= 5) return t.substring(0, 5);
    return t;
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null || timestamp.toString().trim().isEmpty)
      return '--:--';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '--:--';
    }
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

  List<dynamic> get _filteredAndSortedTrips {
    final placeholderStatus = _statusFilter == 'All'
        ? 'Scheduled'
        : _statusFilter;
    final displayTrips = _isLoading
        ? List.generate(
            5,
            (index) => {
              'trip_id': index + 1,
              'route_name': 'Loading Route',
              'trip_status': placeholderStatus,
              'schedule_date': DateTime.now().toIso8601String(),
              'driver_name': 'Loading Driver',
              'plate_number': 'Loading Vehicle',
              'departure_time': '08:00',
              'estimated_arrival_time': '09:00',
              'actual_start_time': null,
              'actual_end_time': null,
            },
          )
        : _trips;
    List<dynamic> filtered = displayTrips.where((trip) {
      final route = (trip['route_name'] ?? '').toString().toLowerCase();
      final driver = (trip['driver_name'] ?? '').toString().toLowerCase();
      final status = (trip['trip_status'] ?? '').toString().toLowerCase();
      final query = _searchTerm.toLowerCase();
      final dateStr = trip['schedule_date']?.toString() ?? '';

      final matchesSearch =
          _searchTerm.isEmpty ||
          route.contains(query) ||
          driver.contains(query);

      final matchesStatus =
          _statusFilter == 'All' ||
          (_statusFilter == 'Completed' && status.contains('completed')) ||
          (_statusFilter == 'Ongoing' && status.contains('ongoing')) ||
          (_statusFilter == 'Scheduled' && status.contains('scheduled')) ||
          (_statusFilter == 'Expired' && status.contains('expired')) ||
          (_statusFilter == 'Cancelled' &&
              (status.contains('cancelled') || status.contains('rejected')));

      final matchesDate =
          _filterDate == null ||
          dateStr.startsWith(
            '${_filterDate!.year}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}',
          );

      return matchesSearch && matchesStatus && matchesDate;
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
      case 'Status (Priority)':
        filtered.sort((a, b) {
          final statusA = (a['trip_status'] ?? '').toString().toLowerCase();
          final statusB = (b['trip_status'] ?? '').toString().toLowerCase();
          final priority = {
            'pending staff assignment': 0,
            'rejected': 1,
            'completed': 2,
            'ongoing': 3,
            'scheduled': 4,
          };
          final pA = priority[statusA] ?? 5;
          final pB = priority[statusB] ?? 5;
          return pA.compareTo(pB);
        });
        break;
    }
    return filtered;
  }

  int get _totalPages =>
      max(1, (_filteredAndSortedTrips.length / _itemsPerPage).ceil());

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
  int get _completedTrips => _trips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase().contains(
          'completed',
        ),
      )
      .length;
  int get _ongoingTrips => _trips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase().contains(
          'ongoing',
        ),
      )
      .length;
  int get _scheduledTrips => _trips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase().contains(
          'scheduled',
        ),
      )
      .length;
  int get _cancelledTrips => _trips.where((t) {
    final s = (t['trip_status'] ?? '').toString().toLowerCase();
    return s.contains('cancelled') || s.contains('rejected');
  }).length;
  int get _expiredTrips => _trips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase().contains(
          'expired',
        ),
      )
      .length;

  Color _getStatusColor(String statusStr) {
    String lower = statusStr.toLowerCase();
    if (lower.contains('completed')) return const Color(0xFF10B981);
    if (lower.contains('ongoing') || lower.contains('pending'))
      return const Color(0xFFF59E0B);
    if (lower.contains('cancelled') || lower.contains('rejected'))
      return const Color(0xFFEF4444);
    return const Color(0xFF3B82F6);
  }

  List<dynamic> _schedulesForDate(DateTime day) {
    final dateStr =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _trips.where((trip) {
      final tripDate = trip['schedule_date']?.toString() ?? '';
      return tripDate.startsWith(dateStr);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 900;
    final double horizontalPadding = isMobile ? 12.0 : 24.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Skeletonizer(
        enabled: _isLoading,
        child: RefreshIndicator(
          onRefresh: _fetchDeploymentLogs,
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
                          _buildTitleHeader(isDark),
                          const SizedBox(height: 16),
                          _buildSearchAndActionRow(isDark, isMobile),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildTitleHeader(isDark),
                          const Spacer(),
                          _buildSearchAndActionRow(isDark, isMobile),
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

  Widget _buildTitleHeader(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trips History Log',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Comprehensive ledger of past and finalized fleet deployments.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndActionRow(bool isDark, bool isMobile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: isMobile ? 160 : 220,
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
              hintText: 'Search history...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF64748B),
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
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
        const SizedBox(width: 8),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _sortOption,
              icon: const Icon(Icons.sort, size: 16, color: Color(0xFF64748B)),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
              ),
              dropdownColor: Theme.of(context).cardColor,
              items: _sortOptions.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() {
                    _sortOption = newValue;
                    _currentPage = 0;
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: Colors.blue.shade600, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            onPressed: _isRefreshing ? null : _fetchDeploymentLogs,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.blue, size: 20),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildTopSummaryStats(bool isDark, bool isMobile) {
    final List<Map<String, dynamic>> stats = [
      {
        'label': 'Total Logged',
        'value': _totalTrips.toString(),
        'icon': Icons.inventory_2_outlined,
        'color': isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        'filter': 'All',
      },
      {
        'label': 'Completed',
        'value': _completedTrips.toString(),
        'icon': Icons.check_circle_outline,
        'color': const Color(0xFF10B981),
        'filter': 'Completed',
      },
      {
        'label': 'Ongoing',
        'value': _ongoingTrips.toString(),
        'icon': Icons.play_arrow_outlined,
        'color': const Color(0xFFF59E0B),
        'filter': 'Ongoing',
      },
      {
        'label': 'Scheduled',
        'value': _scheduledTrips.toString(),
        'icon': Icons.event_available,
        'color': const Color(0xFF3B82F6),
        'filter': 'Scheduled',
      },
      {
        'label': 'Cancelled',
        'value': _cancelledTrips.toString(),
        'icon': Icons.cancel_outlined,
        'color': const Color(0xFFEF4444),
        'filter': 'Cancelled',
      },
      {
        'label': 'Expired',
        'value': _expiredTrips.toString(),
        'icon': Icons.timer_off,
        'color': Colors.grey.shade600,
        'filter': 'Expired',
      },
    ];

    Widget buildCard(Map<String, dynamic> stat) {
      final isSelected = _statusFilter == stat['filter'];
      return InkWell(
        onTap: () {
          setState(() {
            _statusFilter = stat['filter'];
            _currentPage = 0;
          });
        },
        borderRadius: BorderRadius.circular(40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? stat['color'].withOpacity(0.1)
                : Theme.of(context).cardColor,
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
              padding: EdgeInsets.only(right: stat == stats.last ? 0 : 16.0),
              child: buildCard(stat),
            ),
          );
        }).toList(),
      );
    }
  }

  Widget _buildCompactCalendarGrid(bool isDark) {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysBefore = firstDay.weekday % 7;
    final daysInMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    ).day;
    final totalCells = ((daysBefore + daysInMonth) / 7).ceil() * 7;
    final now = DateTime.now();

    final headerBg = Theme.of(context).cardColor;
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
                  children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((day) {
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
                  itemCount: totalCells,
                  itemBuilder: (context, index) {
                    if (index < daysBefore || index >= daysBefore + daysInMonth)
                      return Container();

                    final day = index - daysBefore + 1;
                    final date = DateTime(
                      _focusedMonth.year,
                      _focusedMonth.month,
                      day,
                    );
                    final trips = _schedulesForDate(date);
                    final hasTrips = trips.isNotEmpty;

                    final isSelected =
                        _filterDate?.year == date.year &&
                        _filterDate?.month == date.month &&
                        _filterDate?.day == date.day;

                    final isToday =
                        now.year == date.year &&
                        now.month == date.month &&
                        now.day == date.day;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _filterDate = null;
                          } else {
                            _filterDate = date;
                          }
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
                                    : Theme.of(context).cardColor),
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
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
                        Icons.history,
                        color: isDark
                            ? Colors.grey.shade400
                            : const Color(0xFF475569),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _filterDate == null
                              ? 'All Recorded Trips'
                              : 'Logs for ${_filterDate!.day}/${_filterDate!.month}/${_filterDate!.year}',
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
                    '${_filteredAndSortedTrips.length} entries',
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
          _paginatedTrips.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 60,
                    horizontal: 16,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.layers_clear_outlined,
                        size: 48,
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No historical data found.',
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade500,
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
                      itemCount: _paginatedTrips.length,
                      itemBuilder: (context, index) {
                        final trip = _paginatedTrips[index];
                        return _buildTripCard(trip, isDark, borderColor);
                      },
                    ),
                    if (_totalPages > 1) _buildPagination(isDark, borderColor),
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
    final status = (trip['trip_status'] ?? 'Scheduled')
        .toString()
        .toLowerCase();
    final statusColor = _getStatusColor(status);

    final route = trip['route_name'] ?? 'Unknown Route';
    final tripId = trip['trip_id']?.toString() ?? 'N/A';
    final driver = trip['driver_name'] ?? 'Unassigned';
    final plate = trip['plate_number'] ?? 'No Plate';
    final pax = trip['passenger_count']?.toString() ?? '0';
    final dist = trip['route_distance']?.toString() ?? '0';
    final dep = _formatTimeString(trip['departure_time']);
    final arr = _formatTimeString(trip['estimated_arrival_time']);
    final date = trip['schedule_date'] ?? 'TBD';

    final rawActStart = trip['actual_start_time'];
    final rawActEnd = trip['actual_end_time'];
    final bool hasActual = rawActStart != null || rawActEnd != null;
    final String actStartStr = _formatTimestamp(rawActStart);
    final String actEndStr = rawActEnd != null
        ? _formatTimestamp(rawActEnd)
        : (status.contains('ongoing') ? 'En Route' : '--:--');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 36,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRIP-$tripId • $route',
                  style: TextStyle(
                    fontSize: 15,
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
                    _cardIconText(Icons.calendar_month, date, isDark),
                    _cardIconText(
                      Icons.access_time,
                      'Sched: $dep - $arr',
                      isDark,
                    ),
                    if (hasActual)
                      _cardIconText(
                        Icons.timer_outlined,
                        'Actual: $actStartStr - $actEndStr',
                        isDark,
                        customColor: rawActEnd != null
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                    _cardIconText(Icons.person_outline, driver, isDark),
                    _cardIconText(Icons.directions_car_outlined, plate, isDark),
                    _cardIconText(Icons.groups, '$pax Pax', isDark),
                    _cardIconText(Icons.straighten, '$dist km', isDark),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardIconText(
    IconData icon,
    String text,
    bool isDark, {
    Color? customColor,
  }) {
    final Color textColor =
        customColor ??
        (isDark ? Colors.grey.shade400 : const Color(0xFF64748B));
    final Color iconColor =
        customColor ??
        (isDark ? Colors.grey.shade500 : const Color(0xFF64748B));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: customColor != null
                  ? FontWeight.bold
                  : FontWeight.w500,
              color: textColor,
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      alignment: Alignment.centerLeft,
      child: UniversalPagination(
        currentPage: _currentPage,
        totalPages: _totalPages,
        totalItems: _filteredAndSortedTrips.length,
        itemsPerPage: _itemsPerPage,
        itemName: 'entries',
        onNextPage: _currentPage < _totalPages - 1
            ? () => _goToPage(_currentPage + 1)
            : null,
        onPrevPage: _currentPage > 0 ? () => _goToPage(_currentPage - 1) : null,
      ),
    );
  }
}
