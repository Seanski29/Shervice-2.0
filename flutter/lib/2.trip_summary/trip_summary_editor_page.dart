import 'dart:convert';
import 'package:flutter/material.dart';
import '../layouts/enterprise/enterprise_states.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../constant.dart';
import '../layouts/enterprise/enterprise_theme.dart';

typedef SaveSummaryRow =
    Future<bool> Function(
      Map<String, dynamic> trip,
      Map<String, dynamic> payload,
    );

String _summaryDateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class TripSummaryEditorPage extends StatefulWidget {
  final String staffId;
  final String? summaryId;
  final List<Map<String, dynamic>>? initialRows;
  final SaveSummaryRow? onSaveRow;

  const TripSummaryEditorPage({
    super.key,
    required this.staffId,
    this.summaryId,
    this.initialRows,
    this.onSaveRow,
  });

  @override
  State<TripSummaryEditorPage> createState() => _TripSummaryEditorPageState();
}

class _TripSummaryEditorPageState extends State<TripSummaryEditorPage> {
  final ScrollController _horizontalScrollController = ScrollController();
  final List<_EditorSummaryRow> _rows = [];
  DateTime _date = DateTime.now();
  bool _isLoadingOptions = false;
  bool _isSaving = false;
  double _tableZoom = 1;
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _routes = [];
  String? _selectedCompanyId;
  String _selectedCompanyLabel = '';
  String? _companyError;
  String? _rowsError;
  final Map<_EditorSummaryRow, String> _rowErrors = {};

  bool get _isEditing =>
      widget.summaryId != null && widget.summaryId!.isNotEmpty;
  String get _dateText => _summaryDateKey(_date);

  String get _workingDay {
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    return days[_date.weekday - 1];
  }

