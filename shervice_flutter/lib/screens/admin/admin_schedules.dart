import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import '../../constant.dart';
import '../../widgets/shared/universal_pagination.dart';

class AdminSchedules extends StatefulWidget {
  const AdminSchedules({super.key});

  @override
  State<AdminSchedules> createState() => _AdminSchedulesState();
}

class _AdminSchedulesState extends State<AdminSchedules> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<dynamic> _allSchedules = [];
  List<dynamic> _filteredSchedules = [];

  DateTime _selectedMonth = DateTime.now();
  DateTime? _selectedDate;

  String _searchQuery = '';
  String _statusFilter = 'All';
  final List<String> _statusOptions = [
    'All',
    'Scheduled',
    'Ongoing',
    'Completed',
    'Rejected',
    'Expired',
  ];

  int _currentPage = 0;
  final int _itemsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _fetchSchedulesFromDatabase();
  }

  Future<void> _fetchSchedulesFromDatabase() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _isLoading = true;
    });

    final String url = '$backendUrl/trips';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          _allSchedules = data;
        } else if (data is Map && data.containsKey('trips')) {
          _allSchedules = data['trips'] ?? [];
        } else if (data is Map && data.containsKey('sample_data_payload')) {
          _allSchedules = data['sample_data_payload'] ?? [];
        } else {
          _allSchedules = [];
        }
      } else {
        debugPrint("Schedule request failed: ${response.statusCode}");
        _allSchedules = [];
      }
    } catch (e) {
      debugPrint("❌ Error reading live trip schedule streams: $e");
      _allSchedules = [];
    } finally {
      if (mounted) {
        _applyFiltersAndSort();
        setState(() {
          _isRefreshing = false;
          _isLoading = false;
        });
      }
    }
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

  void _applyFiltersAndSort() {
    List<dynamic> temp = _allSchedules.where((trip) {
      final routeName = (trip['route_name'] ?? '').toString().toLowerCase();
      final userAccount = trip['user_account'] as Map<String, dynamic>?;
      final driverName =
          (userAccount != null ? userAccount['full_name'] ?? '' : '')
              .toString()
              .toLowerCase();
      final tripId = (trip['trip_id'] ?? '').toString().toLowerCase();

      final tripStatus = (trip['trip_status'] ?? 'Scheduled')
          .toString()
          .toLowerCase();

      final matchesSearch =
          routeName.contains(_searchQuery.toLowerCase()) ||
          driverName.contains(_searchQuery.toLowerCase()) ||
          tripId.contains(_searchQuery.toLowerCase());

      bool matchesStatus = true;
      if (_statusFilter != 'All') {
        if (_statusFilter == 'Ongoing') {
          matchesStatus =
              tripStatus.contains('ongoing') ||
              tripStatus.contains('in progress');
        } else if (_statusFilter == 'Rejected') {
          matchesStatus =
              tripStatus.contains('reject') || tripStatus.contains('cancel');
        } else {
          matchesStatus = tripStatus.contains(_statusFilter.toLowerCase());
        }
      }

      return matchesSearch && matchesStatus;
    }).toList();

    temp.sort((a, b) {
      final dateA = (a['schedule_date'] ?? '').toString();
      final timeA = (a['departure_time'] ?? '').toString();
      final dateB = (b['schedule_date'] ?? '').toString();
      final timeB = (b['departure_time'] ?? '').toString();
      return "$dateA $timeA".compareTo("$dateB $timeB");
    });

    setState(() {
      _filteredSchedules = temp;
      _currentPage = 0;
    });
  }

  List<dynamic> _getTripsForDate(DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _filteredSchedules.where((trip) {
      final tripDateRaw = (trip['schedule_date'] ?? '').toString();
      if (tripDateRaw.length >= 10) {
        final tripDate = tripDateRaw.substring(0, 10);
        return tripDate == dateStr;
      }
      return false;
    }).toList();
  }

  List<dynamic> _getDisplayedTrips() {
    if (_selectedDate == null) return _filteredSchedules;
    return _getTripsForDate(_selectedDate!);
  }

  Iterable<dynamic> get _baseSchedules => _allSchedules.where((trip) {
    final routeName = (trip['route_name'] ?? '').toString().toLowerCase();
    final userAccount = trip['user_account'] as Map<String, dynamic>?;
    final driverName =
        (userAccount != null ? userAccount['full_name'] ?? '' : '')
            .toString()
            .toLowerCase();
    final tripId = (trip['trip_id'] ?? '').toString().toLowerCase();
    return routeName.contains(_searchQuery.toLowerCase()) ||
        driverName.contains(_searchQuery.toLowerCase()) ||
        tripId.contains(_searchQuery.toLowerCase());
  });

  int get _totalTrips => _baseSchedules.length;

  int get _scheduledTrips => _baseSchedules.where((t) {
    return (t['trip_status'] ?? 'Scheduled').toString().toLowerCase().contains(
      'scheduled',
    );
  }).length;

  int get _ongoingTrips => _baseSchedules.where((t) {
    final s = (t['trip_status'] ?? '').toString().toLowerCase();
    return s.contains('ongoing') ||
        s.contains('in progress') ||
        s.contains('active');
  }).length;

  int get _completedTrips => _baseSchedules.where((t) {
    return (t['trip_status'] ?? '').toString().toLowerCase().contains(
      'completed',
    );
  }).length;

  int get _rejectedTrips => _baseSchedules.where((t) {
    final s = (t['trip_status'] ?? '').toString().toLowerCase();
    return s.contains('reject') || s.contains('cancel');
  }).length;

  int get _expiredTrips => _baseSchedules.where((t) {
    return (t['trip_status'] ?? '').toString().toLowerCase().contains(
      'expired',
    );
  }).length;

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('ongoing') || s.contains('progress') || s.contains('active'))
      return const Color(0xFFF59E0B);
    if (s.contains('completed')) return const Color(0xFF10B981);
    if (s.contains('reject') || s.contains('cancel'))
      return const Color(0xFFEF4444);
    if (s.contains('expired')) return Colors.grey.shade600;
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

  void _showTripDetails(Map<String, dynamic> trip) {
    final userAccount = trip['user_account'] as Map<String, dynamic>?;
    final vehicle = trip['vehicle'] as Map<String, dynamic>?;

    // Type-safe dynamic fallback for the company value
    final dynamic rawCompany = trip['client_company'] ?? trip['oic_profile'];
    String company = 'Unassigned Company';
    if (rawCompany is String) {
      company = rawCompany;
    } else if (rawCompany is Map) {
      company = rawCompany['company_name']?.toString() ?? 'Unassigned Company';
    }

    final String driver = userAccount != null
        ? (userAccount['full_name'] ?? 'Not Assigned')
        : 'Not Assigned';
    final String email = userAccount != null
        ? (userAccount['email'] ?? 'N/A')
        : 'N/A';
    final String plate = vehicle != null
        ? (vehicle['plate_number'] ?? 'No Shuttle')
        : 'No Shuttle';
    final String type = vehicle != null
        ? (vehicle['bus_type'] ?? 'Standard')
        : 'Standard';

    final String route = trip['route_name'] ?? 'Unassigned Route';
    final String status = trip['trip_status'] ?? 'Scheduled';
    final String date = trip['schedule_date'] ?? 'TBD';
    final String departure = trip['departure_time'] ?? 'TBD';
    final String arrival =
        trip['estimated_arrival_time'] ?? trip['arrival_time'] ?? 'TBD';
    final String actDeparture = _formatTimestamp(trip['actual_start_time']);
    final String actArrival = _formatTimestamp(trip['actual_end_time']);
    final String notes = trip['notes'] ?? 'No additional notes.';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Theme.of(context).cardColor,
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Trip Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _detailRow('Route', route),
              _detailRow('Status', status, color: _getStatusColor(status)),
              _detailRow('Driver', driver),
              _detailRow('Email', email),
              _detailRow('Vehicle', '$plate ($type)'),
              _detailRow('Company', company),
              _detailRow('Date', date),
              _detailRow('Sched Depart', departure),
              _detailRow('Sched Arrive', arrival),
              _detailRow(
                'Actual Left',
                actDeparture,
                color: const Color(0xFF3B82F6),
              ),
              _detailRow(
                'Actual Arrived',
                actArrival,
                color: const Color(0xFF10B981),
              ),
              _detailRow('Notes', notes, isNotes: true),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    Color? color,
    bool isNotes = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color:
                    color ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
                fontSize: 13,
                height: isNotes ? 1.4 : 1.2,
              ),
            ),
          ),
        ],
      ),
    );
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
        onRefresh: _fetchSchedulesFromDatabase,
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Schedule Management',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Monitor and manage all scheduled trips for your fleet operations.',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildSearchAndFilterRow(isDark, isMobile),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Schedule Management',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Monitor and manage all scheduled trips for your fleet operations.',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
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

  Widget _buildSearchAndFilterRow(bool isDark, bool isMobile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: isMobile ? 160 : 220,
          height: 44,
          child: TextField(
            onChanged: (value) {
              _searchQuery = value;
              _applyFiltersAndSort();
            },
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search routes, drivers or trip IDs...',
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
        const SizedBox(width: 8),
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
              items: _statusOptions.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() {
                    _statusFilter = newValue;
                    _applyFiltersAndSort();
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
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            border: Border.all(color: Colors.blue.shade600, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            onPressed: _isRefreshing ? null : _fetchSchedulesFromDatabase,
            icon: const Icon(Icons.refresh, color: Colors.blue, size: 20),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

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
        'label': 'Completed',
        'value': _completedTrips.toString(),
        'icon': Icons.check,
        'color': const Color(0xFF10B981),
        'filter': 'Completed',
      },
      {
        'label': 'Ongoing',
        'value': _ongoingTrips.toString(),
        'icon': Icons.location_on,
        'color': const Color(0xFFF59E0B),
        'filter': 'Ongoing',
      },
      {
        'label': 'Assigned',
        'value': _scheduledTrips.toString(),
        'icon': Icons.sync,
        'color': const Color(0xFF3B82F6),
        'filter': 'Scheduled',
      },
      {
        'label': 'Rejected',
        'value': _rejectedTrips.toString(),
        'icon': Icons.close,
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
          setState(() {
            _statusFilter = stat['filter'];
            _applyFiltersAndSort();
          });
        },
        borderRadius: BorderRadius.circular(40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? stat['color'].withOpacity(0.1)
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
                        setState(() {
                          _currentPage = 0;
                          if (isSelected) {
                            _selectedDate = null;
                          } else {
                            _selectedDate = date;
                          }
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF3B82F6)
                              : (hasTrips
                                    ? (isDark
                                          ? Colors.blue.withOpacity(0.2)
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
    final List<dynamic> allDisplayedTrips = _getDisplayedTrips();
    final int totalItems = allDisplayedTrips.length;
    final int totalPages = (totalItems / _itemsPerPage).ceil();

    final List<dynamic> paginatedTrips = _isLoading
        ? List.generate(
            4,
            (index) => {
              'route_name': 'Skeleton Route Data Masked',
              'trip_status': 'Scheduled',
              'schedule_date': '2026-08-28',
              'departure_time': '08:00 AM',
              'actual_start_time': null,
              'actual_end_time': null,
              'user_account': {'full_name': 'Skeleton Driver Name'},
              'vehicle': {
                'plate_number': 'SKL 123',
                'bus_type': 'Skeleton Type',
              },
              'client_company': {'company_name': 'Skeleton Company Name'},
            },
          )
        : (() {
            if (allDisplayedTrips.isEmpty) return <dynamic>[];
            int start = _currentPage * _itemsPerPage;
            int end = min(start + _itemsPerPage, totalItems);
            return allDisplayedTrips.sublist(start, end);
          })();

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
                          _selectedDate == null
                              ? 'All Trips'
                              : 'Trips for ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
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
                        ? Colors.blue.withOpacity(0.2)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$totalItems trips',
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
          !_isLoading && paginatedTrips.isEmpty
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
                        'No trips scheduled.',
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
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: paginatedTrips.length,
                  itemBuilder: (context, index) {
                    final trip = paginatedTrips[index];
                    return _buildTripCard(trip, isDark, borderColor);
                  },
                ),
          if (!_isLoading && totalItems > 0)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: UniversalPagination(
                currentPage: _currentPage,
                totalPages: totalPages,
                totalItems: totalItems,
                itemsPerPage: _itemsPerPage,
                itemName: 'trips',
                onNextPage: _currentPage < totalPages - 1
                    ? () => setState(() => _currentPage++)
                    : null,
                onPrevPage: _currentPage > 0
                    ? () => setState(() => _currentPage--)
                    : null,
              ),
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
    final userAccount = trip['user_account'] as Map<String, dynamic>?;
    final vehicle = trip['vehicle'] as Map<String, dynamic>?;

    // Type-safe dynamic fallback for the company value
    final dynamic rawCompany = trip['client_company'] ?? trip['oic_profile'];
    String company = 'Unassigned Company';
    if (rawCompany is String) {
      company = rawCompany;
    } else if (rawCompany is Map) {
      company = rawCompany['company_name']?.toString() ?? 'Unassigned Company';
    }

    final String driver = userAccount != null
        ? (userAccount['full_name'] ?? 'No Assigned Driver')
        : 'No Assigned Driver';
    final String plate = vehicle != null
        ? (vehicle['plate_number'] ?? 'No Shuttle Linked')
        : 'No Shuttle Linked';
    final String type = vehicle != null
        ? (vehicle['bus_type'] ?? 'Standard Shuttle')
        : 'Standard Shuttle';

    final String dateStr = trip['schedule_date'] ?? '';
    final String timeStr = trip['departure_time'] ?? 'TBD';
    final String deploymentTime = dateStr.isNotEmpty
        ? "$dateStr @ $timeStr"
        : timeStr;
    final String status = trip['trip_status'] ?? 'Scheduled';
    final String routeName = trip['route_name'] ?? 'Unassigned Route';
    final String tripId = (trip['trip_id'] ?? 'N/A').toString();
    final statusColor = _getStatusColor(status);

    final rawActStart = trip['actual_start_time'];
    final rawActEnd = trip['actual_end_time'];
    final bool hasActual = rawActStart != null || rawActEnd != null;
    final String actStartStr = _formatTimestamp(rawActStart);
    final String actEndStr = rawActEnd != null
        ? _formatTimestamp(rawActEnd)
        : (status.toLowerCase().contains('ongoing') ? 'En Route' : '--:--');

    return InkWell(
      onTap: () => _showTripDetails(trip),
      child: Container(
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
                    'TRIP-$tripId • $routeName',
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
                      _cardIconText(
                        Icons.airport_shuttle_outlined,
                        '$plate ($type)',
                        isDark,
                      ),
                      _cardIconText(
                        Icons.access_time,
                        'Sched: $deploymentTime',
                        isDark,
                      ),
                      if (hasActual)
                        _cardIconText(
                          Icons.timer_outlined,
                          'Actual: $actStartStr → $actEndStr',
                          isDark,
                          customColor: rawActEnd != null
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                      _cardIconText(Icons.business_outlined, company, isDark),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
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
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: isDark
                      ? Colors.grey.shade600
                      : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ],
        ),
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
}
