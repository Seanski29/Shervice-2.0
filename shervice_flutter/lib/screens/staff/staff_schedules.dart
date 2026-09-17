import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import '../../constant.dart';

// ============================================================================
// FORMATTING HELPER
// ============================================================================
String _formatTimeRange(String? departureTime, String? etaTime) {
  final departure = departureTime?.toString().trim();
  final eta = etaTime?.toString().trim();

  final formattedDeparture = departure != null && departure.isNotEmpty
      ? (departure.length >= 5 ? departure.substring(0, 5) : departure)
      : '--:--';
  final formattedEta = eta != null && eta.isNotEmpty
      ? (eta.length >= 5 ? eta.substring(0, 5) : eta)
      : '--:--';

  return '$formattedDeparture-$formattedEta';
}

// ============================================================================
// MAIN WIDGET
// ============================================================================
class StaffSchedules extends StatefulWidget {
  final String staffId;
  const StaffSchedules({super.key, required this.staffId});

  @override
  State<StaffSchedules> createState() => _StaffSchedulesState();
}

class _StaffSchedulesState extends State<StaffSchedules> {
  // --- State Variables ---
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<dynamic> _assignedTrips = [];
  List<dynamic> _blackouts = [];

  // Calendar State
  DateTime _selectedMonth = DateTime.now();
  DateTime? _selectedDate = DateTime.now();

  // Search & Filter
  String _searchQuery = '';
  String _statusFilter = 'All';
  final List<String> _statusOptions = [
    'All',
    'Scheduled',
    'Unassigned',
    'Rejected',
    'Expired',
  ];

  @override
  void initState() {
    super.initState();
    _fetchStaffDashboardData();
  }

