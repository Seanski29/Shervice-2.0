import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import '../../constant.dart';

class DriverSchedules extends StatefulWidget {
  final String driverId;
  const DriverSchedules({super.key, required this.driverId});

  @override
  State<DriverSchedules> createState() => _DriverSchedulesState();
}

class _DriverSchedulesState extends State<DriverSchedules> {
  // --- STATE ---
  bool _isLoading = true;
  List<dynamic> _myTrips = [];
  String _currentSort = 'Date (Newest)';
  final List<String> _sortOptions = ['Date (Newest)', 'Date (Oldest)'];

  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;
  bool _calendarExpanded = false;
  bool _showAllCompleted = false;
  int? _selectedTripId;
  
  // New state for making stats chips clickable filters
  String? _activeFilter;

  @override
  void initState() {
    super.initState();
    _fetchMySchedules();
  }

  // --- API ---
  Future<void> _fetchMySchedules() async {
    try {
      final res = await http.get(
        Uri.parse('$backendUrl/schedules/driver/${widget.driverId}'),
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _myTrips = data['data'] ?? [];
          _isLoading = false;
          _selectedDate = null;
          _showAllCompleted = false;
        });
      } else if (mounted) {
        setState(() {
          _myTrips = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _myTrips = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateTripStatus(int tripId, String newStatus) async {
    try {
      final res = await http.post(
        Uri.parse('$backendUrl/schedules/update-status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'trip_id': tripId, 'status': newStatus}),
      );
      if (res.statusCode == 200 && mounted) {
        _fetchMySchedules();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'Completed'
                  ? 'Trip Finished!'
                  : 'Trip Started! Drive safely.',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating trip: $e');
    }
  }

  void _showTripDetails(Map<String, dynamic> trip) {
    final status = trip['trip_status']?.toString() ?? 'Scheduled';
    final route = trip['route_name']?.toString() ?? 'Unassigned Route';
    final vehicle = trip['plate_number']?.toString() ?? 'Unassigned';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(route, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailLine('Status', status),
            _detailLine('Date', trip['schedule_date']?.toString() ?? 'TBD'),
            _detailLine('Time', _timeValue(trip['departure_time'])),
            _detailLine(
              'Est. Arrival',
              _timeValue(trip['estimated_arrival_time']),
            ),
            _detailLine('Vehicle', vehicle),
            _detailLine(
              'Passengers',
              '${trip['passenger_count'] ?? trip['passengers'] ?? 0}',
            ),
            _detailLine('Distance', '${trip['route_distance'] ?? 0} km'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey.shade400 
                  : Colors.grey.shade600
              ),
            ),
          ),
          Expanded(
            child: Text(
              value, 
              style: const TextStyle(fontWeight: FontWeight.w500)
            )
          ),
        ],
      ),
    );
  }

  String _timeValue(dynamic value) {
    final text = value?.toString() ?? '';
    return text.length >= 5
        ? text.substring(0, 5)
        : (text.isEmpty ? 'TBD' : text);
  }

  // --- UTILS ---
  DateTime? _parseTripDate(String? value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  // --- FILTER & SORT ---
  List<dynamic> _getFilteredTrips() {
    List<dynamic> displayTrips = _isLoading
        ? List.generate(
            5,
            (index) => {
              'trip_id': index + 1,
              'route_name': 'Loading Route Data',
              'trip_status': 'Scheduled',
              'schedule_date': DateTime.now().toIso8601String(),
              'departure_time': '08:00',
              'estimated_arrival_time': '09:00',
              'plate_number': 'Loading Vehicle',
              'passenger_count': 0,
            },
          )
        : _myTrips;

    // Apply Active Filter from Stats Chips
    if (_activeFilter != null) {
      displayTrips = displayTrips.where((t) => t['trip_status']?.toString().toLowerCase() == _activeFilter!.toLowerCase()).toList();
    }

    if (_selectedDate == null) return displayTrips;
    
    return displayTrips.where((trip) {
      final tripDate = _parseTripDate(trip['schedule_date']?.toString());
      return tripDate != null &&
          tripDate.year == _selectedDate!.year &&
          tripDate.month == _selectedDate!.month &&
          tripDate.day == _selectedDate!.day;
    }).toList();
  }

  List<dynamic> _sortTrips(List<dynamic> trips) {
    trips.sort((a, b) {
      final dateA = _parseTripDate(a['schedule_date']?.toString());
      final dateB = _parseTripDate(b['schedule_date']?.toString());
      if (_currentSort == 'Date (Newest)') {
        return (dateB ?? DateTime(0)).compareTo(dateA ?? DateTime(0));
      } else {
        return (dateA ?? DateTime(2100)).compareTo(dateB ?? DateTime(2100));
      }
    });
    return trips;
  }

  List<dynamic> get _scheduledTrips {
    final scheduled = _getFilteredTrips()
        .where((t) => t['trip_status']?.toString().toLowerCase() == 'scheduled')
        .toList();
    return _sortTrips(scheduled);
  }

  List<dynamic> get _ongoingTrips {
    final ongoing = _getFilteredTrips()
        .where((t) => t['trip_status']?.toString().toLowerCase() == 'ongoing')
        .toList();
    return _sortTrips(ongoing);
  }

  List<dynamic> get _completedTrips {
    final completed = _getFilteredTrips()
        .where((t) => t['trip_status']?.toString().toLowerCase() == 'completed')
        .toList();
    return _sortTrips(completed);
  }

  bool get _isFiltered => _selectedDate != null || _activeFilter != null;

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate =
          _selectedDate != null &&
              _selectedDate!.year == date.year &&
              _selectedDate!.month == date.month &&
              _selectedDate!.day == date.day
          ? null
          : date;
      _showAllCompleted = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _calendarMonth = DateTime(
        _calendarMonth.year,
        _calendarMonth.month + delta,
      );
    });
  }

  // --- BUILD ---
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 800;
    final double horizontalPadding = isMobile ? 16.0 : 32.0;
    final totalTrips = _myTrips.length;
    
    // Uniform Theme Colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);

    // Calculate raw totals for the stats chips (ignoring filters)
    final rawScheduled = _myTrips.where((t) => t['trip_status']?.toString().toLowerCase() == 'scheduled').length;
    final rawOngoing = _myTrips.where((t) => t['trip_status']?.toString().toLowerCase() == 'ongoing').length;
    final rawCompleted = _myTrips.where((t) => t['trip_status']?.toString().toLowerCase() == 'completed').length;

    return Scaffold(
      backgroundColor: bgColor,
      body: Skeletonizer(
        enabled: _isLoading,
        child: RefreshIndicator(
          onRefresh: _fetchMySchedules,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── HEADER ──
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Schedule',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedDate == null
                                ? '$totalTrips trips assigned'
                                : '${_getFilteredTrips().length} on ${_selectedDate!.day}/${_selectedDate!.month}',
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
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        border: Border.all(
                          color: Colors.blue.shade600,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        onPressed: _fetchMySchedules,
                        icon: const Icon(
                          Icons.refresh,
                          color: Colors.blue,
                          size: 20,
                        ),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                        tooltip: 'Refresh Schedules',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── STATS CHIPS (Clickable Filters) ──
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _statChip(
                      Icons.calendar_today,
                      '$rawScheduled',
                      'Scheduled',
                      const Color(0xFFF59E0B),
                      isDark,
                    ),
                    _statChip(
                      Icons.play_arrow,
                      '$rawOngoing',
                      'Ongoing',
                      const Color(0xFF3B82F6),
                      isDark,
                    ),
                    _statChip(
                      Icons.check_circle,
                      '$rawCompleted',
                      'Completed',
                      const Color(0xFF10B981),
                      isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── SORT ROW ──
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _currentSort,
                            isExpanded: true,
                            dropdownColor: cardColor,
                            icon: Icon(
                              Icons.sort,
                              size: 18,
                              color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                            items: _sortOptions.map((option) {
                              return DropdownMenuItem<String>(
                                value: option,
                                child: Text(option),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _currentSort = value);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    if (_isFiltered) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedDate = null;
                            _activeFilter = null;
                            _showAllCompleted = false;
                          });
                        },
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.blue.withValues(alpha: 0.2)
                                : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.close,
                                size: 16,
                                color: Color(0xFF3B82F6),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Clear Filter',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.blue.shade300
                                      : const Color(0xFF3B82F6),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),

                // ── TRIP SECTIONS ──
                if (!_isLoading && _getFilteredTrips().isEmpty)
                  _buildEmptyState(isDark, cardColor, borderColor)
                else ...[
                  if (_ongoingTrips.isNotEmpty)
                    _buildStatusSection(
                      'Ongoing',
                      _ongoingTrips,
                      const Color(0xFF3B82F6),
                      isDark,
                      cardColor,
                    ),
                  if (_scheduledTrips.isNotEmpty)
                    _buildStatusSection(
                      'Scheduled',
                      _scheduledTrips,
                      const Color(0xFFF59E0B),
                      isDark,
                      cardColor,
                    ),
                  if (_completedTrips.isNotEmpty)
                    _buildCompletedSection(isDark, cardColor),
                ],

                const SizedBox(height: 24),

                // ── CALENDAR ──
                _buildCalendarSection(isDark, cardColor, borderColor),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statChip(
    IconData icon,
    String count,
    String label,
    Color color,
    bool isDark,
  ) {
    final isSelected = _activeFilter == label;
    
    return InkWell(
      onTap: () {
        setState(() {
          _activeFilter = isSelected ? null : label;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected 
            ? color.withValues(alpha: isDark ? 0.25 : 0.15)
            : (isDark ? color.withValues(alpha: 0.05) : Colors.transparent),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              count,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color cardColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Icon(
            Icons.event_busy,
            size: 48,
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            _selectedDate == null && _activeFilter == null
                ? 'No trips assigned yet'
                : 'No trips match this filter',
            style: TextStyle(
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(
    String title,
    List<dynamic> trips,
    Color themeColor,
    bool isDark,
    Color cardColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? themeColor.withValues(alpha: 0.4)
              : themeColor.withValues(alpha: 0.5),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  title == 'Scheduled' ? Icons.schedule : Icons.play_arrow,
                  size: 18,
                  color: themeColor,
                ),
                const SizedBox(width: 8),
                Text(
                  '$title (${trips.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
          ...trips.asMap().entries.map((entry) {
            final int index = entry.key;
            final trip = entry.value;
            return _buildTripCard(
              trip, 
              isDark, 
              isLast: index == trips.length - 1
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCompletedSection(bool isDark, Color cardColor) {
    final allCompleted = _completedTrips;
    final displayTrips = _isFiltered || _showAllCompleted
        ? allCompleted
        : allCompleted.take(3).toList();
    final hasMore =
        !_isFiltered && allCompleted.length > 3 && !_showAllCompleted;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: isDark
                      ? Colors.grey.shade400
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
                Text(
                  'Completed (${allCompleted.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
          ...displayTrips.asMap().entries.map((entry) {
            final int index = entry.key;
            final trip = entry.value;
            return _buildTripCard(
              trip, 
              isDark, 
              isCompleted: true, 
              isLast: index == displayTrips.length - 1 && !hasMore
            );
          }),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: TextButton(
                  onPressed: () => setState(() => _showAllCompleted = true),
                  child: Text(
                    'Show ${allCompleted.length - 3} more completed trips',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF3B82F6),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTripCard(
    Map<String, dynamic> trip,
    bool isDark, {
    bool isCompleted = false,
    bool isLast = false,
  }) {
    final String status = trip['trip_status'] ?? 'Scheduled';
    final bool isScheduled = status.toLowerCase() == 'scheduled';
    final bool isOngoing = status.toLowerCase() == 'ongoing';
    final bool isExpired = status.toLowerCase() == 'expired';

    final bool hasOngoingTrip = _myTrips.any(
      (t) => t['trip_status']?.toString().toLowerCase() == 'ongoing',
    );

    Color statusColor = const Color(0xFF64748B);
    if (isOngoing) {
      statusColor = const Color(0xFF3B82F6);
    } else if (isCompleted) {
      statusColor = const Color(0xFF10B981);
    } else if (isScheduled) {
      statusColor = const Color(0xFFF59E0B);
    } else if (isExpired) {
      statusColor = Colors.grey.shade600;
    }

    final Color badgeBgColor = statusColor.withValues(alpha: 0.1);
    final Color badgeBorderColor = statusColor.withValues(alpha: 0.3);

    return InkWell(
      onTap: () {
        final tripId = int.tryParse(trip['trip_id']?.toString() ?? '');
        setState(() => _selectedTripId = tripId);
        _showTripDetails(trip);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: isLast 
            ? null 
            : Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
              ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    trip['route_name']?.toString() ?? 'Unassigned Route',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBgColor,
                    border: Border.all(color: badgeBorderColor),
                    borderRadius: BorderRadius.circular(6),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  trip['schedule_date']?.toString() ?? 'TBD',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade300 : const Color(0xFF475569),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  _timeValue(trip['departure_time']),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade300 : const Color(0xFF475569),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            // Render action button if the trip is active
            if (!isCompleted && !isExpired && (isScheduled || isOngoing)) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (isScheduled && hasOngoingTrip)
                      ? null
                      : () => _updateTripStatus(
                          int.tryParse(trip['trip_id']?.toString() ?? '') ?? 0,
                          isScheduled ? 'Ongoing' : 'Completed',
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (isScheduled && hasOngoingTrip)
                        ? Colors.grey.shade400
                        : (isScheduled
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF10B981)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  icon: Icon(
                    isScheduled ? Icons.play_arrow : Icons.check_circle,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: Text(
                    isScheduled
                        ? (hasOngoingTrip
                            ? 'Active Trip in Progress'
                            : 'Start Trip')
                        : 'Finish Trip',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- COLLAPSIBLE CALENDAR ---
  Widget _buildCalendarSection(bool isDark, Color cardColor, Color borderColor) {
    final tripCounts = <String, int>{};
    final completedCounts = <String, int>{};
    for (final trip in _myTrips) {
      final date = _parseTripDate(trip['schedule_date']?.toString());
      if (date == null) continue;
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      tripCounts[key] = (tripCounts[key] ?? 0) + 1;
      if (trip['trip_status']?.toString().toLowerCase() == 'completed') {
        completedCounts[key] = (completedCounts[key] ?? 0) + 1;
      }
    }

    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth = DateTime(
      _calendarMonth.year,
      _calendarMonth.month + 1,
      0,
    ).day;
    final firstWeekday = firstDay.weekday % 7;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _calendarExpanded = !_calendarExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(
                    _calendarExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Calendar View',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Text(
                    '${_calendarMonth.monthName} ${_calendarMonth.year}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.blue.shade300
                          : const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        color: isDark
                            ? Colors.grey.shade400
                            : const Color(0xFF64748B),
                      ),
                      IconButton(
                        onPressed: () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        color: isDark
                            ? Colors.grey.shade400
                            : const Color(0xFF64748B),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_calendarExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 7,
                    childAspectRatio: 0.68,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 4,
                    children: [
                      ...['S', 'M', 'T', 'W', 'T', 'F', 'S'].map(
                        (day) => Center(
                          child: Text(
                            day,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ),
                      ...List.generate(firstWeekday, (_) => const SizedBox()),
                      ...List.generate(daysInMonth, (index) {
                        final day = index + 1;
                        final date = DateTime(
                          _calendarMonth.year,
                          _calendarMonth.month,
                          day,
                        );
                        final key =
                            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                        final tripCount = tripCounts[key] ?? 0;
                        final completedCount = completedCounts[key] ?? 0;
                        final hasTrip = tripCount > 0;
                        final isSelected =
                            _selectedDate != null &&
                            _selectedDate!.year == date.year &&
                            _selectedDate!.month == date.month &&
                            _selectedDate!.day == date.day;

                        return GestureDetector(
                          onTap: hasTrip ? () => _onDateSelected(date) : null,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF3B82F6)
                                  : (hasTrip
                                      ? (isDark
                                          ? Colors.blue.withValues(
                                              alpha: 0.2,
                                            )
                                          : const Color(0xFFEFF6FF))
                                      : Colors.transparent),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF3B82F6)
                                    : (isDark
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade100),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 5,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$day',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isSelected
                                          ? Colors.white
                                          : (hasTrip
                                              ? (isDark
                                                  ? Colors.blue.shade300
                                                  : const Color(0xFF3B82F6))
                                              : (isDark
                                                  ? Colors.grey.shade400
                                                  : const Color(
                                                      0xFF0F172A,
                                                    ))),
                                      fontWeight: hasTrip
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (hasTrip) ...[
                                    const SizedBox(height: 3),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: completedCount == tripCount
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFF2563EB),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          completedCount == tripCount
                                              ? 'Done'
                                              : '$tripCount ${tripCount == 1 ? 'Trip' : 'Trips'}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 7,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.blue.withValues(alpha: 0.2)
                              : const Color(0xFFEFF6FF),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Scheduled Trips Available',
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
        ],
      ),
    );
  }
}

extension on DateTime {
  String get monthName {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month - 1];
  }
}