import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/material.dart';
import '../layouts/enterprise/enterprise_states.dart';
import 'package:http/http.dart' as http;

import '../constant.dart';
import '../utilities/file_download.dart';
import '../layouts/enterprise/enterprise_data_grid.dart';

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
  final Map<String, TextEditingController> _routeRateControllers = {};
  final Map<String, String> _routeNamesById = {};

  bool _isLoading = true;
  bool _isSavingRates = false;
  bool _ratesExpanded = false;
  String? _error;
  String _searchQuery = '';
  String _payrollFilter = 'All';
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
      final settings = payload['settings'];

      if (!mounted) return;
      setState(() {
        _drivers = drivers;
        _attendance = attendance;
        _trips = trips;
        _destinations = destinations;
        _applyPayrollSettings(settings);
        _syncRouteRates();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Unable to load payroll data: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyPayrollSettings(dynamic value) {
    if (value is! Map) return;
    final settings = Map<String, dynamic>.from(value);
    _setControllerValue(_regularPayController, settings['regular_pay']);
    _setControllerValue(
      _halfDayDeductionController,
      settings['half_day_deduction'],
    );
    _setControllerValue(
      _absentDeductionController,
      settings['absent_deduction'],
    );
    _setControllerValue(_overtimePayController, settings['overtime_pay']);
  }

  void _setControllerValue(TextEditingController controller, dynamic value) {
    final amount = double.tryParse('$value');
    if (amount != null) controller.text = amount.toStringAsFixed(2);
  }

  Future<void> _savePayrollSettings() async {
    final values = <String, double?>{
      'regular_pay': double.tryParse(_regularPayController.text.trim()),
      'half_day_deduction': double.tryParse(
        _halfDayDeductionController.text.trim(),
      ),
      'absent_deduction': double.tryParse(
        _absentDeductionController.text.trim(),
      ),
      'overtime_pay': double.tryParse(_overtimePayController.text.trim()),
    };
    if (values.values.any((value) => value == null || value < 0)) {
      _showRateMessage(
        'Enter non-negative numbers for every rate.',
        isError: true,
      );
      return;
    }

    setState(() => _isSavingRates = true);
    try {
      final response = await http.put(
        Uri.parse('$backendUrl/payroll/settings'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(values),
      );
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || payload['success'] != true) {
        throw Exception(payload['message'] ?? 'Unable to save payroll rates.');
      }
      _applyPayrollSettings(payload['settings']);
      _showRateMessage('Payroll rates saved.');
      if (mounted) setState(() {});
    } catch (error) {
      _showRateMessage('Unable to save payroll rates: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingRates = false);
    }
  }

  void _showRateMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
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
      _syncRouteRates();
    });
  }

  String _csvEscape(String value) => '"${value.replaceAll('"', '""')}"';

  String _payrollCsv(List<_PayrollRow> rows) {
    final buffer = StringBuffer()
      ..writeln(
        'Payroll Period,${_csvEscape('${_dateLabel(_periodStart)} - ${_dateLabel(_payDate)}')}',
      )
      ..writeln('Generated,${_csvEscape(DateTime.now().toIso8601String())}')
      ..writeln()
      ..writeln(
        [
          'Driver ID',
          'Driver',
          'Present',
          'Half Day',
          'Absent',
          'Overtime Days',
          'Trips',
          'Route Breakdown',
          'Regular Pay',
          'Deductions',
          'Overtime',
          'Route Pay',
          'Total Pay',
        ].map(_csvEscape).join(','),
      );

    for (final row in rows) {
      buffer.writeln(
        [
          row.driverId,
          row.driverName,
          '${row.presentDays}',
          '${row.halfDays}',
          '${row.absentDays}',
          '${row.overtimeDays}',
          '${row.tripCount}',
          row.routeSummary,
          row.regularPay.toStringAsFixed(2),
          row.totalDeductions.toStringAsFixed(2),
          row.overtimePay.toStringAsFixed(2),
          row.tripPay.toStringAsFixed(2),
          row.netPay.toStringAsFixed(2),
        ].map(_csvEscape).join(','),
      );
    }

    return buffer.toString();
  }

  Uint8List _payrollXlsx(List<_PayrollRow> rows) {
    final excel = xlsx.Excel.createExcel();
    final sheet = excel['Payroll'];

    sheet.appendRow([
      xlsx.TextCellValue('Payroll Period'),
      xlsx.TextCellValue(
        '${_dateLabel(_periodStart)} - ${_dateLabel(_payDate)}',
      ),
    ]);
    sheet.appendRow([
      xlsx.TextCellValue('Generated'),
      xlsx.TextCellValue(DateTime.now().toIso8601String()),
    ]);
    sheet.appendRow([xlsx.TextCellValue('')]);

    const headers = [
      'Driver ID',
      'Driver',
      'Present',
      'Half Day',
      'Absent',
      'Overtime Days',
      'Trips',
      'Route Breakdown',
      'Regular Pay',
      'Deductions',
      'Overtime',
      'Route Pay',
      'Total Pay',
    ];
    sheet.appendRow(headers.map((value) => xlsx.TextCellValue(value)).toList());

    for (final row in rows) {
      sheet.appendRow(
        [
          row.driverId,
          row.driverName,
          '${row.presentDays}',
          '${row.halfDays}',
          '${row.absentDays}',
          '${row.overtimeDays}',
          '${row.tripCount}',
          row.routeSummary,
          row.regularPay.toStringAsFixed(2),
          row.totalDeductions.toStringAsFixed(2),
          row.overtimePay.toStringAsFixed(2),
          row.tripPay.toStringAsFixed(2),
          row.netPay.toStringAsFixed(2),
        ].map((value) => xlsx.TextCellValue(value)).toList(),
      );
    }

    excel.setDefaultSheet('Payroll');
    final headerStyle = xlsx.CellStyle(
      backgroundColorHex: xlsx.ExcelColor.fromHexString('FF1E3A8A'),
      fontColorHex: xlsx.ExcelColor.white,
      bold: true,
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
      sheet.setColumnWidth(column, column == 7 ? 26 : 16);
    }

    return Uint8List.fromList(excel.encode()!);
  }

  Future<void> _downloadPayrollCsv(
    List<_PayrollRow> rows, {
    required String fileName,
  }) async {
    if (rows.isEmpty) {
      EnterpriseToasts.error(context, 'No payroll rows to export.');
      return;
    }

    await downloadFileBytes(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(_payrollCsv(rows))),
    );
    if (mounted) {
      EnterpriseToasts.success(
        context,
        '${rows.length} payroll rows exported.',
      );
    }
  }

  Future<void> _downloadPayrollXlsx(
    List<_PayrollRow> rows, {
    required String fileName,
  }) async {
    if (rows.isEmpty) {
      EnterpriseToasts.error(context, 'No payroll rows to export.');
      return;
    }

    await downloadFileBytes(fileName: fileName, bytes: _payrollXlsx(rows));
    if (mounted) {
      EnterpriseToasts.success(
        context,
        '${rows.length} payroll rows exported.',
      );
    }
  }

  Future<void> _exportPayrollSelection(List<_PayrollRow> rows) async {
    await _downloadPayrollCsv(rows, fileName: 'shervice-payroll-selection.csv');
  }

  Future<void> _exportPayrollSelectionXlsx(List<_PayrollRow> rows) async {
    await _downloadPayrollXlsx(
      rows,
      fileName: 'shervice-payroll-selection.xlsx',
    );
  }

  // ---------------------------------------------------------
  // UI BUILD METHODS
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = _filteredPayrollRows;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 768;
          return Padding(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. TOP ROW: Title on Left, Refresh on Right
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payroll',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _loadPayrollData,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 8 : 16),

                // 2. RATES PANEL (Sleeker, compact container)
                _buildRatesPanel(isDark),
                SizedBox(height: compact ? 8 : 16),

                // 3. FILTERS (Anchored Top-Left)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildFilters(isDark),
                ),
                SizedBox(height: compact ? 8 : 16),

                // 4. MAIN WORKSPACE TABLE (Expanded to fill space)
                Expanded(
                  child: _isLoading
                      ? const EnterpriseTableSkeleton(columns: 9)
                      : _error != null
                      ? EnterpriseEmptyState(
                          icon: Icons.error_outline,
                          title: 'Error Loading Payroll',
                          message: _error!,
                          actionLabel: 'Retry',
                          onAction: _loadPayrollData,
                        )
                      : EnterpriseDataGrid<_PayrollRow>(
                          rows: rows,
                          rowKey: (row) => row.driverId,
                          height: double.infinity,
                          showDateRange: false,
                          filterFields:
                              const [], // Cleared to prevent middle rendering
                          columns: [
                            EnterpriseGridColumn(
                              label: 'Driver',
                              width: 250,
                              value: (row) =>
                                  '${row.driverName}  #${row.driverId}',
                            ),
                            EnterpriseGridColumn(
                              label: 'Present',
                              width: 110,
                              value: (row) => '${row.presentDays}',
                              compare: (first, second) => first.presentDays
                                  .compareTo(second.presentDays),
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
                              value: (row) =>
                                  '-${_moneyLabel(row.totalDeductions)}',
                              compare: (first, second) => first.totalDeductions
                                  .compareTo(second.totalDeductions),
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
                              compare: (first, second) =>
                                  first.netPay.compareTo(second.netPay),
                              cellBuilder: (context, row) => Text(
                                _moneyLabel(row.netPay),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          emptyTitle: 'Prepare this payroll period',
                          emptyMessage:
                              'Attendance and trip records are required before driver payroll can be calculated.',
                          emptyActionLabel: 'Refresh payroll data',
                          onEmptyAction: _loadPayrollData,
                          onExportSelection: _exportPayrollSelection,
                          exportSelectionLabel: 'Export CSV',
                          onSecondaryExportSelection:
                              _exportPayrollSelectionXlsx,
                          secondaryExportSelectionLabel: 'Export XLSX',
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRatesPanel(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Theme.of(context).dividerColor,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _ratesExpanded,
          onExpansionChanged: (value) => setState(() => _ratesExpanded = value),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(
            Icons.tune,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            'Payroll Rates Configuration',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 15,
                  runSpacing: 15,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _amountField(
                      'Regular pay/day',
                      _regularPayController,
                      isDark,
                    ),
                    _amountField(
                      'Half-day deduction',
                      _halfDayDeductionController,
                      isDark,
                    ),
                    _amountField(
                      'Absent deduction',
                      _absentDeductionController,
                      isDark,
                    ),
                    _amountField(
                      'Overtime/day',
                      _overtimePayController,
                      isDark,
                    ),
                    if (widget.userRole.toLowerCase() == 'admin')
                      FilledButton.icon(
                        onPressed: _isSavingRates ? null : _savePayrollSettings,
                        icon: _isSavingRates
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 16),
                        label: Text(
                          _isSavingRates ? 'Saving...' : 'Save rates',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountField(
    String label,
    TextEditingController controller,
    bool isDark,
  ) {
    return SizedBox(
      width: 170,
      height: 56,
      child: TextField(
        controller: controller,
        readOnly: widget.userRole.toLowerCase() != 'admin',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          prefixText: 'PHP ',
          isDense: true,
          filled: true,
          fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildFilters(bool isDark) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          height: 34,
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: 'Search driver ID or name...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF64748B),
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 0,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
          ),
        ),
        Container(
          width: 170,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _payrollFilter,
              isExpanded: true,
              isDense: true,
              icon: const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Icon(Icons.filter_list, size: 16),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              dropdownColor: Theme.of(context).cardColor,
              selectedItemBuilder: (BuildContext context) {
                return [
                  'All',
                  'Payable',
                  'With Absences',
                  'With Half Days',
                  'With Overtime',
                  'With Trips',
                ].map((String value) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value == 'All' ? 'Filter: All' : 'Filter: $value',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList();
              },
              items: const [
                DropdownMenuItem(value: 'All', child: Text('All records')),
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
                setState(() => _payrollFilter = value);
              },
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _pickPayDate,
          icon: const Icon(Icons.event, size: 16),
          label: Text('Pay Thursday: ${_dateLabel(_payDate)}'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            foregroundColor: isDark ? Colors.grey.shade300 : Colors.black87,
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        Chip(
          label: Text(
            '${_filteredPayrollRows.length} drivers',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          backgroundColor: isDark
              ? const Color(0xFF1E293B)
              : const Color(0xFFF1F5F9),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ],
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
