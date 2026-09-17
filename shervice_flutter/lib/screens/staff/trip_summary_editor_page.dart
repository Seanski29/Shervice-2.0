import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../constant.dart';

typedef SaveSummaryRow = Future<bool> Function(
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
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _drivers = [];

  bool get _isEditing => widget.initialRows != null;
  String get _dateText => _summaryDateKey(_date);

  String get _workingDay {
    const days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
    return days[_date.weekday - 1];
  }

  @override
  void initState() {
    super.initState();
    final initialRows = widget.initialRows;
    if (initialRows != null && initialRows.isNotEmpty) {
      final firstDate = DateTime.tryParse(
        (initialRows.first['schedule_date'] ?? initialRows.first['date'] ?? '').toString(),
      );
      if (firstDate != null) _date = firstDate;
      _rows.addAll(initialRows.map(_EditorSummaryRow.fromTrip));
    } else {
      _rows.add(_EditorSummaryRow.empty());
    }
    _loadDispatchOptions();
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
          .get(Uri.parse('$backendUrl/schedules/dispatch-options?date=$_dateText'))
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
    setState(() => _rows.addAll(List.generate(count, (_) => _EditorSummaryRow.empty())));
  }

  void _removeRow(int index) {
    if (_rows.length == 1) return;
    setState(() => _rows.removeAt(index).dispose());
  }

  Future<void> _selectVehicle(_EditorSummaryRow row) async {
    final selected = await _showSearchPicker(
      title: 'Select Vehicle',
      items: _vehicles,
      labelBuilder: (vehicle) {
        final plate = (vehicle['plate_number'] ?? 'Unnamed Vehicle').toString();
        final type = (vehicle['bus_type'] ?? '').toString();
        return type.isEmpty ? plate : '$plate - $type';
      },
    );
    if (selected == null) return;
    setState(() {
      row.vehicleId = '${selected['vehicle_id']}';
      row.vehicleLabel = (selected['plate_number'] ?? 'Selected Vehicle').toString();
      final type = (selected['bus_type'] ?? '').toString();
      if (type.isNotEmpty) row.busType.text = type;
    });
  }

  Future<void> _selectDriver(_EditorSummaryRow row) async {
    final selected = await _showSearchPicker(
      title: 'Select Driver',
      items: _drivers,
      labelBuilder: (driver) => (driver['full_name'] ?? 'Unnamed Driver').toString(),
    );
    if (selected == null) return;
    setState(() {
      row.driverId = '${selected['user_id']}';
      row.driverLabel = (selected['full_name'] ?? 'Selected Driver').toString();
    });
  }

  Future<void> _pickTime(TextEditingController controller) async {
    TimeOfDay initial = TimeOfDay.now();
    final text = controller.text.trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$', caseSensitive: false).firstMatch(text);
    if (match != null) {
      var hour = int.tryParse(match.group(1) ?? '') ?? initial.hour;
      final minute = int.tryParse(match.group(2) ?? '') ?? initial.minute;
      final meridiem = match.group(3)?.toUpperCase();
      if (meridiem == 'PM' && hour < 12) hour += 12;
      if (meridiem == 'AM' && hour == 12) hour = 0;
      initial = TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
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
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = items.where((item) {
              return labelBuilder(item).toLowerCase().contains(query.toLowerCase());
            }).toList();
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 420,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search...',
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
                            title: Text(labelBuilder(item)),
                            onTap: () => Navigator.pop(context, item),
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
    if (filledRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one trip row.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final existingRows = filledRows.where((row) => row.trip != null).toList();
      final newRows = filledRows.where((row) => row.trip == null).toList();

      for (final row in existingRows) {
        await widget.onSaveRow?.call(row.trip!, row.toPayload(_dateText, _workingDay));
      }

      if (newRows.isNotEmpty) {
        final response = await http
            .post(
              Uri.parse('$backendUrl/schedules/staff-summary'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'staff_id': widget.staffId,
                if (_isEditing && (widget.summaryId ?? '').isNotEmpty) 'summary_id': widget.summaryId,
                'schedule_date': _dateText,
                'rows': newRows.map((row) => row.toPayload(_dateText, _workingDay)).toList(),
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
      }

      if (!mounted) return;
      if (_isEditing) {
        Navigator.pop<bool>(context, true);
      } else {
        Navigator.pop<DateTime>(context, _date);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Trip Summary' : 'Add Trip Summary'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save Summary'),
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
                      decoration: _editorDecoration('Date', Icons.calendar_today, fillColor),
                      child: Text(_dateText),
                    ),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: InputDecorator(
                    decoration: _editorDecoration('Working Day', Icons.today, fillColor),
                    child: Text(_workingDay),
                  ),
                ),
                if (_isEditing && (widget.summaryId ?? '').isNotEmpty)
                  Chip(label: Text(widget.summaryId!))
                else
                  const Chip(label: Text('Summary ID auto-generated')),
                OutlinedButton.icon(
                  onPressed: () => _addRows(1),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Row'),
                ),
                OutlinedButton(onPressed: () => _addRows(10), child: const Text('Add 10')),
                OutlinedButton(onPressed: () => _addRows(20), child: const Text('Add 20')),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  border: Border.all(color: isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Scrollbar(
                  controller: _horizontalScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        ),
                        dataRowMinHeight: 62,
                        dataRowMaxHeight: 72,
                        columns: const [
                          DataColumn(label: Text('No.')),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Class')),
                          DataColumn(label: Text('Vehicle')),
                          DataColumn(label: Text('Cap')),
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
                              DataCell(Text('${index + 1}')),
                              DataCell(_editorTextField(row.busType, 180, fillColor)),
                              DataCell(_editorTextField(row.classification, 110, fillColor)),
                              DataCell(_selectorCell(row.vehicleLabel, 180, fillColor, () => _selectVehicle(row))),
                              DataCell(_editorTextField(row.capacity, 70, fillColor, keyboardType: TextInputType.number)),
                              DataCell(_editorTextField(row.ticketNo, 110, fillColor)),
                              DataCell(_selectorCell(row.driverLabel, 170, fillColor, () => _selectDriver(row))),
                              DataCell(_editorTextField(row.route, 190, fillColor)),
                              DataCell(_editorTextField(row.passengers, 70, fillColor, keyboardType: TextInputType.number)),
                              DataCell(_timeCell(row.departure, 96, fillColor)),
                              DataCell(_timeCell(row.arrival, 96, fillColor)),
                              DataCell(SizedBox(width: 70, child: Text(row.utilizationText))),
                              DataCell(_editorTextField(row.remarks, 180, fillColor)),
                              DataCell(
                                IconButton(
                                  tooltip: 'Remove row',
                                  onPressed: _rows.length == 1 ? null : () => _removeRow(index),
                                  icon: const Icon(Icons.delete_outline, size: 19),
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
          ],
        ),
      ),
    );
  }

  InputDecoration _editorDecoration(String label, IconData icon, Color fillColor) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      filled: true,
      fillColor: fillColor,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  Widget _editorTextField(
    TextEditingController controller,
    double width,
    Color fillColor, {
    TextInputType? keyboardType,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (_) => setState(() {}),
        decoration: _cellDecoration(fillColor),
      ),
    );
  }

  Widget _timeCell(TextEditingController controller, double width, Color fillColor) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: () => _pickTime(controller),
        decoration: _cellDecoration(fillColor).copyWith(
          suffixIcon: const Icon(Icons.schedule, size: 18),
        ),
      ),
    );
  }

  Widget _selectorCell(String label, double width, Color fillColor, VoidCallback onTap) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: _isLoadingOptions ? null : onTap,
        child: InputDecorator(
          decoration: _cellDecoration(fillColor).copyWith(
            suffixIcon: const Icon(Icons.search, size: 18),
          ),
          child: Text(
            label.trim().isEmpty ? 'Search...' : label,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  InputDecoration _cellDecoration(Color fillColor) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: fillColor,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    );
  }
}

