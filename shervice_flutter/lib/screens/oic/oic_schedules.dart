import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import '../../constant.dart';
import '../../widgets/shared/universal_pagination.dart';

class OicSchedules extends StatefulWidget {
  final String oicId;

  const OicSchedules({super.key, required this.oicId});

  @override
  State<OicSchedules> createState() => _OicSchedulesState();
}

class _OicSchedulesState extends State<OicSchedules> {
  // --- State Variables ---
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<dynamic> _myTrips = [];
  List<dynamic> _blackouts = []; // 🔥 Store blocked dates

  // Calendar State
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDate;

  // Filtering & Searching
  String _searchQuery = '';
  String _statusFilter = 'All'; // Interactive cross-filtering

  String _sortOption = 'Date (Newest)';
  final List<String> _sortOptions = [
    'Date (Newest)',
    'Date (Oldest)',
    'Route Name',
    'Status (Priority)',
  ];

  // Pagination
  int _currentPage = 0;
  final int _itemsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _fetchMyTrips();
  }

  // --- Data Fetching ---
  Future<void> _fetchMyTrips() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      if (_myTrips.isEmpty) _isLoading = true;
    });

    try {
      // 1. Fetch Trips
      final response = await http.get(
        Uri.parse('$backendUrl/schedules/oic/${widget.oicId}'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          _myTrips = data['data'] ?? [];
        }
      }

      // 2. 🔥 Fetch Blackout Dates
      final blackoutRes = await http.get(
        Uri.parse('$backendUrl/schedules/blackouts'),
      );
      if (blackoutRes.statusCode == 200 && mounted) {
        _blackouts = jsonDecode(blackoutRes.body)['data'] ?? [];
      }

      if (mounted) {
        setState(() {
          _currentPage = 0;
        });
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  // 🔥 Replaced _isDateBlocked with this to fetch the actual reason
  dynamic _blackoutForDate(DateTime date) {
    final dateString =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    for (final blackout in _blackouts) {
      if (blackout['blackout_date'] == dateString) return blackout;
    }
    return null;
  }

  // --- Modals ---
  void _showNewScheduleModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => CreateTripRequestDialog(
        oicId: widget.oicId,
        blackouts: _blackouts, // Pass blackouts to block dates
      ),
    ).then((_) {
      if (mounted) {
        _fetchMyTrips();
      }
    });
  }

  void _showEditScheduleModal(BuildContext context, Map<String, dynamic> trip) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => EditTripRequestDialog(
        trip: trip,
        backendUrl: backendUrl,
        blackouts: _blackouts, // Pass blackouts to block dates
      ),
    ).then((_) {
      if (mounted) {
        _fetchMyTrips();
      }
    });
  }

  // --- Filtering & Sorting ---
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
            },
          )
        : _myTrips;
    List<dynamic> filtered = displayTrips.where((trip) {
      final route = (trip['route_name'] ?? '').toString().toLowerCase();
      final status = (trip['trip_status'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      // Text Search
      final matchesSearch = route.contains(query) || status.contains(query);

      // Status Pill Filter
      final matchesStatus =
          _statusFilter == 'All' ||
          (_statusFilter == 'Pending' && status.contains('pending')) ||
          (_statusFilter == 'Rejected' && status.contains('rejected')) ||
          (_statusFilter == 'Scheduled' && status == 'scheduled') ||
          (_statusFilter == 'Expired' && status.contains('expired')) ||
          (_statusFilter == 'Completed' && status == 'completed');

      // Date Filter
      final tripDate = _parseDate(trip['schedule_date']);
      final matchesDate =
          _selectedDate == null ||
          (tripDate != null &&
              tripDate.year == _selectedDate!.year &&
              tripDate.month == _selectedDate!.month &&
              tripDate.day == _selectedDate!.day);

      return matchesSearch && matchesStatus && matchesDate;
    }).toList();

    // Sorting
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

  // --- Base Stats Calculation (Unfiltered) ---
  int get _totalTrips => _myTrips.length;
  int get _pendingTrips => _myTrips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase().contains(
          'pending',
        ),
      )
      .length;
  int get _scheduledTrips => _myTrips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase() == 'scheduled',
      )
      .length;
  int get _completedTrips => _myTrips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase() == 'completed',
      )
      .length;
  int get _rejectedTrips => _myTrips
      .where(
        (t) => (t['trip_status'] ?? '').toString().toLowerCase().contains(
          'rejected',
        ),
      )
      .length;
  Color _getStatusColor(String statusStr) {
    String lower = statusStr.toLowerCase();
    if (lower.contains('completed')) return const Color(0xFF10B981); // Green
    if (lower.contains('pending') || lower.contains('ongoing'))
      return const Color(0xFFF59E0B); // Amber
    if (lower.contains('rejected') || lower.contains('cancelled'))
      return const Color(0xFFEF4444); // Red
    if (lower.contains('expired')) return Colors.grey.shade600;
    return const Color(0xFF3B82F6); // Blue (Default/Scheduled)
  }

  // --- Pagination Helpers ---
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

  // --- Utility Formatting ---
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

  String _formatTime(dynamic value) {
    if (value == null) return '--:--';
    final text = value.toString();
    if (text.length >= 5) return text.substring(0, 5);
    return text;
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

  List<dynamic> _schedulesForDate(DateTime day) {
    return _myTrips.where((trip) {
      final date = _parseDate(trip['schedule_date']);
      return date != null &&
          date.year == day.year &&
          date.month == day.month &&
          date.day == day.day;
    }).toList();
  }

  // --- MAIN BUILD ---
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
          onRefresh: _fetchMyTrips,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ----- HEADER & FILTERS -----
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
                          const Spacer(), // Forces actions to far right
                          _buildSearchAndActionRow(isDark, isMobile),
                        ],
                      ),
                const SizedBox(height: 24),

                // ----- SUMMARY PILL CARDS -----
                _buildTopSummaryStats(isDark, isMobile),
                const SizedBox(height: 24),

                // ----- MAIN CONTENT (Desktop: Row, Mobile: Column) -----
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
          'Trip Requests',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Manage schedules, pending requests, and dispatches.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // --- ACTIONS ROW (Strict 44px Height) ---
  Widget _buildSearchAndActionRow(bool isDark, bool isMobile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Search Box
        SizedBox(
          width: isMobile ? 140 : 200,
          height: 44,
          child: TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _currentPage = 0;
              });
            },
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search requests...',
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
        // Sort Dropdown
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
        // Refresh Button
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: Colors.blue.shade600, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            onPressed: _isRefreshing ? null : _fetchMyTrips,
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
        const SizedBox(width: 8),
        // New Trip Button
        SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            onPressed: () => _showNewScheduleModal(context),
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text(
              'New Trip',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6), // Strict Action Blue
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  // --- INTERACTIVE PILL CARDS ---
  Widget _buildTopSummaryStats(bool isDark, bool isMobile) {
    final List<Map<String, dynamic>> stats = [
      {
        'label': 'Total',
        'value': _totalTrips.toString(),
        'icon': Icons.inventory_2_outlined,
        'color': isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        'filter': 'All',
      },
      {
        'label': 'Pending',
        'value': _pendingTrips.toString(),
        'icon': Icons.hourglass_top,
        'color': const Color(0xFFF59E0B),
        'filter': 'Pending',
      },
      {
        'label': 'Scheduled',
        'value': _scheduledTrips.toString(),
        'icon': Icons.event_available,
        'color': const Color(0xFF3B82F6),
        'filter': 'Scheduled',
      },
      {
        'label': 'Completed',
        'value': _completedTrips.toString(),
        'icon': Icons.check_circle_outline,
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

  // --- CALENDAR GRID ---
  Widget _buildCompactCalendarGrid(bool isDark) {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final daysInMonth = lastDay.day;
    final firstWeekday = firstDay.weekday % 7;
    final List<String> weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

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

                    // 🔥 Fetch blackout info
                    final blackout = _blackoutForDate(date);
                    final isBlocked = blackout != null;

                    final isSelected =
                        _selectedDate?.year == date.year &&
                        _selectedDate?.month == date.month &&
                        _selectedDate?.day == date.day;

                    final isToday =
                        DateTime.now().year == date.year &&
                        DateTime.now().month == date.month &&
                        DateTime.now().day == date.day;

                    return GestureDetector(
                      onTap: () {
                        // 🔥 Show the block reason if the date is blocked
                        if (isBlocked) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Date Blocked: ${blackout['reason']}',
                              ),
                              backgroundColor: const Color(0xFFEF4444),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }

                        setState(() {
                          if (isSelected) {
                            _selectedDate = null;
                          } else {
                            _selectedDate = date;
                          }
                          _currentPage = 0;
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF3B82F6)
                              : isBlocked
                              ? const Color(0xFFFEE2E2) // Red bg for blocked
                              : (hasTrips
                                    ? (isDark
                                          ? Colors.blue.withValues(alpha: 0.2)
                                          : const Color(0xFFEFF6FF))
                                    : Theme.of(context).cardColor),
                          border: Border.all(
                            color: isToday
                                ? const Color(0xFFF59E0B)
                                : isBlocked
                                ? const Color(0xFFEF4444) // Red border
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
                                  : isBlocked
                                  ? const Color(0xFFEF4444) // Red text
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

  // --- TRIP LIST VIEW ---
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
                        Icons.list_alt,
                        color: isDark
                            ? Colors.grey.shade400
                            : const Color(0xFF475569),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _selectedDate == null
                              ? 'Request History'
                              : 'Requests for ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
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
                    '${_filteredAndSortedTrips.length} found',
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
                        Icons.inbox_outlined,
                        size: 48,
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No requests found.',
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

  // --- TRIP CARD ---
  Widget _buildTripCard(
    Map<String, dynamic> trip,
    bool isDark,
    Color borderColor,
  ) {
    final statusStr = trip['trip_status']?.toString() ?? 'Unknown';
    final statusColor = _getStatusColor(statusStr);

    final bool isPending = statusStr.toLowerCase().contains('pending');
    final bool isRejected = statusStr.toLowerCase().contains('rejected');

    final String routeName = trip['route_name'] ?? 'Unknown Route';
    final String dateStr = trip['schedule_date'] ?? 'TBD';
    final String timeStr = _formatTime(trip['departure_time']);
    final String etaStr = _formatTime(trip['estimated_arrival_time']);
    final String pax = trip['passenger_count']?.toString() ?? '0';
    final String dist = trip['route_distance']?.toString() ?? '0';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRIP-${trip['trip_id'] ?? 'N/A'} • $routeName',
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
                    _cardIconText(Icons.calendar_month, dateStr, isDark),
                    _cardIconText(
                      Icons.access_time,
                      '$timeStr - $etaStr',
                      isDark,
                    ),
                    _cardIconText(Icons.groups, '$pax Pax', isDark),
                    _cardIconText(Icons.map_outlined, '$dist km', isDark),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusStr.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (isPending || isRejected) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.edit, color: Colors.blue.shade600, size: 18),
                  onPressed: () => _showEditScheduleModal(context, trip),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: 'Edit Request',
                ),
              ],
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

  // --- PAGINATION FOOTER ---
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

// ─── CREATE TRIP REQUEST DIALOG ───
class CreateTripRequestDialog extends StatefulWidget {
  final String oicId;
  final List<dynamic> blackouts; // 🔥 Added to block dates

  const CreateTripRequestDialog({
    super.key,
    required this.oicId,
    required this.blackouts,
  });

  @override
  State<CreateTripRequestDialog> createState() =>
      _CreateTripRequestDialogState();
}

class _CreateTripRequestDialogState extends State<CreateTripRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _loadingStaff = true;

  List<dynamic> _staffMembers = [];
  String? _selectedStaffId;

  final _destinationController = TextEditingController();
  final _passengerController = TextEditingController();
  final _distanceController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  TimeOfDay? _selectedArrivalTime;

  @override
  void initState() {
    super.initState();
    _fetchStaff();
  }

  Future<void> _fetchStaff() async {
    try {
      final response = await http.get(
        Uri.parse('$backendUrl/schedules/staff-options'),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true && mounted) {
        setState(() {
          _staffMembers = data['data'];
          _loadingStaff = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null ||
        _selectedTime == null ||
        _selectedArrivalTime == null ||
        _selectedStaffId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all fields.'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);

    final formattedDate =
        "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";
    final formattedTime =
        "${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00";
    final formattedETA =
        "${_selectedArrivalTime!.hour.toString().padLeft(2, '0')}:${_selectedArrivalTime!.minute.toString().padLeft(2, '0')}:00";

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/schedules/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "oic_id": widget.oicId,
          "staff_id": _selectedStaffId,
          "destination": _destinationController.text.trim(),
          "passenger_count": _passengerController.text.trim(),
          "route_distance": _distanceController.text.trim(),
          "departure_date": formattedDate,
          "departure_time": formattedTime,
          "estimated_arrival_time": formattedETA,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 && data['success'] == true) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Trip requested!"),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        throw Exception(data['message'] ?? "Failed to submit request.");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        "Request Schedule",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: textColor,
        ),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loadingStaff)
                  const LinearProgressIndicator()
                else
                  DropdownButtonFormField<String>(
                    dropdownColor: Theme.of(context).cardColor,
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: "Dispatch Staff",
                      labelStyle: TextStyle(
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                      ),
                      prefixIcon: Icon(
                        Icons.support_agent,
                        size: 18,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    initialValue: _selectedStaffId,
                    items: _staffMembers
                        .map(
                          (s) => DropdownMenuItem<String>(
                            value: s['user_id'],
                            child: Text(s['full_name'] ?? 'Staff'),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _selectedStaffId = val),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _destinationController,
                  style: TextStyle(color: textColor, fontSize: 13),
                  validator: (val) => val!.isEmpty ? "Required" : null,
                  decoration: InputDecoration(
                    labelText: "Route / Destination",
                    labelStyle: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                      ),
                    ),
                    prefixIcon: Icon(
                      Icons.location_on,
                      size: 18,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _distanceController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: textColor, fontSize: 13),
                        validator: (val) {
                          if (val == null || val.isEmpty) return "Required";
                          if (double.tryParse(val) == null) return "Invalid";
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: "Distance (km)",
                          labelStyle: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                          ),
                          prefixIcon: Icon(
                            Icons.map,
                            size: 18,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _passengerController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: textColor, fontSize: 13),
                        validator: (val) {
                          if (val == null || val.isEmpty) return "Required";
                          final count = int.tryParse(val);
                          if (count == null) return "Invalid";
                          if (count > 20) return "Max 20";
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: "Passengers",
                          labelStyle: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                          ),
                          prefixIcon: Icon(
                            Icons.people,
                            size: 18,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2030),
                            // 🔥 PREVENT SELECTING BLOCKED DATES
                            selectableDayPredicate: (DateTime val) {
                              final dateStr =
                                  '${val.year}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}';
                              return !widget.blackouts.any(
                                (b) => b['blackout_date'] == dateStr,
                              );
                            },
                          );
                          if (picked != null)
                            setState(() => _selectedDate = picked);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Date',
                            labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            _selectedDate == null
                                ? "Select Date"
                                : "${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}",
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: const TimeOfDay(hour: 8, minute: 0),
                          );
                          if (picked != null)
                            setState(() => _selectedTime = picked);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Depart',
                            labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            _selectedTime == null
                                ? "Time"
                                : _selectedTime!.format(context),
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: const TimeOfDay(hour: 17, minute: 0),
                          );
                          if (picked != null)
                            setState(() => _selectedArrivalTime = picked);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'ETA',
                            labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            _selectedArrivalTime == null
                                ? "Arrival"
                                : _selectedArrivalTime!.format(context),
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  "Submit",
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

// ─── EDIT TRIP REQUEST DIALOG ───
class EditTripRequestDialog extends StatefulWidget {
  final Map<String, dynamic> trip;
  final String backendUrl;
  final List<dynamic> blackouts; // 🔥 Added to block dates

  const EditTripRequestDialog({
    super.key,
    required this.trip,
    required this.backendUrl,
    required this.blackouts,
  });

  @override
  State<EditTripRequestDialog> createState() => _EditTripRequestDialogState();
}

class _EditTripRequestDialogState extends State<EditTripRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  late TextEditingController _destinationController;
  late TextEditingController _passengerController;
  late TextEditingController _distanceController;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  TimeOfDay? _selectedArrivalTime;

  @override
  void initState() {
    super.initState();
    _destinationController = TextEditingController(
      text: widget.trip['route_name'],
    );
    _passengerController = TextEditingController(
      text: widget.trip['passenger_count'].toString(),
    );
    _distanceController = TextEditingController(
      text: widget.trip['route_distance'].toString(),
    );

    if (widget.trip['schedule_date'] != null) {
      _selectedDate = DateTime.parse(
        widget.trip['schedule_date'].toString().split(' ').first,
      );
    }
    _selectedTime = _parseTimeOfDay(widget.trip['departure_time']);
    _selectedArrivalTime = _parseTimeOfDay(
      widget.trip['estimated_arrival_time'],
    );
  }

  TimeOfDay? _parseTimeOfDay(dynamic timeString) {
    if (timeString == null) return null;
    final parts = timeString.toString().split(':');
    if (parts.length >= 2)
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    return null;
  }

  Future<void> _submitEdit() async {
    if (!_formKey.currentState!.validate() ||
        _selectedDate == null ||
        _selectedTime == null ||
        _selectedArrivalTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all fields.'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);

    final formattedDate =
        "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";
    final formattedTime =
        "${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00";
    final formattedETA =
        "${_selectedArrivalTime!.hour.toString().padLeft(2, '0')}:${_selectedArrivalTime!.minute.toString().padLeft(2, '0')}:00";

    try {
      final response = await http.put(
        Uri.parse('${widget.backendUrl}/schedules/update-request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "trip_id": widget.trip['trip_id'],
          "staff_id": widget.trip['staff_id'],
          "destination": _destinationController.text.trim(),
          "passenger_count": _passengerController.text.trim(),
          "route_distance": _distanceController.text.trim(),
          "departure_date": formattedDate,
          "departure_time": formattedTime,
          "estimated_arrival_time": formattedETA,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Trip updated!"),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        throw Exception(data['message'] ?? "Failed to update request.");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        "Edit Request",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: textColor,
        ),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _destinationController,
                  style: TextStyle(color: textColor, fontSize: 13),
                  validator: (val) => val!.isEmpty ? "Required" : null,
                  decoration: InputDecoration(
                    labelText: "Route / Destination",
                    labelStyle: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                      ),
                    ),
                    prefixIcon: Icon(
                      Icons.location_on,
                      size: 18,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _distanceController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: textColor, fontSize: 13),
                        validator: (val) => val == null || val.isEmpty
                            ? "Required"
                            : (double.tryParse(val) == null ? "Invalid" : null),
                        decoration: InputDecoration(
                          labelText: "Distance (km)",
                          labelStyle: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                          ),
                          prefixIcon: Icon(
                            Icons.map,
                            size: 18,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _passengerController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: textColor, fontSize: 13),
                        validator: (val) {
                          if (val == null || val.isEmpty) return "Required";
                          final count = int.tryParse(val);
                          if (count == null) return "Invalid";
                          if (count > 20) return "Max 20";
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: "Passengers",
                          labelStyle: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                          ),
                          prefixIcon: Icon(
                            Icons.people,
                            size: 18,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _selectedDate ??
                                DateTime.now().add(const Duration(days: 1)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2030),
                            // 🔥 PREVENT SELECTING BLOCKED DATES
                            selectableDayPredicate: (DateTime val) {
                              final dateStr =
                                  '${val.year}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}';
                              return !widget.blackouts.any(
                                (b) => b['blackout_date'] == dateStr,
                              );
                            },
                          );
                          if (picked != null)
                            setState(() => _selectedDate = picked);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Date',
                            labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            _selectedDate == null
                                ? "Select Date"
                                : "${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}",
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime:
                                _selectedTime ??
                                const TimeOfDay(hour: 8, minute: 0),
                          );
                          if (picked != null)
                            setState(() => _selectedTime = picked);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Depart',
                            labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            _selectedTime == null
                                ? "Time"
                                : _selectedTime!.format(context),
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime:
                                _selectedArrivalTime ??
                                const TimeOfDay(hour: 17, minute: 0),
                          );
                          if (picked != null)
                            setState(() => _selectedArrivalTime = picked);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'ETA',
                            labelStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            _selectedArrivalTime == null
                                ? "Arrival"
                                : _selectedArrivalTime!.format(context),
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitEdit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  "Save",
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
