import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xlsx;
import '../../constant.dart';
import '../../layouts/enterprise/enterprise_data_grid.dart';
import '../../layouts/enterprise/enterprise_states.dart';
import '../../layouts/enterprise/enterprise_theme.dart';
import 'trip_summary_editor_page.dart';

String _summaryDateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class StaffTrips extends StatefulWidget {
  final String staffId;
  final bool canManageSummaries;
  final String title;
  final String subtitle;

  const StaffTrips({
    super.key,
    required this.staffId,
    this.canManageSummaries = true,
    this.title = 'Trip Summary',
    this.subtitle = 'Billing-style trip summary based on scheduled dates.',
  });

  @override
  State<StaffTrips> createState() => _StaffTripsState();
}

class _StaffTripsState extends State<StaffTrips> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<Map<String, dynamic>> _trips = [];
  DateTime _focusedMonth = DateTime.now();

  DateTime? _selectedDate;
  String _searchQuery = '';
  String _selectedDriver = 'All Drivers';
  String _selectedVehicle = 'All Vehicles';

  String _currentSort = 'Date (Newest)';
  int? _filterMonth = DateTime.now().month;
  int? _filterYear = DateTime.now().year;

  List<int> _availableYears = [DateTime.now().year];
  final List<String> _monthNames = const [
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

  int _activeTab = 0;
  final ScrollController _summaryListScrollController = ScrollController();

  static const List<String> _excludedStatuses = [
    'ongoing',
    'expired',
    'rejected',
  ];

  @override
  void initState() {
    super.initState();
    _fetchTripSummary();
  }

  @override
  void dispose() {
    _summaryListScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchTripSummary() async {
    if (_isRefreshing) return;
    setState(() {
      _isLoading = true;
      _isRefreshing = true;
    });

    try {
      final response = await http
          .get(
            Uri.parse('$backendUrl/schedules/staff-summary/${widget.staffId}'),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final rows = (decoded['data'] as List? ?? [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .where(_isSummaryTrip)
            .toList();

        Set<int> years = {DateTime.now().year};
        for (var t in rows) {
          final d = _parseDate(t['schedule_date'] ?? t['date']);
          if (d != null) years.add(d.year);
        }

        if (mounted) {
          setState(() {
            _trips = rows;
            _availableYears = years.toList()..sort((a, b) => b.compareTo(a));
          });
        }
      }
    } catch (error) {
      debugPrint('Trip summary fetch failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  void _resetPagination() {}

  bool _isSummaryTrip(Map<String, dynamic> trip) {
    final status = (trip['trip_status'] ?? '').toString().toLowerCase();
    return !_excludedStatuses.any((blocked) => status.contains(blocked));
  }

  List<Map<String, dynamic>> get _visibleTrips {
    final query = _searchQuery.trim().toLowerCase();

    final rows = _trips.where((trip) {
      DateTime? tripDate = _parseDate(trip['schedule_date'] ?? trip['date']);
      if (tripDate == null) return false;

      if (_selectedDate != null) {
        if (_dateKey(tripDate) != _dateKey(_selectedDate!)) return false;
      } else {
        if (_filterYear != null && tripDate.year != _filterYear) return false;
        if (_filterMonth != null && tripDate.month != _filterMonth)
          return false;
      }

      if (_selectedDriver != 'All Drivers' &&
          (trip['driver_name'] ?? 'Unassigned').toString() != _selectedDriver) {
        return false;
      }
      if (_selectedVehicle != 'All Vehicles' &&
          (trip['plate_number'] ?? 'Unassigned').toString() !=
              _selectedVehicle) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        trip['route_name'],
        trip['driver_name'],
        trip['plate_number'],
        trip['classification'],
        trip['ticket_no'],
        trip['client_company'],
        trip['summary_id'],
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();

    rows.sort((a, b) {
      final dateA = (a['schedule_date'] ?? '').toString();
      final dateB = (b['schedule_date'] ?? '').toString();
      int cmp = _currentSort == 'Date (Newest)'
          ? dateB.compareTo(dateA)
          : dateA.compareTo(dateB);
      if (cmp != 0) return cmp;
      return _timeText(
        a['departure_time'],
      ).compareTo(_timeText(b['departure_time']));
    });
    return rows;
  }

  List<String> get _driverOptions {
    final values =
        _trips
            .map((trip) => (trip['driver_name'] ?? 'Unassigned').toString())
            .where((name) => name.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All Drivers', ...values];
  }

  List<String> get _vehicleOptions {
    final values =
        _trips
            .map((trip) => (trip['plate_number'] ?? 'Unassigned').toString())
            .where((plate) => plate.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All Vehicles', ...values];
  }

  int get _totalPassengers => _visibleTrips.fold<int>(
    0,
    (sum, trip) => sum + (int.tryParse('${trip['passenger_count'] ?? 0}') ?? 0),
  );

  double get _averageUtilization {
    final values = _visibleTrips
        .map(_utilizationValue)
        .whereType<double>()
        .toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  String get _topDestination {
    final counts = <String, int>{};
    for (final trip in _visibleTrips) {
      final destination = (trip['route_name'] ?? '').toString().trim();
      if (destination.isNotEmpty) {
        counts[destination] = (counts[destination] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return '-';
    return counts.entries
        .reduce((first, second) => first.value >= second.value ? first : second)
        .key;
  }

  List<Map<String, dynamic>> get _summaryGroups {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final trip in _visibleTrips) {
      final summaryId = (trip['summary_id'] ?? '').toString().trim();
      final fallback =
          'SUMMARY-${(trip['schedule_date'] ?? trip['date'] ?? 'NO-DATE').toString()}';
      grouped
          .putIfAbsent(summaryId.isEmpty ? fallback : summaryId, () => [])
          .add(trip);
    }

    final groups = grouped.entries.map((entry) {
      final rows = entry.value;
      rows.sort(
        (a, b) => _timeText(
          a['departure_time'],
        ).compareTo(_timeText(b['departure_time'])),
      );
      final totalPassengers = rows.fold<int>(
        0,
        (sum, trip) =>
            sum + (int.tryParse('${trip['passenger_count'] ?? 0}') ?? 0),
      );
      final vehicles = rows
          .map((trip) => (trip['plate_number'] ?? '').toString())
          .where((plate) => plate.trim().isNotEmpty)
          .toSet()
          .join(', ');
      return {
        'summary_id': entry.key,
        'date': (rows.first['schedule_date'] ?? rows.first['date'] ?? '')
            .toString(),
        'company': (rows.first['client_company'] ?? 'Unassigned Company')
            .toString(),
        'working_day': _workingDay(rows.first),
        'rows': rows,
        'row_count': rows.length,
        'passenger_count': totalPassengers,
        'vehicles': vehicles,
      };
    }).toList();

    groups.sort((a, b) {
      return _currentSort == 'Date (Newest)'
          ? '${b['date']}'.compareTo('${a['date']}')
          : '${a['date']}'.compareTo('${b['date']}');
    });
    return groups;
  }

  String _dateKey(DateTime date) => _summaryDateKey(date);

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString().split(' ').first);
    } catch (_) {
      return null;
    }
  }

  String _workingDay(Map<String, dynamic> trip) {
    final explicit = (trip['working_day'] ?? '').toString();
    if (explicit.isNotEmpty) return explicit.toUpperCase();
    final date = _parseDate(trip['schedule_date'] ?? trip['date']);
    if (date == null) return '';
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    return days[date.weekday - 1];
  }

  String _timeText(dynamic value) {
    final text = (value ?? '').toString();
    if (text.isEmpty) return '--:--';
    if (text.toUpperCase().contains('AM') || text.toUpperCase().contains('PM'))
      return text;
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  double? _utilizationValue(Map<String, dynamic> trip) {
    final direct = double.tryParse('${trip['utilization_rate'] ?? ''}');
    if (direct != null) return direct;
    final passengers = double.tryParse('${trip['passenger_count'] ?? ''}');
    final capacity = double.tryParse('${trip['seating_capacity'] ?? ''}');
    if (passengers == null || capacity == null || capacity == 0) return null;
    return passengers / capacity;
  }

  String _utilizationText(Map<String, dynamic> trip) {
    final value = _utilizationValue(trip);
    if (value == null) return '-';
    return '${(value * 100).round()}%';
  }

  List<Map<String, dynamic>> _tripsForDate(DateTime date) {
    final key = _dateKey(date);
    return _trips
        .where(
          (trip) => (trip['schedule_date'] ?? trip['date'] ?? '')
              .toString()
              .startsWith(key),
        )
        .toList();
  }

  Future<void> _importSummaryFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xls', 'xlsx', 'csv'],
      );
      if (files.isEmpty) return;

      setState(() {
        _isLoading = true;
        _isRefreshing = true;
      });

      final file = files.first;
      final fileBytes = await file.readAsBytes();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$backendUrl/schedules/upload-summary-xls'),
      );
      request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: file.name),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          final List<dynamic> rows = decoded['rows'] ?? [];
          if (rows.isEmpty)
            throw Exception("No valid trip rows found in file.");

          final mappedRows = rows
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          if (!mounted) return;
          final createdDate = await Navigator.of(context).push<DateTime>(
            MaterialPageRoute(
              builder: (_) => TripSummaryEditorPage(
                staffId: widget.staffId,
                initialRows: mappedRows,
              ),
            ),
          );

          if (createdDate != null && mounted) {
            setState(() {
              _selectedDate = createdDate;
              _filterMonth = null;
              _filterYear = null;
            });
            await _fetchTripSummary();
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Imported trips successfully added.'),
                ),
              );
          }
        } else {
          throw Exception(decoded['error'] ?? "Upload failed.");
        }
      } else {
        throw Exception("Server error ${response.statusCode}");
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _showAddSummaryDialog() async {
    final createdDate = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => TripSummaryEditorPage(staffId: widget.staffId),
      ),
    );

    if (createdDate == null || !mounted) return;
    setState(() {
      _selectedDate = createdDate;
      _filterMonth = null;
      _filterYear = null;
    });
    await _fetchTripSummary();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip summary batch added.')),
      );
  }

  // --- RESTORED ORIGINAL MODAL FUNCTIONALITY ---
  void _showTripDetails(Map<String, dynamic> trip) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Trip Summary Details'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow(
                  'Date',
                  (trip['schedule_date'] ?? trip['date'] ?? '').toString(),
                  isDark,
                ),
                _detailRow(
                  'Summary ID',
                  (trip['summary_id'] ?? '').toString(),
                  isDark,
                ),
                _detailRow(
                  'Company',
                  (trip['client_company'] ?? 'Unassigned Company').toString(),
                  isDark,
                ),
                _detailRow('Working Day', _workingDay(trip), isDark),
                _detailRow(
                  'Bus Type',
                  (trip['vehicle_type'] ?? trip['bus_type'] ?? '').toString(),
                  isDark,
                ),
                _detailRow(
                  'Classification',
                  (trip['classification'] ?? '').toString(),
                  isDark,
                ),
                _detailRow(
                  'Vehicle',
                  (trip['plate_number'] ?? 'Unassigned').toString(),
                  isDark,
                ),
                _detailRow(
                  'Seating Capacity',
                  (trip['seating_capacity'] ?? '').toString(),
                  isDark,
                ),
                _detailRow(
                  'Ticket No.',
                  (trip['ticket_no'] ?? '').toString(),
                  isDark,
                ),
                _detailRow(
                  'Driver',
                  (trip['driver_name'] ?? 'Unassigned').toString(),
                  isDark,
                ),
                _detailRow(
                  'Route',
                  (trip['route_name'] ?? '').toString(),
                  isDark,
                ),
                _detailRow(
                  'No. of Passengers',
                  (trip['passenger_count'] ?? '').toString(),
                  isDark,
                ),
                _detailRow(
                  'Departure',
                  _timeText(trip['departure_time']),
                  isDark,
                ),
                _detailRow(
                  'Arrival',
                  _timeText(trip['estimated_arrival_time']),
                  isDark,
                ),
                _detailRow('Utilization', _utilizationText(trip), isDark),
                _detailRow(
                  'Remarks',
                  (trip['remarks'] ?? '').toString(),
                  isDark,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _updateSummaryRow(
    Map<String, dynamic> trip,
    Map<String, dynamic> payload,
  ) async {
    final tripId = int.tryParse('${trip['trip_id'] ?? ''}');
    if (tripId == null) return false;

    final response = await http
        .put(
          Uri.parse('$backendUrl/schedules/staff-summary/$tripId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) return true;
    String message = 'Unable to update summary row.';
    try {
      final decoded = jsonDecode(response.body);
      message = decoded['message']?.toString() ?? message;
    } catch (_) {}
    throw Exception(message);
  }

  Future<void> _showSummaryGroupDetails(Map<String, dynamic> summary) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _SummarySheetPage(
          staffId: widget.staffId,
          canManageSummaries: widget.canManageSummaries,
          summaryId: (summary['summary_id'] ?? '').toString(),
          rows: (summary['rows'] as List? ?? [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
          onSaveRow: _updateSummaryRow,
        ),
      ),
    );

    if (changed == true) await _fetchTripSummary();
  }

  // --- NEW: CALENDAR MODAL LOGIC ---
  void _openCalendarModal(bool isDark) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final firstDay = DateTime(
                  _focusedMonth.year,
                  _focusedMonth.month,
                  1,
                );
                final daysInMonth = DateTime(
                  _focusedMonth.year,
                  _focusedMonth.month + 1,
                  0,
                ).day;
                final firstWeekday = firstDay.weekday % 7;
                final borderColor = isDark
                    ? Colors.grey.shade800
                    : const Color(0xFFE2E8F0);
                const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Date',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => setModalState(() {
                            _focusedMonth = DateTime(
                              _focusedMonth.year,
                              _focusedMonth.month - 1,
                            );
                          }),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          '${_monthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setModalState(() {
                            _focusedMonth = DateTime(
                              _focusedMonth.year,
                              _focusedMonth.month + 1,
                            );
                          }),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 7,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: weekdays
                          .map(
                            (day) => Center(
                              child: Text(
                                day,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            childAspectRatio: 1.0,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                          ),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: daysInMonth + firstWeekday,
                      itemBuilder: (context, index) {
                        if (index < firstWeekday)
                          return const SizedBox.shrink();
                        final day = index - firstWeekday + 1;
                        final date = DateTime(
                          _focusedMonth.year,
                          _focusedMonth.month,
                          day,
                        );
                        final trips = _tripsForDate(date);
                        final hasTrips = trips.isNotEmpty;
                        final isSelected =
                            _selectedDate != null &&
                            _dateKey(_selectedDate!) == _dateKey(date);
                        final isToday =
                            _dateKey(DateTime.now()) == _dateKey(date);

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedDate = isSelected ? null : date;
                              _filterMonth = date.month;
                              _filterYear = date.year;
                              _resetPagination();
                            });
                            Navigator.pop(context);
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : hasTrips
                                  ? (isDark
                                        ? const Color(0xFF0F2D52)
                                        : const Color(0xFFEFF6FF))
                                  : Colors.transparent,
                              border: Border.all(
                                color: isToday
                                    ? const Color(0xFFF59E0B)
                                    : isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : borderColor,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$day',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : hasTrips
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                    fontWeight: isSelected || hasTrips
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                                if (hasTrips)
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: Text(
                                        '${trips.length} trips',
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : const Color(0xFF64748B),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_selectedDate != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _selectedDate = null;
                              _resetPagination();
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Clear Date Selection'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------
  // UI BUILD METHODS
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNarrow = MediaQuery.of(context).size.width < 1200;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _fetchTripSummary,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // 1. TOP ROW: Title on Left, Reload/Actions on Right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.canManageSummaries) ...[
                      OutlinedButton.icon(
                        onPressed: _isRefreshing ? null : _importSummaryFile,
                        icon: const Icon(Icons.upload_file, size: 17),
                        label: const Text('Import Excel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _isRefreshing ? null : _showAddSummaryDialog,
                        icon: const Icon(Icons.add, size: 17),
                        label: const Text('Add Summary'),
                        style: FilledButton.styleFrom(
                          backgroundColor: EnterpriseColors.generativeAction,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _fetchTripSummary,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 2. CARDS BEFORE FILTERS
            if (_isLoading)
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: List.generate(
                  5,
                  (_) => const SizedBox(
                    width: 220,
                    child: EnterpriseSummaryCardSkeleton(),
                  ),
                ),
              )
            else
              _buildSummaryCards(isDark),

            const SizedBox(height: 32),

            // 3. FILTERS
            Align(
              alignment: Alignment.centerLeft,
              child: _buildFilters(isDark, isNarrow),
            ),

            const SizedBox(height: 24),

            // 4. MAIN WORKSPACE TABS & TABLE
            _buildTripTabs(isDark),
            const SizedBox(height: 12),
            _activeTab == 0
                ? _buildSummaryTable(isDark)
                : _buildEditableSummarySheet(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(bool isDark) {
    String selectedLabel = 'All Time';
    if (_selectedDate != null) {
      selectedLabel = _dateKey(_selectedDate!);
    } else if (_filterMonth != null && _filterYear != null) {
      selectedLabel = '${_monthNames[_filterMonth! - 1]} $_filterYear';
    }

    // Colored exactly matching the dashboard reference image style
    final cards = [
      (
        'Total Trips',
        '${_visibleTrips.length}',
        Icons.route_outlined,
        const Color(0xFF3B82F6),
      ),
      (
        'Total Passengers',
        '$_totalPassengers',
        Icons.groups_outlined,
        const Color(0xFF8B5CF6),
      ),
      (
        'Avg Utilization',
        '${(_averageUtilization * 100).round()}%',
        Icons.percent,
        const Color(0xFF06B6D4),
      ),
      (
        'Top Destination',
        _topDestination,
        Icons.place_outlined,
        const Color(0xFF10B981),
      ),
      (
        'Date Basis',
        selectedLabel,
        Icons.calendar_today,
        const Color(0xFFEF4444),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;
        final cardWidth = isNarrow
            ? constraints.maxWidth
            : (constraints.maxWidth - 64) / 5;
        final cardWidgets = cards.map((card) {
          final Color baseColor = card.$4;
          return Container(
            width: cardWidth,
            constraints: const BoxConstraints(minHeight: 112),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: 0.08),
              border: Border.all(color: baseColor.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(card.$3, color: baseColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        card.$1,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: baseColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  card.$2,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          );
        }).toList();
        if (isNarrow) {
          return Column(
            children: cardWidgets
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: card,
                  ),
                )
                .toList(),
          );
        }
        return Row(
          children: [
            for (var index = 0; index < cardWidgets.length; index++) ...[
              if (index > 0) const SizedBox(width: 16),
              Expanded(child: cardWidgets[index]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildFilters(bool isDark, bool isNarrow) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.start,
      children: [
        SizedBox(
          width: 220,
          height: 42,
          child: TextField(
            onChanged: (value) => setState(() {
              _searchQuery = value;
              _resetPagination();
            }),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13,
            ),
            decoration: _inputDecoration(
              isDark,
              'Search ID, route...',
              Icons.search,
            ),
          ),
        ),
        _dropdown(
          isDark: isDark,
          width: 140,
          value: _filterMonth == null
              ? 'All Months'
              : _monthNames[_filterMonth! - 1],
          values: ['All Months', ..._monthNames],
          onChanged: (value) {
            setState(() {
              _selectedDate = null;
              if (value == 'All Months') {
                _filterMonth = null;
              } else {
                _filterMonth = _monthNames.indexOf(value!) + 1;
              }
              _resetPagination();
            });
          },
        ),
        _dropdown(
          isDark: isDark,
          width: 120,
          value: _filterYear == null ? 'All Years' : _filterYear.toString(),
          values: ['All Years', ..._availableYears.map((y) => y.toString())],
          onChanged: (value) {
            setState(() {
              _selectedDate = null;
              if (value == 'All Years') {
                _filterYear = null;
              } else {
                _filterYear = int.parse(value!);
              }
              _resetPagination();
            });
          },
        ),
        _dropdown(
          isDark: isDark,
          width: 150,
          value: _currentSort,
          values: ['Date (Newest)', 'Date (Oldest)'],
          onChanged: (value) => setState(() {
            _currentSort = value ?? 'Date (Newest)';
            _resetPagination();
          }),
        ),
        _dropdown(
          isDark: isDark,
          width: 160,
          value: _driverOptions.contains(_selectedDriver)
              ? _selectedDriver
              : 'All Drivers',
          values: _driverOptions,
          onChanged: (value) => setState(() {
            _selectedDriver = value ?? 'All Drivers';
            _resetPagination();
          }),
        ),
        _dropdown(
          isDark: isDark,
          width: 160,
          value: _vehicleOptions.contains(_selectedVehicle)
              ? _selectedVehicle
              : 'All Vehicles',
          values: _vehicleOptions,
          onChanged: (value) => setState(() {
            _selectedVehicle = value ?? 'All Vehicles';
            _resetPagination();
          }),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(bool isDark, String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF64748B)),
      filled: true,
      fillColor: Theme.of(context).cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
    );
  }

  Widget _dropdown({
    required bool isDark,
    required double width,
    required String value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = values.contains(value) ? value : values.first;
    return Container(
      width: width,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          dropdownColor: Theme.of(context).cardColor,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          items: values
              .toSet()
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildTripTabs(bool isDark) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _tabButton('Trip Ledger', 0, isDark),
          _tabButton('Summary Batches', 1, isDark),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index, bool isDark) {
    final selected = _activeTab == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => setState(() {
          _activeTab = index;
          _resetPagination();
        }),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.grey.shade400 : const Color(0xFF475569)),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryTable(bool isDark) {
    final rows = _visibleTrips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top-Left Anchored Table Controls
        Row(
          children: [
            Chip(
              label: Text(
                '${rows.length} records',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _openCalendarModal(isDark),
              icon: const Icon(Icons.calendar_month, size: 16),
              label: const Text('Open Calendar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        EnterpriseDataGrid<Map<String, dynamic>>(
          rows: rows,
          loading: _isLoading,
          height: 560,
          rowKey: (trip) => Object.hash(trip['trip_id'], trip['summary_id']),
          columns: [
            EnterpriseGridColumn(
              label: 'Date',
              width: 110,
              value: (trip) =>
                  (trip['schedule_date'] ?? trip['date'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Summary ID',
              width: 170,
              value: (trip) => (trip['summary_id'] ?? '').toString(),
            ),
            EnterpriseGridColumn(label: 'Day', width: 105, value: _workingDay),
            EnterpriseGridColumn(
              label: 'Type',
              width: 105,
              value: (trip) =>
                  (trip['vehicle_type'] ?? trip['bus_type'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Class',
              width: 110,
              value: (trip) => (trip['classification'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Plate',
              width: 110,
              value: (trip) => (trip['plate_number'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Capacity',
              width: 95,
              value: (trip) => (trip['seating_capacity'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Ticket',
              width: 105,
              value: (trip) => (trip['ticket_no'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Driver',
              width: 170,
              value: (trip) => (trip['driver_name'] ?? 'Unassigned').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Route',
              width: 190,
              value: (trip) => (trip['route_name'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Pax',
              width: 75,
              value: (trip) => (trip['passenger_count'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Depart',
              width: 95,
              value: (trip) => _timeText(trip['departure_time']),
            ),
            EnterpriseGridColumn(
              label: 'Arrival',
              width: 95,
              value: (trip) => _timeText(trip['estimated_arrival_time']),
            ),
            EnterpriseGridColumn(
              label: 'Util',
              width: 80,
              value: _utilizationText,
            ),
            EnterpriseGridColumn(
              label: 'Remarks',
              width: 180,
              value: (trip) => (trip['remarks'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Action',
              width: 105,
              value: (_) => 'Open',
              cellBuilder: (context, trip) => OutlinedButton(
                onPressed: () => _showTripDetails(trip),
                child: const Text('View'),
              ),
            ),
          ],
          filterFields: const [], // Cleared to prevent middle rendering
          emptyTitle: 'No trips match these filters',
          emptyMessage:
              'Clear the current date and status filters to restore the trip ledger.',
        ),
      ],
    );
  }

  Widget _buildEditableSummarySheet(bool isDark) {
    final groups = _summaryGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top-Left Anchored Table Controls
        Row(
          children: [
            Chip(
              label: Text(
                '${groups.length} batches',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _openCalendarModal(isDark),
              icon: const Icon(Icons.calendar_month, size: 16),
              label: const Text('Open Calendar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        EnterpriseDataGrid<Map<String, dynamic>>(
          rows: groups,
          loading: _isLoading,
          height: 560,
          rowKey: (summary) =>
              Object.hash(summary['summary_id'], summary['date']),
          columns: [
            EnterpriseGridColumn(
              label: 'Summary ID',
              width: 180,
              value: (summary) => (summary['summary_id'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Date',
              width: 120,
              value: (summary) => (summary['date'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Company',
              width: 190,
              value: (summary) => (summary['company'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Day',
              width: 120,
              value: (summary) => (summary['working_day'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Trips',
              width: 85,
              value: (summary) => '${summary['row_count'] ?? 0}',
            ),
            EnterpriseGridColumn(
              label: 'Passengers',
              width: 105,
              value: (summary) => '${summary['passenger_count'] ?? 0}',
            ),
            EnterpriseGridColumn(
              label: 'Vehicles',
              width: 260,
              value: (summary) => (summary['vehicles'] ?? '').toString(),
            ),
            EnterpriseGridColumn(
              label: 'Action',
              width: 110,
              value: (_) => 'Open',
              cellBuilder: (context, summary) => OutlinedButton(
                onPressed: () => _showSummaryGroupDetails(summary),
                child: const Text('View'),
              ),
            ),
          ],
          filterFields: const [], // Cleared to prevent middle rendering
          emptyTitle: 'No summaries match these filters',
          emptyMessage:
              'Clear the selected reporting period to restore summary batches.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------
// SUMMARY SHEET EXPORT PAGE (Fully Restored)
// ---------------------------------------------------------
class _SummarySheetPage extends StatelessWidget {
  final String staffId;
  final bool canManageSummaries;
  final String summaryId;
  final List<Map<String, dynamic>> rows;
  final Future<bool> Function(
    Map<String, dynamic> trip,
    Map<String, dynamic> payload,
  )
  onSaveRow;

  const _SummarySheetPage({
    required this.staffId,
    required this.canManageSummaries,
    required this.summaryId,
    required this.rows,
    required this.onSaveRow,
  });

  String _generateCSV() {
    const headers = [
      'No.',
      'Date',
      'Working Day',
      '(Bus) Type',
      'Classification',
      'Bus No. (Jeep plate no.)',
      'Seating Capacity',
      'Ticket no.',
      'Driver',
      'Route',
      'No. of Passengers',
      'Dept. Time',
      'Arrival Time',
      'Rate per Trip',
      'Cost/head/day',
      'Utilization Rate',
      'REMARKS',
    ];
    String csv =
        'Company,${_csvEscape((rows.first['client_company'] ?? 'Unassigned Company').toString())}\n';
    csv +=
        'Address,${_csvEscape((rows.first['client_company_address'] ?? '').toString())}\n\n';
    csv += '${headers.map(_csvEscape).join(',')}\n';

    for (int i = 0; i < rows.length; i++) {
      final trip = rows[i];
      final row = [
        '${i + 1}',
        (trip['schedule_date'] ?? trip['date'] ?? '').toString(),
        (trip['working_day'] ?? '').toString(),
        (trip['vehicle_type'] ?? trip['bus_type'] ?? '').toString(),
        (trip['classification'] ?? '').toString(),
        (trip['plate_number'] ?? 'Unassigned').toString(),
        (trip['seating_capacity'] ?? '').toString(),
        (trip['ticket_no'] ?? '').toString(),
        (trip['driver_name'] ?? 'Unassigned').toString(),
        (trip['route_name'] ?? '').toString(),
        (trip['passenger_count'] ?? '').toString(),
        (trip['departure_time'] ?? '').toString(),
        (trip['estimated_arrival_time'] ?? '').toString(),
        '',
        '',
        _summaryUtilizationText(trip),
        (trip['remarks'] ?? '').toString(),
      ];
      csv += '${row.map(_csvEscape).join(',')}\n';
    }
    return csv;
  }

  String _csvEscape(String value) => '"${value.replaceAll('"', '""')}"';

  Uint8List _generateXlsx() {
    final excel = xlsx.Excel.createExcel();
    final sheet = excel['Summary'];
    sheet.appendRow([
      xlsx.TextCellValue('Company'),
      xlsx.TextCellValue(
        (rows.first['client_company'] ?? 'Unassigned Company').toString(),
      ),
    ]);
    sheet.appendRow([
      xlsx.TextCellValue('Address'),
      xlsx.TextCellValue(
        (rows.first['client_company_address'] ?? '').toString(),
      ),
    ]);
    sheet.appendRow([xlsx.TextCellValue('')]);
    const headers = [
      'No.',
      'Date',
      'Working Day',
      '(Bus) Type',
      'Classification',
      'Bus No. (Jeep plate no.)',
      'Seating Capacity',
      'Ticket no.',
      'Driver',
      'Route',
      'No. of Passengers',
      'Dept. Time',
      'Arrival Time',
      'Rate per Trip',
      'Cost/head/day',
      'Utilization Rate',
      'REMARKS',
    ];
    sheet.appendRow(headers.map((value) => xlsx.TextCellValue(value)).toList());

    for (var i = 0; i < rows.length; i++) {
      final trip = rows[i];
      final values = [
        '${i + 1}',
        (trip['schedule_date'] ?? trip['date'] ?? '').toString(),
        (trip['working_day'] ?? '').toString(),
        (trip['vehicle_type'] ?? trip['bus_type'] ?? '').toString(),
        (trip['classification'] ?? '').toString(),
        (trip['plate_number'] ?? 'Unassigned').toString(),
        (trip['seating_capacity'] ?? '').toString(),
        (trip['ticket_no'] ?? '').toString(),
        (trip['driver_name'] ?? 'Unassigned').toString(),
        (trip['route_name'] ?? '').toString(),
        (trip['passenger_count'] ?? '').toString(),
        (trip['departure_time'] ?? '').toString(),
        (trip['estimated_arrival_time'] ?? '').toString(),
        '',
        '',
        _summaryUtilizationText(trip),
        (trip['remarks'] ?? '').toString(),
      ];
      sheet.appendRow(
        values.map((value) => xlsx.TextCellValue(value)).toList(),
      );
    }
    excel.setDefaultSheet('Summary');
    final headerStyle = xlsx.CellStyle(
      backgroundColorHex: xlsx.ExcelColor.fromHexString('FF1E3A8A'),
      fontColorHex: xlsx.ExcelColor.white,
      bold: true,
      fontSize: 10,
      horizontalAlign: xlsx.HorizontalAlign.Center,
      verticalAlign: xlsx.VerticalAlign.Center,
      textWrapping: xlsx.TextWrapping.WrapText,
    );
    for (var column = 0; column < headers.length; column++) {
      sheet
              .cell(
                xlsx.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: 3,
                ),
              )
              .cellStyle =
          headerStyle;
      sheet.setColumnWidth(column, column == 0 ? 8 : 18);
    }
    sheet.setColumnWidth(5, 24);
    sheet.setColumnWidth(16, 30);
    return Uint8List.fromList(excel.encode()!);
  }

  Future<void> _exportSummary(BuildContext context) async {
    try {
      final String csvData = _generateCSV();
      final Uint8List fileBytes = Uint8List.fromList(utf8.encode(csvData));
      final safeSummaryId = summaryId.isEmpty ? 'Trip_Summary' : summaryId;
      final Uri? outputFile = await FilePicker.saveFile(
        dialogTitle: 'Export Summary',
        fileName: '${safeSummaryId}_Export.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: fileBytes,
      );
      if (outputFile == null) return;
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export successfully triggered!')),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _exportXlsx(BuildContext context) async {
    try {
      final safeSummaryId = summaryId.isEmpty ? 'Trip_Summary' : summaryId;
      final outputFile = await FilePicker.saveFile(
        dialogTitle: 'Export Summary as Excel',
        fileName: '${safeSummaryId}_Export.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: _generateXlsx(),
      );
      if (outputFile != null && context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel export completed.')),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = ScrollController();

    return Scaffold(
      appBar: AppBar(
        title: Text(summaryId.isEmpty ? 'Trip Summary' : summaryId),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: () => _exportSummary(context),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export CSV'),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark
                    ? Colors.blue.shade300
                    : const Color(0xFF2563EB),
                side: BorderSide(
                  color: isDark ? Colors.blue.shade800 : Colors.blue.shade200,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: () => _exportXlsx(context),
              icon: const Icon(Icons.table_view, size: 18),
              label: const Text('Export XLSX'),
            ),
          ),
          if (canManageSummaries)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => TripSummaryEditorPage(
                        staffId: staffId,
                        summaryId: summaryId,
                        initialRows: rows,
                        onSaveRow: onSaveRow,
                      ),
                    ),
                  );
                  if (changed == true && context.mounted)
                    Navigator.pop(context, true);
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Edit'),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Summary Information',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Text(
                      '${rows.length} trips',
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade400
                            : const Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: controller,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF8FAFC),
                        ),
                        columns: const [
                          DataColumn(label: Text('No.')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Day')),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Class')),
                          DataColumn(label: Text('Plate')),
                          DataColumn(label: Text('Capacity')),
                          DataColumn(label: Text('Ticket')),
                          DataColumn(label: Text('Driver')),
                          DataColumn(label: Text('Route')),
                          DataColumn(label: Text('Pax')),
                          DataColumn(label: Text('Depart')),
                          DataColumn(label: Text('Arrival')),
                          DataColumn(label: Text('Util')),
                          DataColumn(label: Text('Remarks')),
                        ],
                        rows: List.generate(rows.length, (index) {
                          final trip = rows[index];
                          return DataRow(
                            cells: [
                              DataCell(Text('${index + 1}')),
                              DataCell(
                                _plainCell(
                                  (trip['schedule_date'] ?? trip['date'] ?? '')
                                      .toString(),
                                  120,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['working_day'] ?? '').toString(),
                                  120,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['vehicle_type'] ??
                                          trip['bus_type'] ??
                                          '')
                                      .toString(),
                                  180,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['classification'] ?? '').toString(),
                                  100,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['plate_number'] ?? 'Unassigned')
                                      .toString(),
                                  130,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['seating_capacity'] ?? '').toString(),
                                  70,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['ticket_no'] ?? '').toString(),
                                  110,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['driver_name'] ?? 'Unassigned')
                                      .toString(),
                                  160,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['route_name'] ?? '').toString(),
                                  190,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['passenger_count'] ?? '').toString(),
                                  70,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['departure_time'] ?? '').toString(),
                                  90,
                                ),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['estimated_arrival_time'] ?? '')
                                      .toString(),
                                  90,
                                ),
                              ),
                              DataCell(
                                _plainCell(_summaryUtilizationText(trip), 70),
                              ),
                              DataCell(
                                _plainCell(
                                  (trip['remarks'] ?? '').toString(),
                                  180,
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plainCell(String value, double width) {
    return SizedBox(
      width: width,
      child: Text(
        value.trim().isEmpty ? '-' : value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _summaryUtilizationText(Map<String, dynamic> trip) {
    final direct = double.tryParse('${trip['utilization_rate'] ?? ''}');
    if (direct != null) return '${(direct * 100).round()}%';
    final pax = double.tryParse('${trip['passenger_count'] ?? ''}') ?? 0;
    final cap = double.tryParse('${trip['seating_capacity'] ?? ''}') ?? 0;
    if (cap <= 0) return '-';
    return '${((pax / cap) * 100).round()}%';
  }
}