class _EditorSummaryRow {
  final Map<String, dynamic>? trip;
  final busType = TextEditingController();
  final classification = TextEditingController();
  final capacity = TextEditingController();
  final ticketNo = TextEditingController();
  final route = TextEditingController();
  final passengers = TextEditingController();
  final departure = TextEditingController();
  final arrival = TextEditingController();
  final remarks = TextEditingController();
  String? vehicleId;
  String? driverId;
  String vehicleLabel = '';
  String driverLabel = '';

  _EditorSummaryRow.empty() : trip = null;

  _EditorSummaryRow.fromTrip(Map<String, dynamic> source) : trip = source {
    busType.text = (source['bus_type'] ?? '').toString();
    classification.text = (source['classification'] ?? '').toString();
    capacity.text = (source['seating_capacity'] ?? '').toString();
    ticketNo.text = (source['ticket_no'] ?? '').toString();
    route.text = (source['route_name'] ?? '').toString();
    passengers.text = (source['passenger_count'] ?? '').toString();
    departure.text = (source['departure_time'] ?? '').toString();
    arrival.text = (source['estimated_arrival_time'] ?? '').toString();
    remarks.text = (source['remarks'] ?? '').toString();
    vehicleId = source['vehicle_id']?.toString();
    driverId = source['user_id']?.toString();
    vehicleLabel = (source['plate_number'] ?? '').toString();
    driverLabel = (source['driver_name'] ?? '').toString();
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

  Map<String, dynamic> toPayload(String dateText, String workingDay) {
    final pax = double.tryParse(passengers.text.trim()) ?? 0;
    final cap = double.tryParse(capacity.text.trim()) ?? 0;
    return {
      'schedule_date': dateText,
      'working_day': workingDay,
      'bus_type': busType.text.trim(),
      'classification': classification.text.trim(),
      'vehicle_id': vehicleId,
      'seating_capacity': capacity.text.trim(),
      'ticket_no': ticketNo.text.trim(),
      'driver_uuid': driverId,
      'route_name': route.text.trim(),
      'passenger_count': passengers.text.trim(),
      'departure_time': departure.text.trim(),
      'estimated_arrival_time': arrival.text.trim(),
      'utilization_rate': cap <= 0 ? null : pax / cap,
      'remarks': remarks.text.trim(),
    };
  }

  void dispose() {
    busType.dispose();
    classification.dispose();
    capacity.dispose();
    ticketNo.dispose();
    route.dispose();
    passengers.dispose();
    departure.dispose();
    arrival.dispose();
    remarks.dispose();
  }
}