  bool _isInternalCompanyOption(Map<String, dynamic> company) {
    final name = (company['company_name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return name == 'gt lantin' || name == 'gt lantin internal';
  }

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();

    final initialRows = widget.initialRows;
    if (initialRows != null && initialRows.isNotEmpty) {
      if (_isEditing) {
        _selectedCompanyId = initialRows.first['company_id']?.toString();
        _selectedCompanyLabel = (initialRows.first['client_company'] ?? '')
            .toString();

        final firstDate = DateTime.tryParse(
          (initialRows.first['schedule_date'] ??
                  initialRows.first['date'] ??
                  '')
              .toString(),
        );
        if (firstDate != null) _date = firstDate;
      } else {
        _selectedCompanyId = null;
        _selectedCompanyLabel = '';
      }

      _rows.addAll(initialRows.map(_EditorSummaryRow.fromTrip));
    } else {
      _rows.add(_EditorSummaryRow.empty());
    }
    _loadDispatchOptions();
    _loadCompanies();
    _loadRoutes();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDispatchOptions() async {
    setState(() => _isLoadingOptions = true);
    try {
      final response = await http
          .get(
            Uri.parse(
              '$backendUrl/schedules/dispatch-options?date=$_dateText&summary=true',
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _vehicles = (decoded['vehicles'] as List? ?? [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          _drivers = (decoded['drivers'] as List? ?? [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        });
      }
    } catch (error) {
      debugPrint('Dispatch options fetch failed: $error');
    } finally {
      if (mounted) setState(() => _isLoadingOptions = false);
    }
  }

  Future<void> _loadCompanies() async {
    try {
      final response = await http
          .get(Uri.parse('$backendUrl/companies'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        _companies = (decoded['data'] as List? ?? [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .where((company) => !_isInternalCompanyOption(company))
            .toList();
        if (_selectedCompanyLabel.trim().isEmpty &&
            _selectedCompanyId != null) {
          for (final company in _companies) {
            if (company['company_id']?.toString() == _selectedCompanyId) {
              _selectedCompanyLabel = (company['company_name'] ?? '')
                  .toString();
              break;
            }
          }
        } else if (_selectedCompanyId == null &&
            _selectedCompanyLabel.trim().isNotEmpty) {
          for (final company in _companies) {
            if ((company['company_name'] ?? '').toString().toLowerCase() ==
                _selectedCompanyLabel.trim().toLowerCase()) {
              _selectedCompanyId = company['company_id']?.toString();
              break;
            }
          }
        }
      });
    } catch (error) {
      debugPrint('Company options fetch failed: $error');
    }
  }

  Future<void> _loadRoutes() async {
    try {
      final response = await http
          .get(Uri.parse('$backendUrl/routes'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        _routes = (decoded['data'] as List? ?? [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      });
    } catch (error) {
      debugPrint('Route options fetch failed: $error');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _date = picked);
    await _loadDispatchOptions();
  }

  void _addRows(int count) {
    setState(
      () =>
          _rows.addAll(List.generate(count, (_) => _EditorSummaryRow.empty())),
    );
    EnterpriseToasts.success(
      context,
      '$count ${count == 1 ? 'row' : 'rows'} added.',
    );
  }

  void _removeRow(int index) {
    if (_rows.length == 1) return;
    setState(() => _rows.removeAt(index).dispose());
    EnterpriseToasts.success(context, 'Draft row removed.');
  }

  String _vehicleOptionLabel(Map<String, dynamic> vehicle) {
    final plate = (vehicle['plate_number'] ?? 'Unnamed Vehicle').toString();
    final type = (vehicle['vehicle_type'] ?? vehicle['bus_type'] ?? '')
        .toString()
        .trim();
    return type.isEmpty ? plate : '$plate - $type';
  }

  String _driverOptionLabel(Map<String, dynamic> driver) {
    final name = (driver['full_name'] ?? 'Unnamed Driver').toString();
    final id = driver['driver_id']?.toString();
    return id == null || id.trim().isEmpty ? name : '$name #$id';
  }

  bool _matchesOptionLabel(String option, String query) {
    return option.toLowerCase().contains(query.trim().toLowerCase());
  }

  void _resolveTypedVehicle(_EditorSummaryRow row) {
    if (row.vehicleId != null && row.vehicleId!.trim().isNotEmpty) return;
    final typed = row.vehicle.text.trim().toLowerCase();
    if (typed.isEmpty) return;
    for (final vehicle in _vehicles) {
      final plate = (vehicle['plate_number'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final label = _vehicleOptionLabel(vehicle).trim().toLowerCase();
      final id = (vehicle['vehicle_id'] ?? '').toString().trim().toLowerCase();
      if (typed == plate || typed == label || typed == id) {
        row.vehicleId = vehicle['vehicle_id']?.toString();
        return;
      }
    }
  }

  void _resolveTypedDriver(_EditorSummaryRow row) {
    if (row.driverId != null && row.driverId!.trim().isNotEmpty) return;
    final typed = row.driver.text.trim().toLowerCase();
    if (typed.isEmpty) return;
    for (final driver in _drivers) {
      final name = (driver['full_name'] ?? '').toString().trim().toLowerCase();
      final label = _driverOptionLabel(driver).trim().toLowerCase();
      final id = (driver['driver_id'] ?? '').toString().trim().toLowerCase();
      if (typed == name || typed == label || typed == id || typed == '#$id') {
        row.driverId = driver['driver_id']?.toString();
        return;
      }
    }
  }

  void _selectVehicleOption(
    _EditorSummaryRow row,
    Map<String, dynamic> selected,
  ) {
    setState(() {
      row.vehicleId = selected['vehicle_id']?.toString();
      row.vehicle.text = _vehicleOptionLabel(selected);
      row.vehicle.selection = TextSelection.fromPosition(
        TextPosition(offset: row.vehicle.text.length),
      );

      final rawType = (selected['bus_type'] ?? '').toString();
      final type = (selected['vehicle_type'] ?? '').toString().trim();
      if (type.isNotEmpty) row.busType.text = type;

      final cap = (selected['seating_capacity'] ?? '').toString();
      if (cap.isNotEmpty && cap != 'null') {
        row.capacity.text = cap;
      } else {
        final parsedCapacity = _capacityFromVehicleType(rawType);
        if (parsedCapacity != null) {
          row.capacity.text = parsedCapacity.toString();
        }
      }
    });
  }

  int? _capacityFromVehicleType(String rawType) {
    final match = RegExp(
      r'^\s*(\d+)\s*(seats?|seater)\b',
      caseSensitive: false,
    ).firstMatch(rawType);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  void _selectDriverOption(
    _EditorSummaryRow row,
    Map<String, dynamic> selected,
  ) {
    setState(() {
      row.driverId = selected['driver_id']?.toString();
      row.driver.text = _driverOptionLabel(selected);
      row.driver.selection = TextSelection.fromPosition(
        TextPosition(offset: row.driver.text.length),
      );
    });
  }

  Future<void> _selectCompany() async {
    final selected = await _showSearchPicker(
      title: 'Select Company',
      items: _companies,
      labelBuilder: (company) =>
          (company['company_name'] ?? 'Unnamed Company').toString(),
    );
    if (selected == null) return;
    setState(() {
      _selectedCompanyId = selected['company_id']?.toString();
      _selectedCompanyLabel = (selected['company_name'] ?? 'Selected Company')
          .toString();
      _companyError = null;
    });
  }

  Future<void> _pickTime(TextEditingController controller) async {
    TimeOfDay initial = TimeOfDay.now();
    final text = controller.text.trim();
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      var hour = int.tryParse(match.group(1) ?? '') ?? initial.hour;
      final minute = int.tryParse(match.group(2) ?? '') ?? initial.minute;
      final meridiem = match.group(3)?.toUpperCase();
      if (meridiem == 'PM' && hour < 12) hour += 12;
      if (meridiem == 'AM' && hour == 12) hour = 0;
      initial = TimeOfDay(
        hour: hour.clamp(0, 23).toInt(),
        minute: minute.clamp(0, 59).toInt(),
      );
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return;
    if (!mounted) return;
    controller.text = picked.format(context);
    setState(() {});
  }

  Future<Map<String, dynamic>?> _showSearchPicker({
    required String title,
    required List<Map<String, dynamic>> items,
    required String Function(Map<String, dynamic>) labelBuilder,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        var query = '';
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
        final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = items.where((item) {
              return labelBuilder(
                item,
              ).toLowerCase().contains(query.toLowerCase());
            }).toList();
            return AlertDialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              title: Text(
                title,
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 420,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          Icons.search,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                        hintText: 'Search...',
                        hintStyle: TextStyle(
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade400,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                          ),
                        ),
                      ),
                      onChanged: (value) => setDialogState(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return ListTile(
                            title: Text(
                              labelBuilder(item),
                              style: TextStyle(color: textColor),
                            ),
                            onTap: () => Navigator.pop(context, item),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            hoverColor: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.05),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _save() async {
    final filledRows = _rows.where((row) => row.hasContent).toList();
    setState(() {
      _companyError = null;
      _rowsError = null;
      _rowErrors.clear();
    });
    if (filledRows.isEmpty) {
      setState(() => _rowsError = 'Add at least one completed trip row.');
      return;
    }
    if (_selectedCompanyId == null || _selectedCompanyId!.trim().isEmpty) {
      setState(() => _companyError = 'Choose a company for this summary.');
      return;
    }

    final validationErrors = <_EditorSummaryRow, String>{};
    for (final row in filledRows) {
      _resolveTypedVehicle(row);
      _resolveTypedDriver(row);
      final passengers = int.tryParse(row.passengers.text.trim()) ?? 0;
      final capacity = int.tryParse(row.capacity.text.trim()) ?? 0;
      if (capacity > 0 && passengers > capacity) {
        validationErrors[row] = 'Exceeds capacity.';
      } else if (row.vehicle.text.trim().isNotEmpty &&
          (row.vehicleId == null || row.vehicleId!.trim().isEmpty)) {
        validationErrors[row] = 'Select vehicle.';
      } else if (row.driver.text.trim().isNotEmpty &&
          (row.driverId == null || row.driverId!.trim().isEmpty)) {
        validationErrors[row] = 'Select driver.';
      }
    }
    if (validationErrors.isNotEmpty) {
      setState(() => _rowErrors.addAll(validationErrors));
      return;
    }

    setState(() => _isSaving = true);
    try {
      for (final row in filledRows) {
        _resolveTypedVehicle(row);
        _resolveTypedDriver(row);
      }

      final endpoint = _isEditing
          ? '$backendUrl/schedules/staff-summary/save'
          : '$backendUrl/schedules/staff-summary';
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'staff_id': widget.staffId,
              'company_id': _selectedCompanyId,
              if (_isEditing && (widget.summaryId ?? '').isNotEmpty)
                'summary_id': widget.summaryId,
              'schedule_date': _dateText,
              'rows': filledRows
                  .map(
                    (row) => {
                      ...row.toPayload(
                        _dateText,
                        _workingDay,
                        companyId: _selectedCompanyId,
                      ),
                      if (row.trip != null) 'trip_id': row.trip!['trip_id'],
                    },
                  )
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200 && response.statusCode != 201) {
        String message = 'Unable to save trip summary.';
        try {
          final decoded = jsonDecode(response.body);
          message = decoded['message']?.toString() ?? message;
        } catch (_) {}
        throw Exception(message);
      }

      if (!mounted) return;
      EnterpriseToasts.success(
        context,
        _isEditing ? 'Trip summary updated.' : 'Trip summary created.',
      );
      if (_isEditing) {
        Navigator.pop<bool>(context, true);
      } else {
        Navigator.pop<DateTime>(context, _date);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: isDark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textColor,
        elevation: 1,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trip Summary',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              _isEditing
                  ? 'Editing ${widget.summaryId} | $_dateText'
                  : 'New summary | $_dateText | Owner: Staff',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: EnterpriseColors.generativeAction,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: EnterpriseLoadingIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save, size: 18),
              label: Text(
                _isSaving ? 'Saving...' : 'Save Summary',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: _editorDecoration(
                        'Date',
                        Icons.calendar_today,
                        fillColor,
                        isDark,
                      ),
                      child: Text(
                        _dateText,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: InputDecorator(
                    decoration: _editorDecoration(
                      'Working Day',
                      Icons.today,
                      fillColor,
                      isDark,
                    ),
                    child: Text(
                      _workingDay,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: InkWell(
                    onTap: _companies.isEmpty ? null : _selectCompany,
                    child: InputDecorator(
                      decoration:
                          _editorDecoration(
                            'Company',
                            Icons.business,
                            fillColor,
                            isDark,
                          ).copyWith(
                            helperText: 'Required for billing attribution.',
                            errorText: _companyError,
                            suffixIcon: Icon(
                              Icons.search,
                              size: 18,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                      child: Text(
                        _selectedCompanyLabel.trim().isEmpty
                            ? 'Choose company'
                            : _selectedCompanyLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _selectedCompanyLabel.trim().isEmpty
                              ? (isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500)
                              : textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isEditing && (widget.summaryId ?? '').isNotEmpty)
                  Chip(
                    label: Text(
                      widget.summaryId!,
                      style: TextStyle(
                        color: isDark
                            ? Colors.blue.shade200
                            : const Color(0xFF1D4ED8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: isDark
                        ? Colors.blue.withValues(alpha: 0.1)
                        : const Color(0xFFDBEAFE),
                    side: BorderSide.none,
                  )
                else
                  Chip(
                    label: Text(
                      'Summary ID auto-generated',
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    backgroundColor: isDark
                        ? const Color(0xFF0F172A)
                        : Colors.grey.shade200,
                    side: BorderSide.none,
                  ),
                OutlinedButton.icon(
                  onPressed: () => _addRows(1),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Row'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.blue.shade300
                        : const Color(0xFF2563EB),
                    side: BorderSide(
                      color: isDark
                          ? Colors.blue.shade800
                          : Colors.blue.shade200,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _addRows(10),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey.shade300
                        : Colors.grey.shade700,
                    side: BorderSide(
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text('Add 10'),
                ),
                OutlinedButton(
                  onPressed: () => _addRows(20),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey.shade300
                        : Colors.grey.shade700,
                    side: BorderSide(
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text('Add 20'),
                ),
                SegmentedButton<double>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 0.85,
                      label: Text('-'),
                      tooltip: 'Zoom out',
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('100%'),
                      tooltip: 'Reset zoom',
                    ),
                    ButtonSegment(
                      value: 1.15,
                      label: Text('+'),
                      tooltip: 'Zoom in',
                    ),
                  ],
                  selected: {_tableZoom},
                  onSelectionChanged: (selection) {
                    setState(() => _tableZoom = selection.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_rowsError != null) ...[
              Text(
                _rowsError!,
                style: const TextStyle(
                  color: Color(0xFFD92D20),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: fillColor,
                  border: Border.all(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Scrollbar(
                  controller: _horizontalScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: 2500 * _tableZoom,
                        height: (56 + (_rows.length * 92)) * _tableZoom,
                        child: Transform.scale(
                          scale: _tableZoom,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: 2500,
                            height: 56 + (_rows.length * 92),
                            child: DataTable(
                              headingRowColor: WidgetStatePropertyAll(
                                isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF8FAFC),
                              ),
                              headingTextStyle: TextStyle(
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                              dataRowMinHeight: 62,
                              dataRowMaxHeight: 92,
                              columns: const [
                                DataColumn(label: Text('No.')),
                                DataColumn(label: Text('Vehicle')),
                                DataColumn(label: Text('Vehicle Type')),
                                DataColumn(label: Text('Class')),
                                DataColumn(label: Text('Capacity')),
                                DataColumn(label: Text('Ticket')),
                                DataColumn(label: Text('Driver')),
                                DataColumn(label: Text('Route')),
                                DataColumn(label: Text('Pax')),
                                DataColumn(label: Text('Depart')),
                                DataColumn(label: Text('Arrival')),
                                DataColumn(label: Text('Util')),
                                DataColumn(label: Text('Remarks')),
                                DataColumn(label: Text('')),
                              ],
                              rows: List.generate(_rows.length, (index) {
                                final row = _rows[index];
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      _EditorRowNumberCell(
                                        number: index + 1,
                                        canDelete: _rows.length > 1,
                                        onDelete: () => _removeRow(index),
                                      ),
                                    ),
                                    DataCell(
                                      _vehicleAutocompleteCell(
                                        row,
                                        180,
                                        fillColor,
                                        isDark,
                                      ),
                                    ),
                                    DataCell(
                                      _editorTextField(
                                        row.busType,
                                        120,
                                        fillColor,
                                        isDark,
                                      ),
                                    ),
                                    DataCell(
                                      _editorTextField(
                                        row.classification,
                                        110,
                                        fillColor,
                                        isDark,
                                      ),
                                    ),
                                    DataCell(
                                      _editorTextField(
                                        row.capacity,
                                        70,
                                        fillColor,
                                        isDark,
                                        keyboardType: TextInputType.number,
                                        triggersUpdate: true,
                                      ),
                                    ),
                                    DataCell(
                                      _editorTextField(
                                        row.ticketNo,
                                        110,
                                        fillColor,
                                        isDark,
                                      ),
                                    ),
                                    DataCell(
                                      _driverAutocompleteCell(
                                        row,
                                        170,
                                        fillColor,
                                        isDark,
                                      ),
                                    ),
                                    DataCell(
                                      _routeAutocompleteCell(
                                        row,
                                        190,
                                        fillColor,
                                        isDark,
                                      ),
                                    ),
                                    DataCell(
                                      _editorTextField(
                                        row.passengers,
                                        70,
                                        fillColor,
                                        isDark,
                                        keyboardType: TextInputType.number,
                                        triggersUpdate: true,
                                        row: row,
                                        isPax: true,
                                        errorText: _rowErrors[row],
                                      ),
                                    ),
                                    DataCell(
                                      _timeCell(
                                        row.departure,
                                        96,
                                        fillColor,
                                        isDark,
                                      ),
                                    ),
                                    DataCell(
                                      _timeCell(
                                        row.arrival,
                                        96,
                                        fillColor,
                                        isDark,
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: 70,
                                        child: Text(
                                          row.utilizationText,
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      _editorTextField(
                                        row.remarks,
                                        180,
                                        fillColor,
                                        isDark,
                                      ),
                                    ),
                                    DataCell(
                                      IconButton(
                                        tooltip: 'Remove row',
                                        onPressed: _rows.length == 1
                                            ? null
                                            : () => _removeRow(index),
                                        icon: Icon(
                                          Icons.delete_outline,
                                          size: 19,
                                          color: _rows.length == 1
                                              ? Colors.grey.shade400
                                              : Colors.red.shade400,
                                        ),
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
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _editorDecoration(
    String label,
    IconData icon,
    Color fillColor,
    bool isDark,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
      ),
      prefixIcon: Icon(
        icon,
        size: 18,
        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
      ),
      filled: true,
      fillColor: fillColor,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  Widget _editorTextField(
    TextEditingController controller,
    double width,
    Color fillColor,
    bool isDark, {
    TextInputType? keyboardType,
    bool triggersUpdate = false,
    _EditorSummaryRow? row,
    bool isPax = false,
    String? errorText,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        onChanged: (val) {
          if (isPax && row != null) {
            final pax = int.tryParse(val) ?? 0;
            final cap = int.tryParse(row.capacity.text) ?? 0;
            if (pax > cap && cap > 0) {
              controller.text = cap.toString();
              controller.selection = TextSelection.fromPosition(
                TextPosition(offset: controller.text.length),
              );
            }
          }
          if (triggersUpdate || (row != null && _rowErrors.containsKey(row))) {
            setState(() {
              if (row != null) _rowErrors.remove(row);
            });
          }
        },
        decoration: _cellDecoration(
          fillColor,
          isDark,
        ).copyWith(errorText: errorText),
      ),
    );
  }

  Widget _optionTile(String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      dense: true,
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.trim().isEmpty
          ? null
          : Text(subtitle, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }

  Widget _autocompletePopup<T>(
    Iterable<T> options,
    Widget Function(T option) itemBuilder,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 300),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: options.map(itemBuilder).toList(),
          ),
        ),
      ),
    );
  }

  Widget _vehicleAutocompleteCell(
    _EditorSummaryRow row,
    double width,
    Color fillColor,
    bool isDark,
  ) {
    List<Map<String, dynamic>> matchingVehicles(String value) {
      final query = value.trim();
      if (query.isEmpty) return _vehicles.take(8).toList();
      return _vehicles
          .where((vehicle) {
            final label = _vehicleOptionLabel(vehicle);
            final id = vehicle['vehicle_id']?.toString() ?? '';
            return _matchesOptionLabel('$label $id', query);
          })
          .take(8)
          .toList();
    }

    return SizedBox(
      width: width,
      child: RawAutocomplete<Map<String, dynamic>>(
        textEditingController: row.vehicle,
        focusNode: row.vehicleFocus,
        optionsBuilder: (value) => matchingVehicles(value.text),
        displayStringForOption: _vehicleOptionLabel,
        onSelected: (vehicle) => _selectVehicleOption(row, vehicle),
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.tab) {
                final options = matchingVehicles(controller.text);
                if (options.isNotEmpty) {
                  _selectVehicleOption(row, options.first);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              enabled: !_isLoadingOptions,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              onChanged: (_) => row.vehicleId = null,
              decoration: _cellDecoration(fillColor, isDark).copyWith(
                suffixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return _autocompletePopup<Map<String, dynamic>>(
            options,
            (vehicle) => _optionTile(
              (vehicle['plate_number'] ?? 'Unnamed Vehicle').toString(),
              [
                if ((vehicle['vehicle_type'] ?? vehicle['bus_type'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty)
                  (vehicle['vehicle_type'] ?? vehicle['bus_type']).toString(),
                if (vehicle['vehicle_id'] != null)
                  'ID ${vehicle['vehicle_id']}',
              ].join(' - '),
              () => onSelected(vehicle),
            ),
          );
        },
      ),
    );
  }

  Widget _driverAutocompleteCell(
    _EditorSummaryRow row,
    double width,
    Color fillColor,
    bool isDark,
  ) {
    List<Map<String, dynamic>> matchingDrivers(String value) {
      final query = value.trim();
      if (query.isEmpty) return _drivers.take(8).toList();
      return _drivers
          .where((driver) {
            final label = _driverOptionLabel(driver);
            final id = driver['driver_id']?.toString() ?? '';
            return _matchesOptionLabel('$label $id', query);
          })
          .take(8)
          .toList();
    }

    return SizedBox(
      width: width,
      child: RawAutocomplete<Map<String, dynamic>>(
        textEditingController: row.driver,
        focusNode: row.driverFocus,
        optionsBuilder: (value) => matchingDrivers(value.text),
        displayStringForOption: _driverOptionLabel,
        onSelected: (driver) => _selectDriverOption(row, driver),
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.tab) {
                final options = matchingDrivers(controller.text);
                if (options.isNotEmpty) {
                  _selectDriverOption(row, options.first);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              enabled: !_isLoadingOptions,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              onChanged: (_) => row.driverId = null,
              decoration: _cellDecoration(fillColor, isDark).copyWith(
                suffixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return _autocompletePopup<Map<String, dynamic>>(
            options,
            (driver) => _optionTile(
              (driver['full_name'] ?? 'Unnamed Driver').toString(),
              driver['driver_id'] == null ? '' : 'ID ${driver['driver_id']}',
              () => onSelected(driver),
            ),
          );
        },
      ),
    );
  }

  Widget _routeAutocompleteCell(
    _EditorSummaryRow row,
    double width,
    Color fillColor,
    bool isDark,
  ) {
    List<String> matchingRoutes(String value) {
      final query = value.trim().toLowerCase();
      final names = _routes
          .map((route) => (route['route_name'] ?? '').toString())
          .where((name) => name.trim().isNotEmpty)
          .toList();
      if (query.isEmpty) return names.take(8).toList();
      return names
          .where((name) => name.toLowerCase().contains(query))
          .take(8)
          .toList();
    }

    void selectRoute(String name) {
      row.route.text = name;
      row.routeId = null;
      for (final route in _routes) {
        if ((route['route_name'] ?? '').toString().toLowerCase() ==
            name.toLowerCase()) {
          row.routeId = route['route_id']?.toString();
          break;
        }
      }
      row.route.selection = TextSelection.fromPosition(
        TextPosition(offset: row.route.text.length),
      );
    }

    return SizedBox(
      width: width,
      child: RawAutocomplete<String>(
        textEditingController: row.route,
        focusNode: row.routeFocus,
        optionsBuilder: (value) => matchingRoutes(value.text),
        onSelected: selectRoute,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.tab) {
                final options = matchingRoutes(controller.text);
                if (options.isNotEmpty) {
                  selectRoute(options.first);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              onChanged: (_) => row.routeId = null,
              decoration: _cellDecoration(fillColor, isDark),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 6,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 220,
                  maxWidth: 260,
                ),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: options.map((option) {
                    return ListTile(
                      dense: true,
                      title: Text(option),
                      onTap: () => onSelected(option),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _timeCell(
    TextEditingController controller,
    double width,
    Color fillColor,
    bool isDark,
  ) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        readOnly: true,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        onTap: () => _pickTime(controller),
        decoration: _cellDecoration(fillColor, isDark).copyWith(
          suffixIcon: Icon(
            Icons.schedule,
            size: 18,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _selectorCell(
    String label,
    double width,
    Color fillColor,
    bool isDark,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: _isLoadingOptions ? null : onTap,
        child: InputDecorator(
          decoration: _cellDecoration(fillColor, isDark).copyWith(
            suffixIcon: Icon(
              Icons.search,
              size: 18,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          child: Text(
            label.trim().isEmpty ? 'Search...' : label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  InputDecoration _cellDecoration(Color fillColor, bool isDark) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: fillColor,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    );
  }
}

class _EditorRowNumberCell extends StatefulWidget {
  const _EditorRowNumberCell({
    required this.number,
    required this.canDelete,
    required this.onDelete,
  });

  final int number;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  State<_EditorRowNumberCell> createState() => _EditorRowNumberCellState();
}

class _EditorRowNumberCellState extends State<_EditorRowNumberCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: 34,
        child: _hovered && widget.canDelete
            ? IconButton(
                onPressed: widget.onDelete,
                tooltip: 'Delete row ${widget.number}',
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Color(0xFFD92D20),
                ),
              )
            : Center(
                child: Text(
                  '${widget.number}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
      ),
    );
  }
}

class _EditorSummaryRow {
  final Map<String, dynamic>? trip;
  final vehicle = TextEditingController();
  final vehicleFocus = FocusNode();
  final busType = TextEditingController();
  final classification = TextEditingController();
  final capacity = TextEditingController();
  final ticketNo = TextEditingController();
  final driver = TextEditingController();
  final driverFocus = FocusNode();
  final route = TextEditingController();
  final routeFocus = FocusNode();
  final passengers = TextEditingController();
  final departure = TextEditingController();
  final arrival = TextEditingController();
  final remarks = TextEditingController();
  String? vehicleId;
  String? driverId;
  String? routeId;

  _EditorSummaryRow.empty() : trip = null;

  _EditorSummaryRow.fromTrip(Map<String, dynamic> source) : trip = source {
    busType.text = (source['vehicle_type'] ?? source['bus_type'] ?? '')
        .toString();
    classification.text = (source['classification'] ?? '').toString();
    capacity.text = (source['seating_capacity'] ?? '').toString();
    ticketNo.text = (source['ticket_no'] ?? '').toString();
    route.text = (source['route_name'] ?? '').toString();
    routeId = source['route_id']?.toString();
    passengers.text = (source['passenger_count'] ?? '').toString();
    departure.text = (source['departure_time'] ?? '').toString();
    arrival.text = (source['estimated_arrival_time'] ?? '').toString();
    remarks.text = (source['remarks'] ?? '').toString();
    vehicleId = source['vehicle_id']?.toString();
    driverId = source['driver_id']?.toString();
    vehicle.text = (source['plate_number'] ?? '').toString();
    driver.text = [
      (source['driver_name'] ?? '').toString(),
      if (source['driver_id'] != null) '#${source['driver_id']}',
    ].where((part) => part.trim().isNotEmpty).join(' ');
  }

  bool get hasContent {
    return [
      busType.text,
      classification.text,
      capacity.text,
      ticketNo.text,
      route.text,
      passengers.text,
      departure.text,
      arrival.text,
      remarks.text,
      vehicle.text,
      driver.text,
      vehicleId ?? '',
      driverId ?? '',
    ].any((value) => value.trim().isNotEmpty);
  }

  String get utilizationText {
    final pax = double.tryParse(passengers.text.trim()) ?? 0;
    final cap = double.tryParse(capacity.text.trim()) ?? 0;
    if (cap <= 0) return '-';
    return '${((pax / cap) * 100).round()}%';
  }

  Map<String, dynamic> toPayload(
    String dateText,
    String workingDay, {
    String? companyId,
  }) {
    final pax = double.tryParse(passengers.text.trim()) ?? 0;
    final cap = double.tryParse(capacity.text.trim()) ?? 0;

    final safeDriverId =
        (driverId == null || driverId == 'null' || driverId!.trim().isEmpty)
        ? null
        : int.tryParse(driverId!);

    final safeVehicleId =
        (vehicleId == null || vehicleId == 'null' || vehicleId!.trim().isEmpty)
        ? null
        : int.tryParse(vehicleId!);

    return {
      'schedule_date': dateText,
      'working_day': workingDay,
      'company_id': companyId == null ? null : int.tryParse(companyId),
      'vehicle_type': busType.text.trim(),
      'classification': classification.text.trim(),
      'vehicle_id': safeVehicleId,
      'seating_capacity': capacity.text.trim(),
      'ticket_no': ticketNo.text.trim(),
      'driver_id': safeDriverId,
      'route_id': routeId == null ? null : int.tryParse(routeId!),
      'route_name': route.text.trim(),
      'passenger_count': passengers.text.trim(),
      'departure_time': departure.text.trim(),
      'estimated_arrival_time': arrival.text.trim(),
      'utilization_rate': cap <= 0 ? null : pax / cap,
      'remarks': remarks.text.trim(),
    };
  }

  void dispose() {
    vehicle.dispose();
    vehicleFocus.dispose();
    busType.dispose();
    classification.dispose();
    capacity.dispose();
    ticketNo.dispose();
    driver.dispose();
    driverFocus.dispose();
    route.dispose();
    routeFocus.dispose();
    passengers.dispose();
    departure.dispose();
    arrival.dispose();
    remarks.dispose();
  }
}
