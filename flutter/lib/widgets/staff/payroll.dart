import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../layouts/enterprise/enterprise_states.dart';
import 'package:http/http.dart' as http;

import '../../constant.dart';
import '../../utils/file_download.dart';
import '../../layouts/enterprise/enterprise_data_grid.dart';
import '../interface/universal_pagination.dart';

class Payroll extends StatefulWidget {
  final String userRole;

  const Payroll({super.key, required this.userRole});

  @override
  State<Payroll> createState() => _PayrollState();
}

class _PayrollState extends State<Payroll> {
  final _regularPayController = TextEditingController(text: '600');
  final _halfDayDeductionController = TextEditingController(text: '300');
  final _absentDeductionController = TextEditingController(text: '600');
  final _overtimePayController = TextEditingController(text: '100');
  final _searchController = TextEditingController();
  final _tableScrollController = ScrollController();
  final Map<String, TextEditingController> _routeRateControllers = {};
  final Map<String, String> _routeNamesById = {};

  bool _isLoading = true;
  bool _ratesExpanded = false;
  String? _error;
  String _searchQuery = '';
  String _payrollFilter = 'All';
  int _currentPage = 0;
  static const int _rowsPerPage = 10;
  DateTime _payDate = _currentPayThursday(DateTime.now());
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _destinations = [];

  @override
  void initState() {
    super.initState();
    _loadPayrollData();
  }

