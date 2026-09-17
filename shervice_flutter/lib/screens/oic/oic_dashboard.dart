import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import '../../constant.dart';
import '../../widgets/shared/universal_pagination.dart';

class OicDashboard extends StatefulWidget {
  final String oicName;
  final String companyName;
  final String oicId;

  const OicDashboard({
    super.key,
    required this.oicName,
    required this.companyName,
    required this.oicId,
  });

  @override
  State<OicDashboard> createState() => _OicDashboardState();
}

class _OicDashboardState extends State<OicDashboard> {
  // --- STATE ---
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<dynamic> _allTrips = [];
  
  // Active Filters
  String _statusFilter = 'Pending';
  DateTime? _filterDate = DateTime.now();
  String _sortOption = 'Date (Newest)';
  
  final List<String> _sortOptions = ['Date (Newest)', 'Date (Oldest)', 'Trip ID'];

  // Pagination
  int _currentPage = 0;
  final int _itemsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _fetchLiveSchedules();
  }

  // --- DATA FETCH ---
  Future<void> _fetchLiveSchedules() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      if (_allTrips.isEmpty) _isLoading = true;
    });

    try {
      final res = await http.get(
        Uri.parse('$backendUrl/schedules/oic/${widget.oicId}'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _allTrips = data['data'] ?? [];
            _currentPage = 0;
          });
        }
      } else {
        _showSnackBar('Failed to load trips. Error ${res.statusCode}.', const Color(0xFFEF4444));
      }
    } catch (e) {
      debugPrint('OIC sync error: $e');
      _showSnackBar('Failed to sync schedules.', const Color(0xFFEF4444));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // --- FILTERING & SORTING ---
  List<dynamic> get _filteredAndSortedTrips {
    final placeholderStatus = _statusFilter == 'Total' ? 'Scheduled' : _statusFilter;
    final displayTrips = _isLoading
        ? List.generate(5, (index) => {
              'trip_id': index + 1,
              'route_name': 'Loading Route',
              'trip_status': placeholderStatus,
              'schedule_date': DateTime.now().toIso8601String(),
              'driver_name': 'Loading Driver',
              'plate_number': 'Loading Vehicle',
              'departure_time': '08:00',
              'estimated_arrival_time': '09:00',
              'passenger_count': 0,
              'route_distance': 0,
            })
        : _allTrips;
    final filtered = displayTrips.where((t) {
      final s = (t['trip_status'] ?? '').toString().toLowerCase().trim();
      final dateStr = t['schedule_date']?.toString() ?? '';

      // Map Status Filter
      bool matchesStatus = false;
      if (_statusFilter == 'Pending') {
        matchesStatus = s == 'pending staff assignment' || s.contains('pending');
      } else if (_statusFilter == 'Scheduled') matchesStatus = s == 'scheduled';
      else if (_statusFilter == 'Ongoing') matchesStatus = s == 'ongoing';
      else if (_statusFilter == 'Completed') matchesStatus = s == 'completed';
      else if (_statusFilter == 'Total') matchesStatus = true;

      // Date Filter
      final matchesDate = _filterDate == null || 
          dateStr.startsWith('${_filterDate!.year}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}');

      return matchesStatus && matchesDate;
    }).toList();

    // Sort
    switch (_sortOption) {
      case 'Date (Newest)':
        filtered.sort((a, b) {
          final da = a['schedule_date'] ?? '';
          final db = b['schedule_date'] ?? '';
          return db.compareTo(da);
        });
        break;
      case 'Date (Oldest)':
        filtered.sort((a, b) {
          final da = a['schedule_date'] ?? '';
          final db = b['schedule_date'] ?? '';
          return da.compareTo(db);
        });
        break;
      case 'Trip ID':
        filtered.sort((a, b) {
          final idA = (a['trip_id'] ?? 0).toString();
          final idB = (b['trip_id'] ?? 0).toString();
          return idA.compareTo(idB);
        });
        break;
    }
    return filtered;
  }

  // --- STATS CALCULATION ---
  int get _pendingCount => _allTrips.where((t) => (t['trip_status'] ?? '').toString().toLowerCase().contains('pending')).length;
  int get _scheduledCount => _allTrips.where((t) => (t['trip_status'] ?? '').toString().toLowerCase() == 'scheduled').length;
  int get _ongoingCount => _allTrips.where((t) => (t['trip_status'] ?? '').toString().toLowerCase() == 'ongoing').length;
  int get _completedCount => _allTrips.where((t) => (t['trip_status'] ?? '').toString().toLowerCase() == 'completed').length;

  Color _getStatusColor(String statusStr) {
    String lower = statusStr.toLowerCase();
    if (lower.contains('completed')) return const Color(0xFF10B981);
    if (lower.contains('ongoing') || lower.contains('pending')) return const Color(0xFFF59E0B);
    return const Color(0xFF3B82F6); // Default/Scheduled
  }

  // --- UI BUILD ---
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final double pad = isMobile ? 12.0 : 24.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Skeletonizer(
        enabled: _isLoading,
        child: RefreshIndicator(
        onRefresh: _fetchLiveSchedules,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER & ACTIONS ---
              isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTitleHeader(isDark),
                        const SizedBox(height: 16),
                        _buildSearchAndActionRow(isDark),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildTitleHeader(isDark),
                        const Spacer(), // Pushes actions to the right
                        _buildSearchAndActionRow(isDark),
                      ],
                    ),
              const SizedBox(height: 24),

              // --- INTERACTIVE PILLS ---
              _buildTopSummaryStats(isDark, isMobile),
              const SizedBox(height: 24),

              // --- MAIN CONTENT ---
              _buildPaginatedGrid(isMobile, isDark),
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.oicName} Dashboard',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.blue.withValues(alpha: 0.2) : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.2)),
              ),
              child: Text(
                widget.companyName,
                style: TextStyle(
                  color: isDark ? Colors.blue.shade300 : const Color(0xFF3B82F6),
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Live overview of trips and schedules.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndActionRow(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Calendar Modal Trigger
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: _filterDate != null ? (isDark ? Colors.blue.withValues(alpha: 0.2) : const Color(0xFFEFF6FF)) : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _filterDate != null ? const Color(0xFF3B82F6) : (isDark ? Colors.grey.shade700 : Colors.grey.shade300)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _filterDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.light(
                            primary: const Color(0xFF3B82F6),
                            onPrimary: Colors.white,
                            surface: Theme.of(context).cardColor,
                            onSurface: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setState(() {
                      _filterDate = picked;
                      _currentPage = 0;
                    });
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month, size: 16, color: _filterDate != null ? const Color(0xFF3B82F6) : (isDark ? Colors.grey.shade400 : const Color(0xFF64748B))),
                      const SizedBox(width: 8),
                      Text(
                        _filterDate != null 
                            ? '${_filterDate!.month.toString().padLeft(2, '0')}/${_filterDate!.day.toString().padLeft(2, '0')}/${_filterDate!.year}' 
                            : 'Select Date',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _filterDate != null ? const Color(0xFF3B82F6) : (isDark ? Colors.white : const Color(0xFF0F172A)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_filterDate != null) ...[
                Container(width: 1, height: 24, color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Color(0xFF3B82F6)),
                  onPressed: () {
                    setState(() {
                      _filterDate = null;
                      _currentPage = 0;
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
                  tooltip: 'Clear Date',
                ),
              ]
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Sort Dropdown
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _sortOption,
              icon: const Icon(Icons.sort, size: 16, color: Color(0xFF64748B)),
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A), fontWeight: FontWeight.bold),
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

        // Refresh
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: Colors.blue.shade600, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            onPressed: _isRefreshing ? null : _fetchLiveSchedules,
            icon: _isRefreshing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue))
                : const Icon(Icons.refresh, color: Colors.blue, size: 20),
            padding: EdgeInsets.zero,
            tooltip: 'Refresh Data',
          ),
        ),
      ],
    );
  }

  Widget _buildTopSummaryStats(bool isDark, bool isMobile) {
    final List<Map<String, dynamic>> stats = [
      {'label': 'Pending', 'value': _pendingCount.toString(), 'icon': Icons.hourglass_top, 'color': const Color(0xFFF59E0B), 'filter': 'Pending'},
      {'label': 'Scheduled', 'value': _scheduledCount.toString(), 'icon': Icons.event_available, 'color': const Color(0xFF3B82F6), 'filter': 'Scheduled'},
      {'label': 'Ongoing', 'value': _ongoingCount.toString(), 'icon': Icons.local_shipping, 'color': const Color(0xFFF59E0B), 'filter': 'Ongoing'},
      {'label': 'Completed', 'value': _completedCount.toString(), 'icon': Icons.check_circle_outline, 'color': const Color(0xFF10B981), 'filter': 'Completed'},
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
            color: isSelected ? stat['color'].withOpacity(0.1) : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: isSelected ? stat['color'] : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
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
                      color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
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

  // --- STANDARD GRID ---
  Widget _buildPaginatedGrid(bool isMobile, bool isDark) {
    final items = _filteredAndSortedTrips;
    final totalPages = max(1, (items.length / _itemsPerPage).ceil());
    final start = _currentPage * _itemsPerPage;
    final end = min(start + _itemsPerPage, items.length);
    final pageItems = start >= items.length ? [] : items.sublist(start, end);

    if (items.isEmpty) return _buildEmptyState('No $_statusFilter trips found for the selected date.', isDark);

    Widget grid = isMobile
        ? ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pageItems.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _buildUltraCompactCard(pageItems[i], isDark),
          )
        : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 3.5,
            ),
            itemCount: pageItems.length,
            itemBuilder: (_, i) => _buildUltraCompactCard(pageItems[i], isDark),
          );

    return Column(
      children: [
        grid,
        if (items.length > _itemsPerPage) _buildPagination(start, end, totalPages, items.length, isDark),
      ],
    );
  }

  // --- ULTRA-COMPACT CARD ---
  Widget _buildUltraCompactCard(dynamic trip, bool isDark) {
    final status = (trip['trip_status'] ?? 'Scheduled').toString().toLowerCase();
    final driver = trip['driver_name'] ?? trip['user_account']?['full_name'] ?? 'Unassigned';
    final vehicle = trip['plate_number'] ?? trip['vehicle']?['plate_number'] ?? 'No Shuttle';
    final dep = _formatTime(trip['departure_time']);
    final arr = _formatTime(trip['estimated_arrival_time']);
    final pax = trip['passenger_count'] ?? 0;
    final distance = trip['route_distance'] ?? 0;

    final statusColor = _getStatusColor(status);
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'TRIP-${trip['trip_id']} • ${trip['route_name'] ?? 'Unassigned'}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _tinyChip(Icons.person, driver, isDark),
                    _tinyChip(Icons.directions_car, vehicle, isDark),
                    _tinyChip(Icons.access_time, '$dep → $arr', isDark),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tinyChip(Icons.people, '$pax pax', isDark),
                  const SizedBox(width: 8),
                  _tinyChip(Icons.straighten, '$distance km', isDark),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tinyChip(IconData icon, String text, bool isDark) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: isDark ? Colors.grey.shade500 : const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );

  // --- HELPERS ---
  Widget _buildEmptyState(String msg, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              msg,
              style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade500, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );

  String _formatTime(dynamic t) {
    if (t == null || t.toString().trim().isEmpty) return 'TBD';
    final s = t.toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  Widget _buildPagination(int start, int end, int totalPages, int total, bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      alignment: Alignment.centerLeft,
      child: UniversalPagination(
        currentPage: _currentPage,
        totalPages: totalPages,
        totalItems: total,
        itemsPerPage: _itemsPerPage,
        itemName: 'entries',
        onNextPage: _currentPage < totalPages - 1 
            ? () => setState(() => _currentPage++) 
            : null,
        onPrevPage: _currentPage > 0 
            ? () => setState(() => _currentPage--) 
            : null,
      ),
    );
  }
}