import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xlsx;
import '../../constant.dart';
import '../shared/enterprise_data_grid.dart';
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
  bool _isCalendarExpanded = true;
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

  int _currentTripPage = 0;
  int _currentSummaryPage = 0;
  final int _itemsPerPage = 10;

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

  void _resetPagination() {
    setState(() {
      _currentTripPage = 0;
      _currentSummaryPage = 0;
    });
  }

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

      int cmp = 0;
      if (_currentSort == 'Date (Newest)') {
        cmp = dateB.compareTo(dateA);
      } else {
        cmp = dateA.compareTo(dateB);
      }

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
      int cmp = 0;
      if (_currentSort == 'Date (Newest)') {
        cmp = '${b['date']}'.compareTo('${a['date']}');
      } else {
        cmp = '${a['date']}'.compareTo('${b['date']}');
      }
      return cmp;
    });
    return groups;
  }

  String _dateKey(DateTime date) {
    return _summaryDateKey(date);
  }

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
    return _trips.where((trip) {
      return (trip['schedule_date'] ?? trip['date'] ?? '')
          .toString()
          .startsWith(key);
    }).toList();
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
          if (rows.isEmpty) {
            throw Exception("No valid trip rows found in file.");
          }

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
              _resetPagination();
            });
            await _fetchTripSummary();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Imported trips successfully added.'),
                ),
              );
            }
          }
        } else {
          throw Exception(decoded['error'] ?? "Upload failed.");
        }
      } else {
        String errorMsg = "Server error ${response.statusCode}";
        try {
          final decoded = jsonDecode(response.body);
          if (decoded['error'] != null) {
            errorMsg = decoded['error'];
          }
        } catch (_) {}
        throw Exception(errorMsg);
      }
    } catch (e) {
      if (!mounted) return;
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
      _resetPagination();
    });
    await _fetchTripSummary();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Trip summary batch added.')));
  }

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

    if (changed == true) {
      await _fetchTripSummary();
    }
  }

  String _monthYear(DateTime date) {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNarrow = MediaQuery.of(context).size.width < 1200;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _fetchTripSummary,
        child: Skeletonizer(
          enabled: _isLoading,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stackHeader = constraints.maxWidth < 1650;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(isDark, stackHeader, isNarrow),
                    const SizedBox(height: 18),
                    _buildSummaryCards(isDark, isNarrow),
                    const SizedBox(height: 20),
                    isNarrow
                        ? Column(
                            children: [
                              _isCalendarExpanded
                                  ? _buildCalendar(isDark, isNarrow)
                                  : _buildCollapsedCalendarBar(isDark, true),
                              const SizedBox(height: 18),
                              _buildTripWorkspace(isDark),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: _isCalendarExpanded
                                    ? SizedBox(
                                        width: 360,
                                        child: _buildCalendar(isDark, isNarrow),
                                      )
                                    : _buildCollapsedCalendarBar(isDark, false),
                              ),
                              const SizedBox(width: 20),
                              Expanded(child: _buildTripWorkspace(isDark)),
                            ],
                          ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, bool stackHeader, bool isNarrow) {
    return stackHeader
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle(isDark),
              const SizedBox(height: 14),
              _buildFilters(isDark, isNarrow),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildTitle(isDark)),
              _buildFilters(isDark, false),
            ],
          );
  }

  Widget _buildTitle(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${_trips.length} trip records  |  Last synchronized: ${_isRefreshing ? 'in progress' : 'current'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _buildTripWorkspace(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTripTabs(isDark),
        const SizedBox(height: 12),
        _activeTab == 0
            ? _buildSummaryTable(isDark)
            : _buildEditableSummarySheet(isDark),
      ],
    );
  }

  Widget _buildTripTabs(bool isDark) {
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _tabButton('Trip', 0, isDark),
          _tabButton('Summary', 1, isDark),
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
            color: selected ? const Color(0xFF2563EB) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.grey.shade300 : const Color(0xFF475569)),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(bool isDark, bool isNarrow) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        SizedBox(
          width: isNarrow ? double.infinity : 180,
          height: 42,
          child: TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _resetPagination();
              });
            },
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
          width: isNarrow ? double.infinity : 120,
          value: _filterMonth == null
              ? 'All Months'
              : _monthNames[_filterMonth! - 1],
          values: ['All Months', ..._monthNames],
          onChanged: (value) {
            setState(() {
              if (value == 'All Months') {
                _filterMonth = null;
              } else {
                _filterMonth = _monthNames.indexOf(value!) + 1;
                _selectedDate = null;
              }
              _resetPagination();
            });
          },
        ),
        _dropdown(
          isDark: isDark,
          width: isNarrow ? double.infinity : 110,
          value: _filterYear == null ? 'All Years' : _filterYear.toString(),
          values: ['All Years', ..._availableYears.map((y) => y.toString())],
          onChanged: (value) {
            setState(() {
              if (value == 'All Years') {
                _filterYear = null;
              } else {
                _filterYear = int.parse(value!);
                _selectedDate = null;
              }
              _resetPagination();
            });
          },
        ),
        _dropdown(
          isDark: isDark,
          width: isNarrow ? double.infinity : 140,
          value: _currentSort,
          values: ['Date (Newest)', 'Date (Oldest)'],
          onChanged: (value) {
            setState(() {
              _currentSort = value ?? 'Date (Newest)';
              _resetPagination();
            });
          },
        ),
        _dropdown(
          isDark: isDark,
          width: isNarrow ? double.infinity : 140,
          value: _driverOptions.contains(_selectedDriver)
              ? _selectedDriver
              : 'All Drivers',
          values: _driverOptions,
          onChanged: (value) {
            setState(() {
              _selectedDriver = value ?? 'All Drivers';
              _resetPagination();
            });
          },
        ),
        _dropdown(
          isDark: isDark,
          width: isNarrow ? double.infinity : 140,
          value: _vehicleOptions.contains(_selectedVehicle)
              ? _selectedVehicle
              : 'All Vehicles',
          values: _vehicleOptions,
          onChanged: (value) {
            setState(() {
              _selectedVehicle = value ?? 'All Vehicles';
              _resetPagination();
            });
          },
        ),
        if (widget.canManageSummaries) ...[
          SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _isRefreshing ? null : _importSummaryFile,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Import Excel'),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark
                    ? Colors.blue.shade300
                    : const Color(0xFF2563EB),
                side: BorderSide(
                  color: isDark ? Colors.blue.shade800 : Colors.blue.shade200,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _isRefreshing ? null : _showAddSummaryDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Trip Summary'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
        SizedBox(
          height: 42,
          width: 42,
          child: OutlinedButton(
            onPressed: _isRefreshing ? null : _fetchTripSummary,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.refresh, size: 19),
          ),
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
      fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
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
    final List<String> safeValues = values.toSet().toList();
    final String safeValue = safeValues.contains(value)
        ? value
        : safeValues.first;

    return Container(
      width: width,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          items: safeValues
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSummaryCards(bool isDark, bool isNarrow) {
    String selectedLabel = 'All Time';
    if (_selectedDate != null) {
      selectedLabel = _dateKey(_selectedDate!);
    } else if (_filterMonth != null && _filterYear != null) {
      selectedLabel = '${_monthNames[_filterMonth! - 1]} $_filterYear';
    } else if (_filterYear != null) {
      selectedLabel = 'Year $_filterYear';
    } else if (_filterMonth != null) {
      selectedLabel = '${_monthNames[_filterMonth! - 1]} (All Years)';
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = isNarrow
        ? 170.0
        : ((screenWidth - 520) / 4).clamp(185.0, 245.0).toDouble();
    final cards = [
      (
        'Rows',
        '${_visibleTrips.length}',
        Icons.receipt_long,
        const Color(0xFF3B82F6),
      ),
      (
        'Passengers',
        '$_totalPassengers',
        Icons.groups_outlined,
        const Color(0xFF10B981),
      ),
      (
        'Avg Utilization',
        '${(_averageUtilization * 100).round()}%',
        Icons.percent,
        const Color(0xFFF59E0B),
      ),
      (
        'Date Basis',
        selectedLabel,
        Icons.calendar_today,
        const Color(0xFF8B5CF6),
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: cards.asMap().entries.map((entry) {
          final index = entry.key;
          final card = entry.value;
          final isPrimary = index == 0;
          return Container(
            width: cardWidth,
            margin: EdgeInsets.only(right: index == cards.length - 1 ? 0 : 14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              border: Border.all(
                color: isPrimary
                    ? (isDark ? Colors.grey.shade300 : const Color(0xFF475569))
                    : (isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0)),
                width: isPrimary ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(card.$3, color: card.$4, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        card.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade400
                              : const Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCollapsedCalendarBar(bool isDark, bool isNarrow) {
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);
    final child = Container(
      width: isNarrow ? double.infinity : 64,
      height: isNarrow ? 58 : 560,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: isNarrow
          ? Row(
              children: [
                const Icon(Icons.event_note, color: Color(0xFF2563EB)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Show Calendar',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down),
              ],
            )
          : Column(
              children: [
                const Icon(Icons.event_note, color: Color(0xFF2563EB)),
                const SizedBox(height: 60),
                RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    'CALENDAR',
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ],
            ),
    );

    return InkWell(
      key: ValueKey('calendar-collapsed-$isNarrow'),
      borderRadius: BorderRadius.circular(4),
      onTap: () => setState(() => _isCalendarExpanded = true),
      child: child,
    );
  }

  Widget _buildCalendar(bool isDark, bool isNarrow) {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    ).day;
    final firstWeekday = firstDay.weekday % 7;
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);
    const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _isCalendarExpanded = false),
                  icon: Icon(
                    isNarrow ? Icons.keyboard_arrow_up : Icons.menu_open,
                  ),
                  tooltip: 'Collapse calendar',
                ),
                Expanded(
                  child: Text(
                    _monthYear(_focusedMonth),
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _focusedMonth = DateTime(
                      _focusedMonth.year,
                      _focusedMonth.month - 1,
                    );
                  }),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous month',
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _focusedMonth = DateTime(
                      _focusedMonth.year,
                      _focusedMonth.month + 1,
                    );
                  }),
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next month',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 0.95,
                    mainAxisSpacing: 5,
                    crossAxisSpacing: 5,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: daysInMonth + firstWeekday,
                  itemBuilder: (context, index) {
                    if (index < firstWeekday) return const SizedBox.shrink();
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
                    final isToday = _dateKey(DateTime.now()) == _dateKey(date);

                    return InkWell(
                      onTap: () => setState(() {
                        _selectedDate = isSelected ? null : date;
                        if (_selectedDate != null) {
                          _filterMonth = null;
                          _filterYear = null;
                        }
                        _resetPagination();
                      }),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF3B82F6)
                              : hasTrips
                              ? (isDark
                                    ? const Color(0xFF0F2D52)
                                    : const Color(0xFFEFF6FF))
                              : Colors.transparent,
                          border: Border.all(
                            color: isToday
                                ? const Color(0xFFF59E0B)
                                : isSelected
                                ? const Color(0xFF3B82F6)
                                : borderColor,
                          ),
                          borderRadius: BorderRadius.circular(4),
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
                                    ? const Color(0xFF3B82F6)
                                    : (isDark
                                          ? Colors.grey.shade300
                                          : const Color(0xFF0F172A)),
                                fontWeight: isSelected || hasTrips
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                            if (hasTrips)
                              Text(
                                '${trips.length}',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
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

  Widget _buildSummaryTable(bool isDark) {
    final rows = _visibleTrips;
    return EnterpriseDataGrid<Map<String, dynamic>>(
      rows: rows,
      loading: _isLoading,
      height: 560,
      rowKey: (trip) => Object.hash(
        trip['trip_id'],
        trip['summary_id'],
        trip['schedule_date'],
        trip['plate_number'],
      ),
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
        EnterpriseGridColumn(label: 'Util', width: 80, value: _utilizationText),
        EnterpriseGridColumn(
          label: 'Remarks',
          width: 180,
          value: (trip) => (trip['remarks'] ?? '').toString(),
        ),
        EnterpriseGridColumn(
          label: 'Action',
          width: 105,
          value: (_) => 'Open',
          cellBuilder: (context, trip) => TextButton.icon(
            onPressed: () => _showTripDetails(trip),
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('Open'),
          ),
        ),
      ],
      filterFields: [Chip(label: Text('${rows.length} trip records'))],
      emptyTitle: 'No trips match these filters',
      emptyMessage:
          'Clear the current date and status filters to restore the trip ledger.',
      emptyActionLabel: 'Clear filters',
      onEmptyAction: () => setState(() {
        _selectedDate = null;
        _filterMonth = null;
        _filterYear = null;
        _currentTripPage = 0;
      }),
    );
  }

  Widget _buildLegacySummaryTable(bool isDark) {
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);
    final rows = _isLoading ? List.generate(5, _skeletonTrip) : _visibleTrips;

    final int totalPages = max(1, (rows.length / _itemsPerPage).ceil());
    final paginatedRows = rows.isEmpty
        ? []
        : rows.sublist(
            _currentTripPage * _itemsPerPage,
            min((_currentTripPage + 1) * _itemsPerPage, rows.length),
          );

    String selectedLabel = 'All Time';
    if (_selectedDate != null) {
      selectedLabel = _dateKey(_selectedDate!);
    } else if (_filterMonth != null && _filterYear != null) {
      selectedLabel = '${_monthNames[_filterMonth! - 1]} $_filterYear';
    } else if (_filterYear != null) {
      selectedLabel = 'Year $_filterYear';
    } else if (_filterMonth != null) {
      selectedLabel = '${_monthNames[_filterMonth! - 1]} (All Years)';
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border.all(color: borderColor),
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
                    'Summary for $selectedLabel',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '${rows.length} rows',
                  style: TextStyle(
                    color: isDark
                        ? Colors.grey.shade400
                        : const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (!_isLoading && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No trip summary rows for the selected filters.',
                  style: TextStyle(
                    color: isDark
                        ? Colors.grey.shade400
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            )
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                ),
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Summary ID')),
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
                rows: paginatedRows.map((trip) {
                  return DataRow(
                    onSelectChanged: _isLoading
                        ? null
                        : (_) => _showTripDetails(trip),
                    cells: [
                      DataCell(
                        Text(
                          (trip['schedule_date'] ?? trip['date'] ?? '')
                              .toString(),
                        ),
                      ),
                      DataCell(Text((trip['summary_id'] ?? '').toString())),
                      DataCell(Text(_workingDay(trip))),
                      DataCell(
                        Text(
                          (trip['vehicle_type'] ?? trip['bus_type'] ?? '')
                              .toString(),
                        ),
                      ),
                      DataCell(Text((trip['classification'] ?? '').toString())),
                      DataCell(Text((trip['plate_number'] ?? '').toString())),
                      DataCell(
                        Text((trip['seating_capacity'] ?? '').toString()),
                      ),
                      DataCell(Text((trip['ticket_no'] ?? '').toString())),
                      DataCell(
                        Text((trip['driver_name'] ?? 'Unassigned').toString()),
                      ),
                      DataCell(Text((trip['route_name'] ?? '').toString())),
                      DataCell(
                        Text((trip['passenger_count'] ?? '').toString()),
                      ),
                      DataCell(Text(_timeText(trip['departure_time']))),
                      DataCell(Text(_timeText(trip['estimated_arrival_time']))),
                      DataCell(Text(_utilizationText(trip))),
                      DataCell(Text((trip['remarks'] ?? '').toString())),
                    ],
                  );
                }).toList(),
              ),
            ),
            if (totalPages > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${(_currentTripPage * _itemsPerPage) + 1} - ${min((_currentTripPage + 1) * _itemsPerPage, rows.length)} of ${rows.length} rows',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _currentTripPage > 0
                              ? () => setState(() => _currentTripPage--)
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0F172A)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Page ${_currentTripPage + 1} of $totalPages',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _currentTripPage < totalPages - 1
                              ? () => setState(() => _currentTripPage++)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditableSummarySheet(bool isDark) {
    final groups = _summaryGroups;
    return EnterpriseDataGrid<Map<String, dynamic>>(
      rows: groups,
      loading: _isLoading,
      height: 560,
      rowKey: (summary) => Object.hash(
        summary['summary_id'],
        summary['date'],
        summary['company'],
      ),
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
          cellBuilder: (context, summary) => TextButton.icon(
            onPressed: () => _showSummaryGroupDetails(summary),
            icon: const Icon(Icons.table_view_outlined, size: 15),
            label: const Text('Open'),
          ),
        ),
      ],
      filterFields: [Chip(label: Text('${groups.length} summaries'))],
      emptyTitle: 'No summaries match these filters',
      emptyMessage:
          'Clear the selected reporting period to restore summary batches.',
      emptyActionLabel: 'Clear filters',
      onEmptyAction: () => setState(() {
        _selectedDate = null;
        _filterMonth = null;
        _filterYear = null;
        _currentSummaryPage = 0;
      }),
    );
  }

  Widget _buildLegacyEditableSummarySheet(bool isDark) {
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);
    final groups = _isLoading
        ? List.generate(4, (index) {
            final row = _skeletonTrip(index);
            return {
              'summary_id': row['summary_id'],
              'date': row['schedule_date'],
              'company': row['client_company'],
              'working_day': row['working_day'],
              'rows': [row],
              'row_count': 1,
              'passenger_count': row['passenger_count'],
              'vehicles': row['plate_number'],
            };
          })
        : _summaryGroups;

    final int totalPages = max(1, (groups.length / _itemsPerPage).ceil());
    final paginatedGroups = groups.isEmpty
        ? []
        : groups.sublist(
            _currentSummaryPage * _itemsPerPage,
            min((_currentSummaryPage + 1) * _itemsPerPage, groups.length),
          );

    String selectedLabel = 'All Time';
    if (_selectedDate != null) {
      selectedLabel = _dateKey(_selectedDate!);
    } else if (_filterMonth != null && _filterYear != null) {
      selectedLabel = '${_monthNames[_filterMonth! - 1]} $_filterYear';
    } else if (_filterYear != null) {
      selectedLabel = 'Year $_filterYear';
    } else if (_filterMonth != null) {
      selectedLabel = '${_monthNames[_filterMonth! - 1]} (All Years)';
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border.all(color: borderColor),
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
                    'Summaries for $selectedLabel',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '${groups.length} summaries',
                  style: TextStyle(
                    color: isDark
                        ? Colors.grey.shade400
                        : const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (!_isLoading && groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No summaries for the selected filters.',
                  style: TextStyle(
                    color: isDark
                        ? Colors.grey.shade400
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            )
          else ...[
            Scrollbar(
              controller: _summaryListScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _summaryListScrollController,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  ),
                  dataRowMinHeight: 62,
                  dataRowMaxHeight: 68,
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('Summary ID')),
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Company')),
                    DataColumn(label: Text('Day')),
                    DataColumn(label: Text('Trips')),
                    DataColumn(label: Text('Passengers')),
                    DataColumn(label: Text('Vehicles')),
                    DataColumn(label: Text('Action')),
                  ],
                  rows: paginatedGroups.map((summary) {
                    return DataRow(
                      onSelectChanged: _isLoading
                          ? null
                          : (_) => _showSummaryGroupDetails(summary),
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 180,
                            child: Text(
                              (summary['summary_id'] ?? '').toString(),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 120,
                            child: Text((summary['date'] ?? '').toString()),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 180,
                            child: Text((summary['company'] ?? '').toString()),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 120,
                            child: Text(
                              (summary['working_day'] ?? '').toString(),
                            ),
                          ),
                        ),
                        DataCell(Text('${summary['row_count'] ?? 0}')),
                        DataCell(Text('${summary['passenger_count'] ?? 0}')),
                        DataCell(
                          SizedBox(
                            width: 260,
                            child: Text((summary['vehicles'] ?? '').toString()),
                          ),
                        ),
                        DataCell(
                          TextButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () => _showSummaryGroupDetails(summary),
                            icon: const Icon(Icons.table_view, size: 18),
                            label: const Text('Open'),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            if (totalPages > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${(_currentSummaryPage * _itemsPerPage) + 1} - ${min((_currentSummaryPage + 1) * _itemsPerPage, groups.length)} of ${groups.length} batches',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _currentSummaryPage > 0
                              ? () => setState(() => _currentSummaryPage--)
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0F172A)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Page ${_currentSummaryPage + 1} of $totalPages',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _currentSummaryPage < totalPages - 1
                              ? () => setState(() => _currentSummaryPage++)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic> _skeletonTrip(int index) {
    return {
      'summary_id': 'SUM-LOADING',
      'schedule_date': _dateKey(DateTime.now()),
      'working_day': 'LOADING',
      'bus_type': 'VAN',
      'vehicle_type': 'VAN',
      'classification': 'IN7AM',
      'plate_number': 'ABC1234',
      'seating_capacity': 14,
      'ticket_no': '000000',
      'driver_name': 'Loading Driver',
      'route_name': 'Loading Route',
      'passenger_count': 14,
      'departure_time': '07:00',
      'estimated_arrival_time': '08:00',
      'utilization_rate': 1,
      'remarks': '',
    };
  }
}

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

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export successfully triggered!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
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
      if (outputFile != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel export completed.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel export failed: $e')));
      }
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
                  if (changed == true && context.mounted) {
                    Navigator.pop(context, true);
                  }
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