  @override
  void dispose() {
    _regularPayController.dispose();
    _halfDayDeductionController.dispose();
    _absentDeductionController.dispose();
    _overtimePayController.dispose();
    _searchController.dispose();
    _tableScrollController.dispose();
    for (final controller in _routeRateControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  static DateTime _currentPayThursday(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final daysUntilThursday = DateTime.thursday - day.weekday;
    return day.add(
      Duration(
        days: daysUntilThursday >= 0
            ? daysUntilThursday
            : daysUntilThursday + 7,
      ),
    );
  }

  DateTime get _periodStart => _payDate.subtract(const Duration(days: 6));

  Future<void> _loadPayrollData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final payload = await _getPayrollContext();
      final drivers = _asList(payload['drivers']);
      final attendance = _asList(payload['attendance']);
      final trips = _asList(payload['trips']);
      final destinations = _asList(payload['destinations']);

      if (!mounted) return;
      setState(() {
        _drivers = drivers;
        _attendance = attendance;
        _trips = trips;
        _destinations = destinations;
        _currentPage = 0;
        _syncRouteRates();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Unable to load payroll data: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Request failed ${response.statusCode}: $url');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  Future<Map<String, dynamic>> _getPayrollContext() async {
    final start = _dateKey(_periodStart);
    final end = _dateKey(_payDate);
    try {
      return await _getJson(
        '$backendUrl/payroll/context?start=$start&end=$end',
      );
    } catch (_) {
      final results = await Future.wait([
        _getJson('$backendUrl/${widget.userRole}/attendance'),
        _getJson('$backendUrl/schedules/staff-summary/all'),
      ]);
      final driversPayload = await _getJsonOrEmpty('$backendUrl/driver/all');
      return {
        'drivers':
            driversPayload['sample_data_payload'] ??
            driversPayload['data'] ??
            driversPayload['drivers'],
        'attendance': results[0]['data'] ?? results[0]['attendance'],
        'trips': results[1]['data'] ?? results[1]['trips'],
        'destinations': [],
      };
    }
  }

  Future<Map<String, dynamic>> _getJsonOrEmpty(String url) async {
    try {
      return await _getJson(url);
    } catch (_) {
      return {};
    }
  }

  List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  void _syncRouteRates() {
    final routeRows = <String, Map<String, dynamic>>{};
    _routeNamesById.clear();

    for (final destination in _destinations) {
      final route = _cleanText(destination['route_name']);
      if (route.isEmpty) continue;
      routeRows[_normalizedRouteKey(route)] = destination;
    }

    final routes =
        routeRows.values
            .map(
              (row) => _cleanText(row['route_name'] ?? row['destination_name']),
            )
            .where((route) => route.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    for (final route in routes) {
      final routeRow = routeRows[_normalizedRouteKey(route)] ?? {};
      final routeId = routeRow['route_id'];
      if (routeId != null) {
        _routeNamesById[_cleanText(routeId)] = route;
      }
      final price = _money(
        _cleanText(routeRow['price'] ?? routeRow['destination_price']),
      );
      _routeRateControllers.putIfAbsent(
        route,
        () => TextEditingController(text: price.toStringAsFixed(2)),
      );
    }
  }

  List<Map<String, dynamic>> get _periodTrips {
    return _trips.where((trip) {
      final date = _parseDate(trip['schedule_date'] ?? trip['date']);
      return date != null &&
          !_dateOnly(date).isBefore(_periodStart) &&
          !_dateOnly(date).isAfter(_payDate);
    }).toList();
  }

  List<Map<String, dynamic>> get _periodAttendance {
    return _attendance.where((row) {
      final date = _parseDate(row['work_date'] ?? row['date']);
      return date != null &&
          !_dateOnly(date).isBefore(_periodStart) &&
          !_dateOnly(date).isAfter(_payDate);
    }).toList();
  }

  List<_PayrollRow> get _payrollRows {
    final attendanceByDriver = <String, Map<String, Map<String, dynamic>>>{};
    for (final row in _periodAttendance) {
      final driverId = _driverIdFromAttendance(row);
      final date = _parseDate(row['work_date'] ?? row['date']);
      if (driverId.isEmpty || date == null) continue;
      attendanceByDriver.putIfAbsent(driverId, () => {})[_dateKey(date)] = row;
    }

    final tripsByDriver = <String, List<Map<String, dynamic>>>{};
    for (final trip in _periodTrips) {
      final driverId = _cleanText(trip['driver_id']);
      if (driverId.isEmpty) continue;
      tripsByDriver.putIfAbsent(driverId, () => []).add(trip);
    }

    final driverIds = <String>{
      ..._drivers
          .map((driver) => _cleanText(driver['driver_id']))
          .where((id) => id.isNotEmpty),
      ...attendanceByDriver.keys,
      ...tripsByDriver.keys,
    }.toList()..sort((a, b) => _driverName(a).compareTo(_driverName(b)));

    return driverIds.map((driverId) {
      final attendanceDays = attendanceByDriver[driverId] ?? {};
      final absenceEnd = _absenceEvaluationEnd;
      var presentDays = 0;
      var halfDays = 0;
      var overtimeDays = 0;
      var absentDays = 0;

      for (var index = 0; index < 7; index++) {
        final date = _periodStart.add(Duration(days: index));
        if (date.isAfter(absenceEnd)) continue;
        final row = attendanceDays[_dateKey(date)];
        if (row == null || _isAbsent(row)) {
          absentDays++;
          continue;
        }
        if (_isHalfDay(row)) {
          halfDays++;
        } else {
          presentDays++;
        }
        if (_hasValue(row['overtime_in']) || _hasValue(row['overtime_out'])) {
          overtimeDays++;
        }
      }

      final driverTrips = tripsByDriver[driverId] ?? [];
      final routeBreakdown = <String, int>{};
      for (final trip in driverTrips) {
        final route = _tripDestinationName(trip);
        routeBreakdown[route] = (routeBreakdown[route] ?? 0) + 1;
      }

      final regularRate = _money(_regularPayController.text);
      final halfDeduction = _money(_halfDayDeductionController.text);
      final absentDeduction = _money(_absentDeductionController.text);
      final overtimeRate = _money(_overtimePayController.text);

      final regularPay = (presentDays + halfDays) * regularRate;
      final halfDayPenalty = halfDays * halfDeduction;
      final absentPenalty = absentDays * absentDeduction;
      final overtimePay = overtimeDays * overtimeRate;
      final tripPay = driverTrips.fold<double>(0, (total, trip) {
        return total + _rateForTrip(trip);
      });

      return _PayrollRow(
        driverId: driverId,
        driverName: _driverName(driverId),
        presentDays: presentDays,
        halfDays: halfDays,
        absentDays: absentDays,
        overtimeDays: overtimeDays,
        tripCount: driverTrips.length,
        routeBreakdown: routeBreakdown,
        regularPay: regularPay,
        halfDayDeduction: halfDayPenalty,
        absentDeduction: absentPenalty,
        overtimePay: overtimePay,
        tripPay: tripPay,
      );
    }).toList();
  }

  DateTime get _absenceEvaluationEnd {
    final today = _dateOnly(DateTime.now());
    return _payDate.isBefore(today) ? _payDate : today;
  }

  List<_PayrollRow> get _filteredPayrollRows {
    final query = _searchQuery.trim().toLowerCase();
    return _payrollRows.where((row) {
      final matchesSearch =
          query.isEmpty ||
          row.driverId.toLowerCase().contains(query) ||
          row.driverName.toLowerCase().contains(query);
      if (!matchesSearch) return false;

      switch (_payrollFilter) {
        case 'With Absences':
          return row.absentDays > 0;
        case 'With Half Days':
          return row.halfDays > 0;
        case 'With Overtime':
          return row.overtimeDays > 0;
        case 'With Trips':
          return row.tripCount > 0;
        case 'Payable':
          return row.netPay > 0;
        default:
          return true;
      }
    }).toList();
  }

  int get _totalPages {
    final total = (_filteredPayrollRows.length / _rowsPerPage).ceil();
    return total < 1 ? 1 : total;
  }

  List<_PayrollRow> get _pagedPayrollRows {
    final rows = _filteredPayrollRows;
    if (_currentPage >= _totalPages) _currentPage = _totalPages - 1;
    final start = _currentPage * _rowsPerPage;
    final end = start + _rowsPerPage > rows.length
        ? rows.length
        : start + _rowsPerPage;
    return rows.sublist(start, end);
  }

  String _driverName(String driverId) {
    for (final driver in _drivers) {
      if (_cleanText(driver['driver_id']) == driverId) {
        final name = _cleanText(driver['full_name'] ?? driver['name']);
        if (name.isNotEmpty) return name;
      }
    }
    for (final trip in _trips) {
      if (_cleanText(trip['driver_id']) == driverId) {
        final name = _cleanText(trip['driver_name']);
        if (name.isNotEmpty && name != 'Unassigned') return name;
      }
    }
    for (final row in _attendance) {
      if (_driverIdFromAttendance(row) == driverId) {
        final name = _attendanceName(row);
        if (name.isNotEmpty && name != 'Unknown') return name;
      }
    }
    return 'Driver $driverId';
  }

  String _tripDestinationName(Map<String, dynamic> trip) {
    final routeId = _cleanText(trip['route_id']);
    if (routeId.isNotEmpty && _routeNamesById.containsKey(routeId)) {
      return _routeNamesById[routeId]!;
    }
    return _cleanText(
      trip['destination_name'] ??
          trip['destination'] ??
          trip['route_name'] ??
          trip['route'] ??
          'Unspecified Route',
    );
  }

  double _rateForTrip(Map<String, dynamic> trip) {
    final routeId = _cleanText(trip['route_id']);
    if (routeId.isNotEmpty && _routeNamesById.containsKey(routeId)) {
      final routeName = _routeNamesById[routeId]!;
      final controller = _routeRateControllers[routeName];
      if (controller != null) return _money(controller.text);
    }

    final tripRoute = _tripDestinationName(trip);
    final exactController = _routeRateControllers[tripRoute];
    if (exactController != null) return _money(exactController.text);

    final normalizedTripRoute = _normalizedRouteKey(tripRoute);
    for (final entry in _routeRateControllers.entries) {
      if (_normalizedRouteKey(entry.key) == normalizedTripRoute) {
        return _money(entry.value.text);
      }
    }

    return _money(_cleanText(trip['destination_price']));
  }

  String _normalizedRouteKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _driverIdFromAttendance(Map<String, dynamic> row) {
    final direct = _cleanText(row['driver_id']);
    if (direct.isNotEmpty) return direct;

    final employeeId = _cleanText(row['employee_id']);
    final idMatch = RegExp(r'\d+').firstMatch(employeeId);
    if (idMatch != null) return idMatch.group(0)!;

    final employee = _cleanText(row['employee'] ?? row['employee_name']);
    final labelMatch = RegExp(r'\((\d+)\)').firstMatch(employee);
    return labelMatch?.group(1) ?? '';
  }

  String _attendanceName(Map<String, dynamic> row) {
    final direct = _cleanText(row['employee_name']);
    if (direct.isNotEmpty) return direct;

    final employee = _cleanText(row['employee']);
    final labelMatch = RegExp(r'^(.*?)\s*\(').firstMatch(employee);
    return (labelMatch?.group(1) ?? employee).trim();
  }

  bool _isHalfDay(Map<String, dynamic> row) {
    if (_isAbsent(row)) return false;
    final hasMorning =
        _hasValue(row['morning_in']) || _hasValue(row['morning_out']);
    final hasAfternoon =
        _hasValue(row['afternoon_in']) || _hasValue(row['afternoon_out']);
    return hasMorning != hasAfternoon;
  }

  bool _isAbsent(Map<String, dynamic> row) {
    final note = _cleanText(row['note'] ?? row['notes']).toLowerCase();
    if (note.contains('absent') || note.contains('whole day')) return true;
    return ![
      row['morning_in'],
      row['morning_out'],
      row['afternoon_in'],
      row['afternoon_out'],
      row['overtime_in'],
      row['overtime_out'],
      row['time_in'],
      row['time_out'],
    ].any(_hasValue);
  }

  bool _hasValue(dynamic value) {
    final text = _cleanText(value).toLowerCase();
    return text.isNotEmpty && text != 'nan' && text != 'null' && text != '-';
  }

  DateTime? _parseDate(dynamic value) {
    final text = _cleanText(value);
    if (text.isEmpty || text.toLowerCase() == 'nan') return null;
    try {
      return DateTime.parse(text.split('T').first);
    } catch (_) {
      return null;
    }
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _cleanText(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    return text == 'null' ? '' : text;
  }

  double _money(String value) {
    return double.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }

  String _moneyLabel(num value) {
    return 'PHP ${value.toStringAsFixed(2)}';
  }

  String _dateLabel(DateTime date) {
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

  Future<void> _pickPayDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _payDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      selectableDayPredicate: (date) => date.weekday == DateTime.thursday,
    );
    if (picked == null) return;
    setState(() {
      _payDate = DateTime(picked.year, picked.month, picked.day);
      _currentPage = 0;
      _syncRouteRates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allRows = _payrollRows;
    final rows = _filteredPayrollRows;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isDark),
          const SizedBox(height: 20),
          _buildRatesPanel(isDark),
          const SizedBox(height: 20),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: EnterpriseLoadingIndicator(),
              ),
            )
          else if (_error != null)
            _buildMessage(_error!, Icons.error_outline, Colors.red)
          else if (allRows.isEmpty)
            _buildMessage(
              'No payroll data found for this pay period.',
              Icons.payments_outlined,
              Colors.blueGrey,
            )
          else ...[
            _buildTableToolbar(isDark, rows.length),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              _buildNoMatchesMessage()
            else ...[
              _buildPayrollTable(_pagedPayrollRows, isDark),
              const SizedBox(height: 16),
              UniversalPagination(
                currentPage: _currentPage,
                totalPages: _totalPages,
                totalItems: rows.length,
                itemsPerPage: _rowsPerPage,
                itemName: 'drivers',
                onPrevPage: _currentPage > 0
                    ? () => setState(() => _currentPage--)
                    : null,
                onNextPage: _currentPage < _totalPages - 1
                    ? () => setState(() => _currentPage++)
                    : null,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Pay period: ${_dateLabel(_periodStart)} - ${_dateLabel(_payDate)}  |  ${_payrollRows.length} drivers',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _buildRatesPanel(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _ratesExpanded,
          onExpansionChanged: (value) => setState(() => _ratesExpanded = value),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          leading: const Icon(Icons.tune),
          title: Text(
            'Payroll Rates',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          subtitle: Text(
            'Regular pay, deductions, and overtime',
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _loadPayrollData,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
              ),
              Icon(_ratesExpanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _amountField('Regular pay/day', _regularPayController),
                _amountField('Half-day deduction', _halfDayDeductionController),
                _amountField('Absent deduction', _absentDeductionController),
                _amountField('Overtime/day', _overtimePayController),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountField(String label, TextEditingController controller) {
    return SizedBox(
      width: 180,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: 'PHP ',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildTableToolbar(bool isDark, int totalRows) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 340,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search driver ID or name',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _currentPage = 0;
                });
              },
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              value: _payrollFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.filter_list),
                labelText: 'Filter',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'All', child: Text('All')),
                DropdownMenuItem(value: 'Payable', child: Text('Payable')),
                DropdownMenuItem(
                  value: 'With Absences',
                  child: Text('With Absences'),
                ),
                DropdownMenuItem(
                  value: 'With Half Days',
                  child: Text('With Half Days'),
                ),
                DropdownMenuItem(
                  value: 'With Overtime',
                  child: Text('With Overtime'),
                ),
                DropdownMenuItem(
                  value: 'With Trips',
                  child: Text('With Trips'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _payrollFilter = value;
                  _currentPage = 0;
                });
              },
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _payPeriodBadge(isDark),
              OutlinedButton.icon(
                onPressed: _pickPayDate,
                icon: const Icon(Icons.event),
                label: Text('Pay Thursday: ${_dateLabel(_payDate)}'),
              ),
              Text(
                '$totalRows driver${totalRows == 1 ? '' : 's'}',
                style: TextStyle(
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
    );
  }

  Widget _payPeriodBadge(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.date_range, size: 18, color: Colors.blue.shade500),
          const SizedBox(width: 8),
          Text(
            'Pay Period: ${_dateLabel(_periodStart)} - ${_dateLabel(_payDate)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollTable(List<_PayrollRow> rows, bool isDark) {
    return EnterpriseDataGrid<_PayrollRow>(
      rows: rows,
      paginate: false,
      rowKey: (row) => row.driverId,
      height: 500,
      showDateRange: false,
      columns: [
        EnterpriseGridColumn(
          label: 'Driver',
          width: 250,
          value: (row) => '${row.driverName}  #${row.driverId}',
        ),
        EnterpriseGridColumn(
          label: 'Present',
          width: 110,
          value: (row) => '${row.presentDays}',
          compare: (first, second) =>
              first.presentDays.compareTo(second.presentDays),
        ),
        EnterpriseGridColumn(
          label: 'Half day',
          width: 110,
          value: (row) => '${row.halfDays}',
        ),
        EnterpriseGridColumn(
          label: 'Absent',
          width: 110,
          value: (row) => '${row.absentDays}',
        ),
        EnterpriseGridColumn(
          label: 'Trips',
          width: 110,
          value: (row) => '${row.tripCount}',
        ),
        EnterpriseGridColumn(
          label: 'Regular pay',
          width: 160,
          value: (row) => _moneyLabel(row.regularPay),
          compare: (first, second) =>
              first.regularPay.compareTo(second.regularPay),
        ),
        EnterpriseGridColumn(
          label: 'Deductions',
          width: 160,
          value: (row) => '-${_moneyLabel(row.totalDeductions)}',
          compare: (first, second) =>
              first.totalDeductions.compareTo(second.totalDeductions),
        ),
        EnterpriseGridColumn(
          label: 'Overtime',
          width: 150,
          value: (row) => _moneyLabel(row.overtimePay),
        ),
        EnterpriseGridColumn(
          label: 'Route pay',
          width: 150,
          value: (row) => _moneyLabel(row.tripPay),
        ),
        EnterpriseGridColumn(
          label: 'Total pay',
          width: 170,
          value: (row) => _moneyLabel(row.netPay),
          compare: (first, second) => first.netPay.compareTo(second.netPay),
          cellBuilder: (context, row) => Text(
            _moneyLabel(row.netPay),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
      emptyTitle: 'Prepare this payroll period',
      emptyMessage:
          'Attendance and trip records are required before driver payroll can be calculated.',
      emptyActionLabel: 'Refresh payroll data',
      onEmptyAction: _loadPayrollData,
      onExportSelection: _exportPayrollSelection,
    );
  }

  Future<void> _exportPayrollSelection(List<_PayrollRow> rows) async {
    final buffer = StringBuffer(
      'Driver ID,Driver,Present,Half Day,Absent,Trips,Regular Pay,Deductions,Overtime,Route Pay,Total Pay\n',
    );
    for (final row in rows) {
      buffer.writeln(
        '${row.driverId},"${row.driverName.replaceAll('"', '""')}",'
        '${row.presentDays},${row.halfDays},${row.absentDays},${row.tripCount},'
        '${row.regularPay},${row.totalDeductions},${row.overtimePay},'
        '${row.tripPay},${row.netPay}',
      );
    }
    await downloadFileBytes(
      fileName: 'shervice-payroll-selection.csv',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
    );
    if (mounted) {
      EnterpriseToasts.success(
        context,
        '${rows.length} payroll rows exported.',
      );
    }
  }

  Widget _buildMessage(String message, IconData icon, Color color) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(icon, color: color, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchesMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.filter_alt_off, color: Colors.blueGrey.shade400, size: 42),
          const SizedBox(height: 12),
          const Text('No drivers match the current payroll filter.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _payrollFilter = 'All';
                _searchQuery = '';
                _searchController.clear();
                _currentPage = 0;
              });
            },
            icon: const Icon(Icons.clear),
            label: const Text('Clear Filter'),
          ),
        ],
      ),
    );
  }
}

class _PayrollRow {
  final String driverId;
  final String driverName;
  final int presentDays;
  final int halfDays;
  final int absentDays;
  final int overtimeDays;
  final int tripCount;
  final Map<String, int> routeBreakdown;
  final double regularPay;
  final double halfDayDeduction;
  final double absentDeduction;
  final double overtimePay;
  final double tripPay;

  const _PayrollRow({
    required this.driverId,
    required this.driverName,
    required this.presentDays,
    required this.halfDays,
    required this.absentDays,
    required this.overtimeDays,
    required this.tripCount,
    required this.routeBreakdown,
    required this.regularPay,
    required this.halfDayDeduction,
    required this.absentDeduction,
    required this.overtimePay,
    required this.tripPay,
  });

  double get totalDeductions => halfDayDeduction + absentDeduction;

  double get netPay => regularPay - totalDeductions + overtimePay + tripPay;

  String get routeSummary {
    if (routeBreakdown.isEmpty) return 'No trips this period';
    return routeBreakdown.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
  }
}