  // --- Data Fetching ---
  Future<void> _fetchStaffDashboardData() async {
    if (_isRefreshing) return;
    setState(() {
      _isLoading = true;
      _isRefreshing = true;
    });

    try {
      final tripsResponse = await http.get(
        Uri.parse('$backendUrl/schedules/staff/${widget.staffId}'),
      );

      if (tripsResponse.statusCode == 200 && mounted) {
        final tripsData = jsonDecode(tripsResponse.body);
        setState(() {
          _assignedTrips = tripsData['data'] ?? [];
        });
      }
      final blackoutResponse = await http.get(
        Uri.parse('$backendUrl/schedules/blackouts'),
      );
      if (blackoutResponse.statusCode == 200 && mounted) {
        setState(
          () => _blackouts = jsonDecode(blackoutResponse.body)['data'] ?? [],
        );
      }
    } catch (e) {
      debugPrint("Error fetching staff schedules: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  // --- Filtering & Sorting Logic ---
  List<dynamic> _getTripsForDate(DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _assignedTrips
        .where((trip) => trip['schedule_date'] == dateStr)
        .toList();
  }

  dynamic _blackoutForDate(DateTime date) {
    final dateString =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    for (final blackout in _blackouts) {
      if (blackout['blackout_date'] == dateString) return blackout;
    }
    return null;
  }

  Future<void> _toggleBlackout(DateTime date) async {
    final existing = _blackoutForDate(date);
    if (existing != null) {
      final response = await http.delete(
        Uri.parse('$backendUrl/schedules/blackouts/${existing['blackout_id']}'),
      );
      if (response.statusCode == 200) _fetchStaffDashboardData();
      return;
    }

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block ${_formatDateOnly(date)}'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason *',
            hintText: 'e.g. GT LANTIN unavailable',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Block Date'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null) return;

    final dateString =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final response = await http.post(
      Uri.parse('$backendUrl/schedules/blackouts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'blackout_date': dateString, 'reason': reason}),
    );
    if (response.statusCode == 201) _fetchStaffDashboardData();
  }

  List<dynamic> _getFilteredTrips() {
    if (_isLoading) {
      // Mock data for skeletonizer
      return List.generate(
        4,
        (index) => {
          'trip_id': index,
          'route_name': 'Loading Route Description Data',
          'trip_status': 'Scheduled',
          'schedule_date':
              '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
          'departure_time': '00:00:00',
          'estimated_arrival_time': '00:00:00',
          'client_company': 'Loading Company Data',
          'passenger_count': 0,
          'route_distance': 0.0,
          'driver_name': 'Loading Driver Name',
          'vehicle_plate': 'LOADING',
          'user_id': 1,
          'vehicle_id': 1,
        },
      );
    }

    List<dynamic> trips = _selectedDate != null
        ? _getTripsForDate(_selectedDate!)
        : List.from(_assignedTrips);

    // 1. Search Filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      trips = trips.where((trip) {
        final routeName = (trip['route_name'] ?? '').toString().toLowerCase();
        final driverName = (trip['driver_name'] ?? '').toString().toLowerCase();
        final companyName = (trip['client_company'] ?? '')
            .toString()
            .toLowerCase();
        return routeName.contains(query) ||
            driverName.contains(query) ||
            companyName.contains(query);
      }).toList();
    }

    // 2. Status Filter
    if (_statusFilter != 'All') {
      trips = trips.where((trip) {
        final statusStr = trip['trip_status']?.toString() ?? 'Unknown';
        final isRejected = statusStr.toLowerCase().contains('rejected');
        final isUnassigned =
            (trip['user_id'] == null || trip['vehicle_id'] == null) &&
            !isRejected;
        final isScheduled =
            trip['user_id'] != null &&
            trip['vehicle_id'] != null &&
            !isRejected;

        if (_statusFilter == 'Scheduled') return isScheduled;
        if (_statusFilter == 'Unassigned') return isUnassigned;
        if (_statusFilter == 'Rejected') return isRejected;
        if (_statusFilter == 'Expired')
          return statusStr.toLowerCase().contains('expired');
        return true;
      }).toList();
    }

    // 3. Sort: Unassigned first
    trips.sort((a, b) {
      final aStatus = a['trip_status']?.toString().toLowerCase() ?? '';
      final bStatus = b['trip_status']?.toString().toLowerCase() ?? '';

      final aRejected = aStatus.contains('rejected');
      final bRejected = bStatus.contains('rejected');

      final aUnassigned =
          (a['user_id'] == null || a['vehicle_id'] == null) && !aRejected;
      final bUnassigned =
          (b['user_id'] == null || b['vehicle_id'] == null) && !bRejected;

      if (aUnassigned && !bUnassigned) return -1;
      if (!aUnassigned && bUnassigned) return 1;
      return 0;
    });

    return trips;
  }

  // --- Base Stats ---
  int get _totalTrips => _isLoading ? 8 : _assignedTrips.length;

  int get _rejectedTrips => _isLoading
      ? 0
      : _assignedTrips.where((t) {
          final statusStr = t['trip_status']?.toString() ?? 'Unknown';
          return statusStr.toLowerCase().contains('rejected');
        }).length;
  int get _expiredTrips => _isLoading
      ? 0
      : _assignedTrips.where((t) {
          final statusStr = t['trip_status']?.toString() ?? 'Unknown';
          return statusStr.toLowerCase().contains('expired');
        }).length;

  int get _scheduledTrips => _isLoading
      ? 5
      : _assignedTrips.where((t) {
          final statusStr = t['trip_status']?.toString() ?? 'Unknown';
          final isRejected = statusStr.toLowerCase().contains('rejected');
          return t['user_id'] != null && t['vehicle_id'] != null && !isRejected;
        }).length;

  int get _unassignedTrips => _isLoading
      ? 3
      : _assignedTrips.where((t) {
          final statusStr = t['trip_status']?.toString() ?? 'Unknown';
          final isRejected = statusStr.toLowerCase().contains('rejected');
          return (t['user_id'] == null || t['vehicle_id'] == null) &&
              !isRejected;
        }).length;

  String _formatDateOnly(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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

  // --- MAIN BUILD ---
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 900;
    final double horizontalPadding = isMobile ? 12.0 : 24.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _fetchStaffDashboardData,
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
                // ----- HEADER & FILTERS -----
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

                // ----- TOP STATS -----
                _buildTopSummaryStats(isDark, isMobile),
                const SizedBox(height: 24),

                // ----- DATE CLEAR HINT -----
                if (_selectedDate != null) _buildActiveDateHint(isDark),

                // ----- MAIN LAYOUT -----
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
          'Trip Assignment',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Assign trips and monitor dispatch schedules.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveDateHint(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(Icons.event_available, size: 18, color: const Color(0xFF3B82F6)),
          const SizedBox(width: 8),
          Text(
            'Viewing trips for: ${_formatDateOnly(_selectedDate!)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF3B82F6),
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: () => setState(() => _selectedDate = null),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close, size: 14, color: Color(0xFF3B82F6)),
                  SizedBox(width: 4),
                  Text(
                    'Clear Date Filter',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF3B82F6),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _toggleBlackout(_selectedDate!),
            icon: Icon(
              _blackoutForDate(_selectedDate!) == null
                  ? Icons.block_outlined
                  : Icons.lock_open_outlined,
              size: 15,
            ),
            label: Text(
              _blackoutForDate(_selectedDate!) == null
                  ? 'Block Date'
                  : 'Unblock Date',
            ),
          ),
        ],
      ),
    );
  }

  // ---- SEARCH & FILTER ROW ----
  Widget _buildSearchAndFilterRow(bool isDark, bool isMobile) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Search Box
        SizedBox(
          width: isMobile ? double.infinity : 220,
          height: 44,
          child: TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
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
        // Status Dropdown
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
                if (val != null) setState(() => _statusFilter = val);
              },
            ),
          ),
        ),
        // Refresh Button
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            border: Border.all(color: Colors.blue.shade600, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            onPressed: _isRefreshing ? null : _fetchStaffDashboardData,
            icon: const Icon(Icons.refresh, color: Colors.blue, size: 20),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  // ---- TOP SUMMARY STATS ----
  Widget _buildTopSummaryStats(bool isDark, bool isMobile) {
    final List<Map<String, dynamic>> stats = [
      {
        'label': 'Total Trips',
        'value': _totalTrips.toString(),
        'icon': Icons.inventory_2_outlined,
        'color': isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        'filter': 'All',
      },
      {
        'label': 'Scheduled',
        'value': _scheduledTrips.toString(),
        'icon': Icons.check_circle_outline,
        'color': const Color(0xFF10B981),
        'filter': 'Scheduled',
      },
      {
        'label': 'Unassigned',
        'value': _unassignedTrips.toString(),
        'icon': Icons.assignment_late_outlined,
        'color': const Color(0xFFF59E0B),
        'filter': 'Unassigned',
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
        'icon': Icons.timer_off,
        'color': Colors.grey.shade600,
        'filter': 'Expired',
      },
    ];

    Widget buildCard(Map<String, dynamic> stat) {
      final isSelected = _statusFilter == stat['filter'];
      return InkWell(
        onTap: () {
          setState(() => _statusFilter = stat['filter']);
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
              padding: EdgeInsets.only(right: stat == stats.last ? 0 : 16.0),
              child: buildCard(stat),
            ),
          );
        }).toList(),
      );
    }
  }

  // ---- CALENDAR ----
  Widget _buildCompactCalendarGrid(bool isDark) {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
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
                  _monthYearFormat(_selectedMonth),
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
                        () => _selectedMonth = DateTime(
                          _selectedMonth.year,
                          _selectedMonth.month - 1,
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
                        () => _selectedMonth = DateTime(
                          _selectedMonth.year,
                          _selectedMonth.month + 1,
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
                // 🔥 Replaced GridView.builder entirely for Staff
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
                      _selectedMonth.year,
                      _selectedMonth.month,
                      day,
                    );
                    final trips = _getTripsForDate(date);
                    final hasTrips = trips.isNotEmpty;

                    // Fetch blackout info
                    final blackout = _blackoutForDate(date);
                    final isBlocked = blackout != null;

                    final isSelected =
                        _selectedDate != null &&
                        _selectedDate!.year == date.year &&
                        _selectedDate!.month == date.month &&
                        _selectedDate!.day == date.day;
                    final isToday =
                        DateTime.now().year == date.year &&
                        DateTime.now().month == date.month &&
                        DateTime.now().day == date.day;

                    return GestureDetector(
                      onTap: () {
                        // Display reason for block to staff
                        if (isBlocked) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Blocked Reason: ${blackout['reason']}',
                              ),
                              backgroundColor: const Color(0xFFEF4444),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }

                        setState(() {
                          _selectedDate = isSelected ? null : date;
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF3B82F6)
                              : (isBlocked
                                    ? const Color(0xFFFEE2E2)
                                    : (hasTrips
                                          ? (isDark
                                                ? Colors.blue.withValues(
                                                    alpha: 0.2,
                                                  )
                                                : const Color(0xFFEFF6FF))
                                          : (isDark
                                                ? const Color(0xFF1E293B)
                                                : Colors.white))),
                          border: Border.all(
                            color: isToday
                                ? const Color(0xFFF59E0B)
                                : isBlocked
                                ? const Color(0xFFEF4444)
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
                                  ? const Color(0xFFEF4444)
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

  // ---- TRIP LIST ----
  Widget _buildTripListView(bool isDark) {
    final List<dynamic> displayedTrips = _getFilteredTrips();
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
                              ? 'Filtered Results'
                              : 'Schedule',
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
                    '${displayedTrips.length} results',
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
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayedTrips.length,
                  itemBuilder: (context, index) {
                    final trip = displayedTrips[index];
                    final statusStr =
                        trip['trip_status']?.toString() ?? 'Unknown';
                    final isRejected = statusStr.toLowerCase().contains(
                      'rejected',
                    );
                    final bool needsAssignment =
                        (trip['user_id'] == null ||
                            trip['vehicle_id'] == null) &&
                        !isRejected;

                    return TripCard(
                      trip: trip,
                      backendUrl: backendUrl,
                      needsAssignment: needsAssignment,
                      isModal: false,
                      isDark: isDark,
                      borderColor: borderColor,
                      onAssign: () {
                        setState(() => _isLoading = true);
                        _fetchStaffDashboardData();
                      },
                    );
                  },
                ),
        ],
      ),
    );
  }
}

// ─── UNIFIED TRIP CARD (Modernized) ───
class TripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final String backendUrl;
  final bool needsAssignment;
  final bool isModal;
  final bool isDark;
  final Color borderColor;
  final VoidCallback onAssign;

  const TripCard({
    super.key,
    required this.trip,
    required this.backendUrl,
    required this.needsAssignment,
    this.isModal = false,
    required this.isDark,
    required this.borderColor,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final statusStr = trip['trip_status']?.toString() ?? 'Unknown';
    final isRejected = statusStr.toLowerCase().contains('rejected');
    final isExpired = statusStr.toLowerCase().contains('expired');
    final isUnassigned = needsAssignment && !isRejected && !isExpired;

    Color statusColor = const Color(0xFF10B981); // Default to Completed Green
    String badgeText = statusStr.toUpperCase();

    if (isRejected) {
      statusColor = const Color(0xFFEF4444);
      badgeText = 'REJECTED';
    } else if (isUnassigned) {
      statusColor = const Color(0xFFF59E0B);
      badgeText = 'UNASSIGNED';
    } else if (isExpired) {
      statusColor = Colors.grey.shade600;
      badgeText = 'EXPIRED';
    } else if (statusStr.toLowerCase().contains('ongoing')) {
      statusColor = const Color(0xFF3B82F6);
      badgeText = 'ONGOING';
    } else if (statusStr.toLowerCase().contains('scheduled')) {
      statusColor = const Color(0xFFF59E0B);
      badgeText = 'SCHEDULED';
    }

    final String routeName = trip['route_name'] ?? 'Unspecified Route';
    final String company = trip['client_company'] ?? 'Unknown Client';
    final String passengers = '${trip['passenger_count'] ?? 0} pax';
    final String distance = '${trip['route_distance'] ?? 0} km';
    final String timeRange = _formatTimeRange(
      trip['departure_time'],
      trip['estimated_arrival_time'],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _cardIconText(Icons.access_time, timeRange, isDark),
                        _cardIconText(Icons.business_outlined, company, isDark),
                        _cardIconText(Icons.people_outline, passengers, isDark),
                        _cardIconText(Icons.straighten, distance, isDark),
                        if (trip['driver_name'] != null &&
                            !isUnassigned &&
                            !isRejected)
                          _cardIconText(
                            Icons.person_outline,
                            trip['driver_name'],
                            isDark,
                          ),
                        if (trip['vehicle_plate'] != null &&
                            !isUnassigned &&
                            !isRejected)
                          _cardIconText(
                            Icons.directions_car_outlined,
                            trip['vehicle_plate'],
                            isDark,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    badgeText,
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

          if (isUnassigned) ...[
            const SizedBox(height: 16),
            Skeleton.ignore(
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (isModal) Navigator.pop(context);
                          _showAssignModal(context);
                        },
                        icon: const Icon(
                          Icons.assignment_ind,
                          color: Colors.white,
                          size: 16,
                        ),
                        label: const Text(
                          'Assign',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: () => _rejectTrip(context),
                        icon: const Icon(
                          Icons.cancel,
                          color: Color(0xFFEF4444),
                          size: 16,
                        ),
                        label: const Text(
                          'Reject',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  void _showAssignModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AssignTripDialog(
        trip: trip,
        backendUrl: backendUrl,
        onSuccess: onAssign,
      ),
    );
  }

  Future<void> _rejectTrip(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reasonController = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Reject Request?",
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason for cancellation/rejection *',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              "Cancel",
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isNotEmpty) Navigator.pop(ctx, value);
            },
            child: const Text(
              "Reject",
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    reasonController.dispose();

    if (reason == null) return;

    try {
      final res = await http.post(
        Uri.parse('$backendUrl/schedules/reject'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "trip_id": trip['trip_id'],
          "rejection_reason": reason,
        }),
      );
      if (res.statusCode == 200 && context.mounted) {
        if (isModal) Navigator.pop(context);
        onAssign();
      }
    } catch (e) {
      debugPrint("Reject Error: $e");
    }
  }
}

// ─── ASSIGNMENT MODAL ───
class AssignTripDialog extends StatefulWidget {
  final Map<String, dynamic> trip;
  final String backendUrl;
  final VoidCallback onSuccess;

  const AssignTripDialog({
    super.key,
    required this.trip,
    required this.backendUrl,
    required this.onSuccess,
  });

  @override
  State<AssignTripDialog> createState() => _AssignTripDialogState();
}

class _AssignTripDialogState extends State<AssignTripDialog> {
  bool _isLoadingOptions = true;
  bool _isSubmitting = false;

  List<dynamic> _drivers = [];
  List<dynamic> _vehicles = [];
  bool _isBlockedDate = false;
  String? _availabilityMessage;

  String? _selectedDriverUuid;
  String? _selectedVehicleId;

  @override
  void initState() {
    super.initState();
    _fetchAvailability();
  }

  Future<void> _fetchAvailability() async {
    try {
      final String tripDate = widget.trip['schedule_date'];
      final String cacheBuster = DateTime.now().millisecondsSinceEpoch
          .toString();

      final res = await http.get(
        Uri.parse(
          '${widget.backendUrl}/schedules/dispatch-options?date=$tripDate&cb=$cacheBuster',
        ),
      );

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _drivers = data['drivers'] ?? [];
          _vehicles = data['vehicles'] ?? [];
          _isBlockedDate = data['blocked'] == true;
          _availabilityMessage =
              data['block_reason'] ??
              (data['availability_message']?['drivers'] == null &&
                      data['availability_message']?['vehicles'] == null
                  ? null
                  : '${data['availability_message']?['drivers'] ?? ''} ${data['availability_message']?['vehicles'] ?? ''}'
                        .trim());
          _isLoadingOptions = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingOptions = false);
    }
  }

  Future<void> _submitAssignment() async {
    if (_isBlockedDate ||
        _selectedDriverUuid == null ||
        _selectedVehicleId == null)
      return;
    setState(() => _isSubmitting = true);

    try {
      final res = await http.post(
        Uri.parse('${widget.backendUrl}/schedules/assign'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "trip_id": widget.trip['trip_id'],
          "driver_uuid": _selectedDriverUuid,
          "vehicle_id": int.parse(_selectedVehicleId!),
        }),
      );
      if (res.statusCode == 200 && mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Trip assigned successfully!"),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (mounted) {
        final responseData = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(responseData['message'] ?? 'Assignment blocked.'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    dynamic currentDriver;
    try {
      currentDriver = _drivers.firstWhere(
        (d) => d['user_id'] == _selectedDriverUuid,
      );
    } catch (_) {}

    dynamic currentVehicle;
    try {
      currentVehicle = _vehicles.firstWhere(
        (v) => v['vehicle_id'].toString() == _selectedVehicleId,
      );
    } catch (_) {}

    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        "Dispatch: ${widget.trip['route_name']}",
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
      content: _isLoadingOptions
          ? const SizedBox(
              height: 100,
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
              ),
            )
          : SizedBox(
              width: isMobile ? double.infinity : 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Date: ${widget.trip['schedule_date']}",
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_isBlockedDate || _availabilityMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF450A0A)
                            : const Color(0xFFFEF2F2),
                        border: Border.all(color: const Color(0xFFEF4444)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _availabilityMessage ??
                            'Assignment blocked for this date.',
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                  if (_drivers.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF450A0A)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "⚠️ No drivers available for this date.",
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    _SearchableDropdown<dynamic>(
                      labelText: "Select Driver",
                      value: currentDriver,
                      items: _drivers,
                      itemAsString: (d) =>
                          d['full_name']?.toString() ?? 'Unknown',
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedDriverUuid = val['user_id']);
                        }
                      },
                      isDark: isDark,
                    ),

                  const SizedBox(height: 16),

                  if (_vehicles.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF450A0A)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "⚠️ No vehicles available for this date.",
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    _SearchableDropdown<dynamic>(
                      labelText: "Select Vehicle",
                      value: currentVehicle,
                      items: _vehicles,
                      itemAsString: (v) =>
                          "${v['plate_number']} (${v['bus_type']})",
                      onChanged: (val) {
                        if (val != null) {
                          setState(
                            () => _selectedVehicleId = val['vehicle_id']
                                .toString(),
                          );
                        }
                      },
                      isDark: isDark,
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            "Cancel",
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          onPressed:
              (_isSubmitting ||
                  _isBlockedDate ||
                  _selectedDriverUuid == null ||
                  _selectedVehicleId == null)
              ? null
              : _submitAssignment,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  "Confirm Assignment",
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

// ─── SEARCHABLE DROPDOWN COMPONENTS ───
class _SearchableDropdown<T> extends StatefulWidget {
  final String labelText;
  final T? value;
  final List<T> items;
  final String Function(T) itemAsString;
  final void Function(T?) onChanged;
  final bool isDark;

  const _SearchableDropdown({
    required this.labelText,
    required this.value,
    required this.items,
    required this.itemAsString,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<_SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<_SearchableDropdown<T>> {
  Future<void> _showSearchDialog() async {
    final T? selected = await showDialog<T>(
      context: context,
      builder: (context) {
        return _SearchDialog<T>(
          items: widget.items,
          itemAsString: widget.itemAsString,
          labelText: widget.labelText,
          isDark: widget.isDark,
        );
      },
    );
    if (selected != null) {
      widget.onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color fieldColor = widget.isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF8FAFC);
    final String displayText = widget.value == null
        ? ''
        : widget.itemAsString(widget.value as T);

    return InkWell(
      onTap: _showSearchDialog,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.labelText,
          labelStyle: TextStyle(
            fontSize: 13,
            color: widget.isDark
                ? Colors.grey.shade400
                : const Color(0xFF64748B),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          filled: true,
          fillColor: fieldColor,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          displayText.isEmpty ? "Select..." : displayText,
          style: TextStyle(
            fontSize: 14,
            color: displayText.isEmpty
                ? Colors.grey.shade500
                : (widget.isDark ? Colors.white : Colors.black87),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _SearchDialog<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) itemAsString;
  final String labelText;
  final bool isDark;

  const _SearchDialog({
    required this.items,
    required this.itemAsString,
    required this.labelText,
    required this.isDark,
  });

  @override
  State<_SearchDialog<T>> createState() => _SearchDialogState<T>();
}

class _SearchDialogState<T> extends State<_SearchDialog<T>> {
  late List<T> filteredItems;
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filteredItems = widget.items;
    searchController.addListener(() {
      setState(() {
        final query = searchController.text.toLowerCase();
        filteredItems = widget.items
            .where(
              (item) => widget.itemAsString(item).toLowerCase().contains(query),
            )
            .toList();
      });
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.labelText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: textColor),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: searchController,
              autofocus: true,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Search...",
                hintStyle: TextStyle(color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filteredItems.isEmpty
                  ? Center(
                      child: Text(
                        "No results found.",
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return ListTile(
                          title: Text(
                            widget.itemAsString(item),
                            style: TextStyle(color: textColor, fontSize: 14),
                          ),
                          onTap: () {
                            Navigator.pop(context, item);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
