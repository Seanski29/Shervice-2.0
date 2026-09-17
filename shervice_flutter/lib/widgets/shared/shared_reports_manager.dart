import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart' as excel;

import '../../constant.dart';
import '../../utils/file_download.dart';
import 'universal_pagination.dart';

class SharedReportsManager extends StatefulWidget {
  final String userRole;

  const SharedReportsManager({super.key, required this.userRole});

  @override
  State<SharedReportsManager> createState() => _SharedReportsManagerState();
}

class _SharedReportsManagerState extends State<SharedReportsManager> {
  final List<String> _reportTypes = ['Trips', 'Maintenance', 'Timecard'];

  String _selectedReportType = 'Timecard';
  bool _isImporting = false;
  bool _isLoadingSystemData = false;
  String _sourceFileName = 'No file selected';

  // Custom Pagination, Sorting & Search State
  int _rowsPerPage = 10;
  int _currentPage = 0;
  bool _sortDateAscending = false; // Default: newest first
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Main UI Date Filter State
  String _selectedRange = 'All Time';
  DateTimeRange? _customDateRange;

  final List<String> _timecardColumns = [
    'employee',
    'pay_period',
    'day',
    'date',
    'in_time',
    'out_time',
    'work_time',
    'daily_total',
    'note',
  ];

  final Map<String, List<String>> _reportColumns = const {
    'Trips': [
      'client_name',
      'company_id',
      'departure_time',
      'estimated_arrival_time',
      'actual_start_time',
      'actual_end_time',
      'trip_id',
      'route_name',
      'schedule_date',
      'trip_status',
      'driver_name',
      'plate_number',
    ],
    'Maintenance': [
      'vehicle_id',
      'plate_number',
      'target_date',
      'incident_date',
      'repair_date',
      'description',
      'is_resolved',
      'status',
    ],
  };

  List<String> _columns = [];
  List<Map<String, String>> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadCurrentReportData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _canImportCurrentReport => _selectedReportType == 'Timecard';

  // ===========================================================================
  // PIPELINE: FILTER, SEARCH & SORT
  // ===========================================================================

  List<Map<String, String>> get _processedRows {
    List<Map<String, String>> result = List.from(_rows);

    // 1. Date Filter (Applied from the main UI dropdown)
    DateTime now = DateTime.now();
    DateTime? startDate;
    DateTime? endDate;

    if (_selectedRange == 'Today') {
      startDate = DateTime(now.year, now.month, now.day);
      endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_selectedRange == 'This Week') {
      startDate = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      endDate = startDate.add(
        const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
      );
    } else if (_selectedRange == 'This Month') {
      startDate = DateTime(now.year, now.month, 1);
      endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    } else if (_selectedRange == 'This Year') {
      startDate = DateTime(now.year, 1, 1);
      endDate = DateTime(now.year, 12, 31, 23, 59, 59);
    } else if (_selectedRange == 'Custom Range' && _customDateRange != null) {
      startDate = _customDateRange!.start;
      endDate = DateTime(
        _customDateRange!.end.year,
        _customDateRange!.end.month,
        _customDateRange!.end.day,
        23,
        59,
        59,
      );
    }

    if (startDate != null && endDate != null) {
      result = result.where((row) {
        final dateStr = _extractDateFromRow(row);
        if (dateStr == 'NaN' || dateStr.isEmpty) return false;
        try {
          final parsed = DateTime.parse(dateStr.split('T')[0]);
          return parsed.isAfter(startDate!.subtract(const Duration(days: 1))) &&
              parsed.isBefore(endDate!.add(const Duration(days: 1)));
        } catch (_) {
          return false;
        }
      }).toList();
    }

    // 2. Search Filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((row) {
        return row.values.any(
          (val) => _formatDisplayValue('', val).toLowerCase().contains(query),
        );
      }).toList();
    }

    // 3. Sort By Explicit Target Date
    result.sort((a, b) {
      DateTime dateA =
          _parseFlexibleDate(_extractDateFromRow(a)) ?? DateTime(1970);
      DateTime dateB =
          _parseFlexibleDate(_extractDateFromRow(b)) ?? DateTime(1970);
      return _sortDateAscending
          ? dateA.compareTo(dateB)
          : dateB.compareTo(dateA);
    });

    return result;
  }

  DateTime? _parseFlexibleDate(String dateStr) {
    if (dateStr == 'NaN' || dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr.split('T')[0]);
    } catch (_) {
      return null;
    }
  }

  String _extractDateFromRow(Map<String, String> row) {
    if (_selectedReportType == 'Timecard') return row['date'] ?? '';
    if (_selectedReportType == 'Maintenance') return row['incident_date'] ?? '';
    if (_selectedReportType == 'Trips')
      return row['schedule_date'] ?? row['schedule'] ?? '';
    return '';
  }

  // ===========================================================================
  // DATA LOADING
  // ===========================================================================

  Future<void> _loadCurrentReportData() async {
    setState(() {
      _isLoadingSystemData = true;
      _currentPage = 0;
      _selectedRange = 'All Time';
      _customDateRange = null;
    });

    try {
      http.Response response;

      if (_selectedReportType == 'Trips') {
        response = await http.get(Uri.parse('$backendUrl/trips'));
      } else if (_selectedReportType == 'Maintenance') {
        response = await http.get(
          Uri.parse('$backendUrl/vehicles/maintenance'),
        );
      } else {
        response = await http.get(
          Uri.parse('$backendUrl/${widget.userRole}/timecards'),
        );
        if (response.statusCode != 200) {
          response = await http.get(Uri.parse('$backendUrl/admin/timecards'));
        }
      }

      if (response.statusCode != 200) {
        _setEmptyState();
        return;
      }

      final decoded = jsonDecode(response.body);
      final rawList = _selectedReportType == 'Trips'
          ? ((decoded is Map ? decoded['trips'] : decoded) ?? [])
          : _selectedReportType == 'Maintenance'
          ? ((decoded is Map ? decoded['data'] : decoded) ?? [])
          : ((decoded is Map
                    ? decoded['data'] ?? decoded['timecards']
                    : decoded) ??
                []);

      final normalized = _normalizeSystemRows(rawList);

      final columns = _selectedReportType == 'Timecard'
          ? _timecardColumns
          : (_reportColumns[_selectedReportType] ??
                (normalized.isNotEmpty
                    ? _buildColumns(normalized.first.keys.toList())
                    : const ['status']));

      if (!mounted) return;
      setState(() {
        _sourceFileName = 'System $_selectedReportType records';
        _columns = columns;
        _rows = normalized;
      });
    } catch (error) {
      _setEmptyState();
    } finally {
      if (mounted) setState(() => _isLoadingSystemData = false);
    }
  }

  void _setEmptyState() {
    if (!mounted) return;
    setState(() {
      _sourceFileName = 'System data unavailable';
      _columns = _selectedReportType == 'Timecard'
          ? _timecardColumns
          : (_reportColumns[_selectedReportType] ?? const ['status']);
      _rows = [];
    });
  }

  List<Map<String, String>> _normalizeSystemRows(List<dynamic> rawList) {
    final normalized = <Map<String, String>>[];

    for (final item in rawList) {
      if (item is! Map) continue;

      final flat = <String, String>{};
      final map = item as Map<String, dynamic>;

      if (_selectedReportType == 'Timecard') {
        return _normalizeTimecardRows(rawList);
      }

      for (final entry in map.entries) {
        final key = entry.key.toString();
        final value = entry.value;

        if (key == 'user_account' && value is Map) {
          final userName = value['full_name'] ?? value['username'] ?? '';
          flat['driver_name'] = _normalizeCellValue(userName);
          continue;
        }

        if (key == 'vehicle' && value is Map) {
          final plate = value['plate_number'] ?? '';
          final vehicleType = value['bus_type'] ?? '';
          flat['plate_number'] = _normalizeCellValue(plate);
          flat['bus_type'] = _normalizeCellValue(vehicleType);
          continue;
        }

        if (key == 'oic_profile' && value is Map) {
          final company = value['company_name'] ?? '';
          flat['company_name'] = _normalizeCellValue(company);
          continue;
        }

        if (key == 'client_company' && value is Map) {
          flat['client_name'] = _normalizeCellValue(value['company_name']);
          continue;
        }

        if (key == 'client_company') {
          flat['client_name'] = _normalizeCellValue(value);
          continue;
        }

        flat[key] = _normalizeCellValue(value);
      }
      if (_selectedReportType == 'Trips') {
        flat['client_name'] =
            flat['client_name'] ??
            flat['company_name'] ??
            flat['client'] ??
            'Unassigned Client';
        flat['company_id'] = flat['company_id'] ?? 'N/A';
        flat['departure_time'] = flat['departure_time'] ?? '--:--';
        flat['estimated_arrival_time'] =
            flat['estimated_arrival_time'] ?? '--:--';
        flat['actual_start_time'] = flat['actual_start_time'] ?? '--:--';
        flat['actual_end_time'] = flat['actual_end_time'] ?? '--:--';
        flat['trip_id'] = flat['trip_id'] ?? 'N/A';
        flat['status'] = _normalizeCellValue(
          flat['trip_status'] ?? flat['status'] ?? 'Scheduled',
        );
      } else if (_selectedReportType == 'Maintenance') {
        flat['status'] = _normalizeCellValue(
          flat['status'] ??
              (flat['is_resolved']?.toLowerCase() == 'true'
                  ? 'Resolved'
                  : 'Needs Attention'),
        );
      }
      if (flat.isNotEmpty) normalized.add(flat);
    }
    return normalized;
  }

  Widget _buildReportTitle(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Import & Export',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'View system reports and manage timecards.',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildImportButton() {
    return FilledButton.icon(
      onPressed: _isImporting || !_canImportCurrentReport
          ? null
          : _pickExcelFile,
      icon: _isImporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_file_outlined),
      label: Text(
        _isImporting
            ? 'Importing...'
            : _canImportCurrentReport
            ? 'Import Excel'
            : 'Import Locked',
      ),
    );
  }

  Widget _buildExportButton() {
    return OutlinedButton.icon(
      onPressed: _showExportDialog,
      icon: const Icon(Icons.download_outlined),
      label: const Text('Export Report'),
    );
  }

  Future<void> _pickExcelFile() async {
    setState(() => _isImporting = true);

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xls', 'xlsx', 'csv'],
        withData: true,
      );

      if (result.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No spreadsheet file was selected.')),
        );
        return;
      }

      final file = result.first;
      final lowerName = file.name.toLowerCase();
      final fileBytes = await file.readAsBytes();

      List<List<dynamic>> rawRows = [];

      if (lowerName.endsWith('.xls')) {
        rawRows = await _convertLegacyXlsDirectly(fileBytes, file.name);
        if (rawRows.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not read .xls file via backend. Save as .xlsx locally and try again.',
              ),
            ),
          );
          return;
        }
      } else {
        rawRows = _extractRawRows(fileBytes, lowerName.endsWith('.csv'));
      }

      final parsedRows = _applySmartHeuristics(rawRows);

      if (!mounted) return;
      if (parsedRows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid biometric records found.')),
        );
        return;
      }

      setState(() {
        _sourceFileName = file.name;
        _columns = _timecardColumns;
        _rows = parsedRows;
        _currentPage = 0;
        _selectedRange = 'All Time';
        _customDateRange = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${parsedRows.length} biometric rows from ${file.name}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to read the spreadsheet: $error')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<List<List<dynamic>>> _convertLegacyXlsDirectly(
    Uint8List fileBytes,
    String fileName,
  ) async {
    final endpoints = [
      '/${widget.userRole}/timecards/upload-legacy-xls',
      '/admin/timecards/upload-legacy-xls',
      '/${widget.userRole}/attendance/upload-legacy-xls',
      '/admin/attendance/upload-legacy-xls',
    ];

    for (final endpoint in endpoints) {
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$backendUrl$endpoint'),
        );
        request.files.add(
          http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
        );
        final response = await http.Response.fromStream(await request.send());

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final rows = decoded['rows'] as List<dynamic>? ?? const [];
          if (rows.isNotEmpty && rows.first is Map) {
            return rows
                .map<List<dynamic>>((row) => (row as Map).values.toList())
                .toList();
          } else if (rows.isNotEmpty && rows.first is List) {
            return rows.cast<List<dynamic>>();
          }
          return [];
        }
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  List<String> _buildColumns(List<String> keys) {
    final seen = <String>{};
    final unique = <String>[];
    for (final key in keys) {
      final cleaned = key.trim();
      if (cleaned.isEmpty) continue;
      final normalized = seen.contains(cleaned)
          ? '${cleaned}_${seen.length}'
          : cleaned;
      seen.add(cleaned);
      unique.add(normalized);
    }
    return unique.isEmpty ? ['No columns detected'] : unique;
  }

  // ===========================================================================
  // EXPORT LOGIC
  // ===========================================================================

  Future<void> _showExportDialog() async {
    final activeRows = _processedRows;
    if (activeRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available to export.')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Export ${_selectedReportType}'),
          content: Text(
            'You are about to export ${activeRows.length} displayed records.\n\nPlease select your preferred file format.',
            style: const TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _executeExport('CSV');
              },
              icon: const Icon(Icons.data_object),
              label: const Text('Download CSV'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _executeExport('XLSX');
              },
              icon: const Icon(Icons.table_view),
              label: const Text('Download XLSX'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _executeExport(String format) async {
    final filteredRows = _processedRows;
    final exportColumns = _selectedReportType == 'Timecard'
        ? _timecardColumns
        : (_reportColumns[_selectedReportType] ?? _columns);

    String baseName;
    if (_sourceFileName != 'No file selected' &&
        !_sourceFileName.startsWith('System ')) {
      baseName = _sourceFileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    } else {
      String suffix = _selectedRange == 'All Time'
          ? 'all_time'
          : _selectedRange.toLowerCase().replaceAll(' ', '_');
      baseName = '${_selectedReportType.toLowerCase()}_report_$suffix';
    }

    final fileName = '$baseName.${format.toLowerCase()}';

    try {
      final bytes = format == 'XLSX'
          ? _convertRowsToXlsx(
              filteredRows.isEmpty
                  ? [
                      {for (final column in exportColumns) column: ''},
                    ]
                  : filteredRows,
              exportColumns,
            )
          : utf8.encode(
              <List<String>>[
                exportColumns,
                ...filteredRows.map(
                  (row) => exportColumns
                      .map(
                        (column) => _escapeCsv(
                          _formatDisplayValue(column, row[column] ?? ''),
                        ),
                      )
                      .toList(),
                ),
              ].map((row) => row.map((value) => value).join(',')).join('\n'),
            );

      if (kIsWeb) {
        await downloadFileBytes(fileName: fileName, bytes: bytes);
      } else {
        await FilePicker.saveFile(fileName: fileName, bytes: bytes);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported ${filteredRows.length} rows as $fileName'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to export report: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 700;

    final activeData = _processedRows;
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage > activeData.length)
        ? activeData.length
        : startIndex + _rowsPerPage;
    final displayRows = activeData.isEmpty
        ? []
        : activeData.sublist(startIndex, endIndex);
    final totalPages = (activeData.length / _rowsPerPage).ceil();

    final tableColumns = _columns.isEmpty
        ? const [DataColumn(label: Text('No data'))]
        : _columns
              .map(
                (col) => DataColumn(
                  label: Text(
                    _formatTableHeader(col),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              )
              .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ==========================================
              // TOP HEADER
              // ==========================================
              isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildReportTitle(isDark),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildImportButton(),
                            _buildExportButton(),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: _buildReportTitle(isDark)),
                        const SizedBox(width: 16),
                        _buildImportButton(),
                        const SizedBox(width: 12),
                        _buildExportButton(),
                      ],
                    ),
              const SizedBox(height: 20),

              // ==========================================
              // INFO PANEL
              // ==========================================
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111827) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      color: Colors.blue.shade500,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _sourceFileName,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Total: ${activeData.length} rows',
                        style: const TextStyle(
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ==========================================
              // CONTROLS ROW (Chips, Search, Filter, Sort)
              // ==========================================
              Flex(
                direction: isMobile ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    fit: isMobile ? FlexFit.loose : FlexFit.tight,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _reportTypes.map((type) {
                        final isSelected = _selectedReportType == type;
                        return ChoiceChip(
                          label: Text(type),
                          selected: isSelected,
                          avatar: Icon(
                            type == 'Trips'
                                ? Icons.route_outlined
                                : type == 'Maintenance'
                                ? Icons.build_outlined
                                : Icons.schedule_outlined,
                            size: 18,
                          ),
                          onSelected: (_) async {
                            setState(() => _selectedReportType = type);
                            await _loadCurrentReportData();
                          },
                          selectedColor: Colors.blue.shade100,
                          backgroundColor: isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.blue.shade900
                                : (isDark ? Colors.white : Colors.black87),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (_columns.isNotEmpty && _rows.isNotEmpty) ...[
                    // Search Bar
                    SizedBox(
                      width: isMobile ? double.infinity : 200,
                      height: 42,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() {
                          _searchQuery = val;
                          _currentPage = 0;
                        }),
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                      _currentPage = 0;
                                    });
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 0,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1F2937)
                              : Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Date Filter Dropdown
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1F2937) : Colors.white,
                        border: Border.all(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: PopupMenuButton<String>(
                        tooltip: 'Filter by Date Range',
                        offset: const Offset(0, 48),
                        icon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down,
                              size: 18,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ],
                        ),
                        onSelected: (val) async {
                          if (val == 'Custom Range') {
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDateRange: _customDateRange,
                              builder: (context, child) {
                                return Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 400,
                                      maxHeight: 600,
                                    ),
                                    child: child,
                                  ),
                                );
                              },
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedRange = val;
                                _customDateRange = picked;
                                _currentPage = 0;
                              });
                            }
                          } else {
                            setState(() {
                              _selectedRange = val;
                              _currentPage = 0;
                            });
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'All Time',
                            child: Text('All Time'),
                          ),
                          const PopupMenuItem(
                            value: 'Today',
                            child: Text('Today'),
                          ),
                          const PopupMenuItem(
                            value: 'This Week',
                            child: Text('This Week'),
                          ),
                          const PopupMenuItem(
                            value: 'This Month',
                            child: Text('This Month'),
                          ),
                          const PopupMenuItem(
                            value: 'This Year',
                            child: Text('This Year'),
                          ),
                          const PopupMenuItem(
                            value: 'Custom Range',
                            child: Text('Custom Range...'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Date Sort Asc/Desc Toggle
                    Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1F2937) : Colors.white,
                        border: Border.all(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Tooltip(
                        message: _sortDateAscending
                            ? 'Oldest First'
                            : 'Newest First',
                        child: InkWell(
                          onTap: () => setState(() {
                            _sortDateAscending = !_sortDateAscending;
                            _currentPage = 0;
                          }),
                          borderRadius: BorderRadius.circular(8),
                          child: Center(
                            child: Icon(
                              _sortDateAscending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (_selectedRange != 'All Time')
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Filtering: $_selectedRange',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // ==========================================
              // FIT TABLE CONTAINER
              // ==========================================
              Expanded(
                child: _isLoadingSystemData
                    ? const Center(child: CircularProgressIndicator())
                    : activeData.isEmpty
                    ? const Center(
                        child: Text('No report data matches current filters'),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF111827)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(17),
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: DataTable(
                                      headingRowColor: WidgetStatePropertyAll(
                                        isDark
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFFF8FAFC),
                                      ),
                                      columnSpacing: 24,
                                      dataRowMinHeight: 52,
                                      dataRowMaxHeight: 90,
                                      columns: tableColumns,
                                      rows: displayRows.map((row) {
                                        return DataRow(
                                          cells: _columns.map((col) {
                                            final displayValue =
                                                _formatDisplayValue(
                                                  col,
                                                  row[col] ?? '',
                                                );
                                            final isStatus =
                                                col == 'status' ||
                                                col == 'trip_status';
                                            final statusColor = _statusColor(
                                              displayValue,
                                              isDark,
                                            );
                                            return DataCell(
                                              Container(
                                                padding: isStatus
                                                    ? const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      )
                                                    : EdgeInsets.zero,
                                                decoration: isStatus
                                                    ? BoxDecoration(
                                                        color: statusColor
                                                            .withOpacity(0.12),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      )
                                                    : null,
                                                child: ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                        minWidth: 80,
                                                        maxWidth: 200,
                                                      ),
                                                  child: Text(
                                                    displayValue,
                                                    style: isStatus
                                                        ? TextStyle(
                                                            color: statusColor,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          )
                                                        : null,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 2,
                                                  ),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 16.0,
                              ),
                              child: Wrap(
                                alignment: WrapAlignment.start,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 24,
                                runSpacing: 12,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Rows per page:',
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      DropdownButton<int>(
                                        value: _rowsPerPage,
                                        underline: const SizedBox(),
                                        iconSize: 20,
                                        items: [10, 20, 50].map((int value) {
                                          return DropdownMenuItem<int>(
                                            value: value,
                                            child: Text(
                                              value.toString(),
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (value) {
                                          if (value != null) {
                                            setState(() {
                                              _rowsPerPage = value;
                                              _currentPage = 0;
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  UniversalPagination(
                                    currentPage: _currentPage,
                                    totalPages: totalPages,
                                    totalItems: activeData.length,
                                    itemsPerPage: _rowsPerPage,
                                    itemName: 'rows',
                                    onNextPage: _currentPage < totalPages - 1
                                        ? () => setState(() => _currentPage++)
                                        : null,
                                    onPrevPage: _currentPage > 0
                                        ? () => setState(() => _currentPage--)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // DATA FORMATTERS
  // ===========================================================================

  String _formatDisplayValue(String column, String rawValue) {
    if (column == 'in_time' || column == 'out_time') {
      return _formatTimeValue(rawValue);
    } else if (column == 'work_time' || column == 'daily_total') {
      return _formatDurationValue(rawValue);
    } else if (column == 'date' ||
        column == 'incident_date' ||
        column == 'schedule_date') {
      return _formatDateValue(rawValue);
    } else if (column == 'day') {
      return (rawValue == 'NaN' || rawValue.isEmpty || rawValue == 'null')
          ? '-'
          : rawValue.toUpperCase();
    }
    return rawValue;
  }

  String _formatTimeValue(String val) {
    if (val.isEmpty || val == 'null' || val == 'NaN') return '-';
    final trimmed = val.trim();
    final amPmRegex = RegExp(r'^\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)$');
    if (amPmRegex.hasMatch(trimmed)) return trimmed.toUpperCase();

    try {
      final parsed = DateTime.parse(trimmed);
      return _formatHoursMinutes(parsed.hour, parsed.minute);
    } catch (_) {}

    try {
      final parts = trimmed.split(' ');
      if (parts.length == 2) {
        final timeParts = parts[1].split(':');
        if (timeParts.length >= 2) {
          return _formatHoursMinutes(
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
          );
        }
      }
    } catch (_) {}

    try {
      final parts = trimmed.split(':');
      if (parts.length >= 2) {
        return _formatHoursMinutes(int.parse(parts[0]), int.parse(parts[1]));
      }
    } catch (_) {}

    return trimmed;
  }

  String _formatHoursMinutes(int hour, int minute) {
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final displayMin = minute.toString().padLeft(2, '0');
    return '${displayHour.toString().padLeft(2, '0')}:$displayMin $ampm';
  }

  String _formatDurationValue(String val) {
    if (val.isEmpty || val == 'null' || val == 'NaN') return '-';
    final trimmed = val.trim();
    final doubleValue = double.tryParse(trimmed);

    if (doubleValue != null) {
      final hours = doubleValue.floor();
      final minutes = ((doubleValue - hours) * 60).round();
      if (hours == 0 && minutes == 0) return '0h 0m';
      if (hours == 0) return '${minutes}m';
      if (minutes == 0) return '${hours}h';
      return '${hours}h ${minutes}m';
    }

    try {
      final parts = trimmed.split(':');
      if (parts.length >= 2) {
        final hours = int.tryParse(parts[0]);
        final minutes = int.tryParse(parts[1]);
        if (hours != null && minutes != null) {
          if (hours == 0 && minutes == 0) return '0h 0m';
          if (hours == 0) return '${minutes}m';
          if (minutes == 0) return '${hours}h';
          return '${hours}h ${minutes}m';
        }
      }
    } catch (_) {}

    if (trimmed.contains('h') || trimmed.contains('m')) return trimmed;
    return val;
  }

  String _formatDateValue(String val) {
    if (val.isEmpty || val == 'null' || val == 'NaN') return '-';
    try {
      final cleanDate = val.trim().split('T').first;
      final parsed = DateTime.tryParse(cleanDate);
      if (parsed != null) {
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
        return '${months[parsed.month - 1]} ${parsed.day.toString().padLeft(2, '0')}, ${parsed.year}';
      }
      return cleanDate;
    } catch (_) {
      return val;
    }
  }

  String _formatTableHeader(String value) {
    final lowerVal = value.trim().toLowerCase();
    if (lowerVal == 'employee') return 'Employee';
    if (lowerVal == 'pay_period') return 'Pay Period';
    if (lowerVal == 'day') return 'Day';
    if (lowerVal == 'date') return 'Date';
    if (lowerVal == 'in_time' || lowerVal == 'in') return 'IN';
    if (lowerVal == 'out_time' || lowerVal == 'out') return 'OUT';
    if (lowerVal == 'work_time' || lowerVal == 'work_hours') return 'Work Time';
    if (lowerVal == 'daily_total' || lowerVal == 'total_hours')
      return 'Daily Total';
    if (lowerVal == 'note' || lowerVal == 'notes' || lowerVal == 'remarks')
      return 'Note';

    final cleaned = value
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Column';

    return cleaned
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          final lowerWord = word.toLowerCase();
          if (lowerWord == 'id' || lowerWord == 'ids') return 'ID';
          if (word.length <= 2) return lowerWord.toUpperCase();
          return lowerWord[0].toUpperCase() + lowerWord.substring(1);
        })
        .join(' ');
  }

  Color _statusColor(String status, bool isDark) {
    final normalized = status.toLowerCase();
    if (normalized.contains('completed') ||
        normalized.contains('resolved') ||
        normalized.contains('scheduled')) {
      return const Color(0xFF10B981);
    }
    if (normalized.contains('rejected') ||
        normalized.contains('expired') ||
        normalized.contains('attention') ||
        normalized.contains('maintenance')) {
      return const Color(0xFFEF4444);
    }
    if (normalized.contains('ongoing') || normalized.contains('progress')) {
      return const Color(0xFF3B82F6);
    }
    return isDark ? Colors.grey.shade300 : const Color(0xFF64748B);
  }

  String _normalizeCellValue(dynamic value) {
    if (value == null) return '';
    if (value is DateTime) return value.toIso8601String();
    if (value is num) return value.toString();
    if (value is Map)
      return value.entries
          .map((e) => '${e.key}: ${_normalizeCellValue(e.value)}')
          .join(', ');
    if (value is Iterable)
      return value.map((i) => _normalizeCellValue(i)).join(', ');
    return value.toString().trim();
  }

  List<String> _splitCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final character = line[i];
      if (character == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (character == ',' && !inQuotes) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(character);
      }
    }
    values.add(buffer.toString());
    return values;
  }

  String _escapeCsv(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  List<Map<String, String>> _normalizeTimecardRows(List<dynamic> rawList) {
    final normalized = <Map<String, String>>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final map = item as Map<String, dynamic>;

      String employeeId = '';
      String employeeName = '';
      if (map['user_account'] is Map) {
        final userAccount = map['user_account'] as Map<String, dynamic>;
        employeeId = (userAccount['id'] ?? userAccount['user_id'] ?? '')
            .toString();
        employeeName =
            (userAccount['full_name'] ?? userAccount['username'] ?? '')
                .toString();
      } else {
        employeeId = (map['employee_id'] ?? '').toString();
        employeeName = (map['employee_name'] ?? '').toString();
      }

      String dateStr = (map['date'] ?? map['work_date'] ?? '').toString();
      String dayOfWeek = 'NaN';

      if (dateStr.isNotEmpty && dateStr != 'null' && dateStr != 'NaN') {
        try {
          final date = DateTime.parse(dateStr);
          const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
          dayOfWeek = days[date.weekday - 1];
        } catch (_) {}
      }

      normalized.add({
        'employee': employeeName.isNotEmpty && employeeId.isNotEmpty
            ? '$employeeName ($employeeId)'
            : (employeeName.isNotEmpty ? employeeName : 'Unknown'),
        'pay_period': (map['pay_period'] ?? '').toString(),
        'day': dayOfWeek,
        'date': dateStr,
        'in_time': (map['in_time'] ?? map['time_in'] ?? '').toString(),
        'out_time': (map['out_time'] ?? map['time_out'] ?? '').toString(),
        'work_time': (map['work_time'] ?? map['work_hours'] ?? '').toString(),
        'daily_total': (map['daily_total'] ?? map['total_hours'] ?? '')
            .toString(),
        'note': (map['note'] ?? map['notes'] ?? '').toString(),
      });
    }
    return normalized;
  }

  List<List<dynamic>> _extractRawRows(Uint8List bytes, bool isCsv) {
    List<List<dynamic>> rawRows = [];
    if (isCsv) {
      final lines = const LineSplitter().convert(utf8.decode(bytes));
      for (var line in lines) {
        rawRows.add(_splitCsvLine(line));
      }
    } else {
      final workbook = excel.Excel.decodeBytes(bytes);
      if (workbook.tables.isNotEmpty) {
        rawRows = workbook.tables[workbook.tables.keys.first]!.rows;
      }
    }
    return rawRows;
  }

  List<Map<String, String>> _applySmartHeuristics(List<List<dynamic>> rawRows) {
    String currentEmployee = 'Unknown';
    String currentPayPeriod = 'NaN';
    String currentDate = 'NaN';
    String currentDay = 'NaN';
    final parsedRows = <Map<String, String>>[];

    for (var row in rawRows) {
      bool hasEmployeeLabel = row.any(
        (c) => [
          'employee',
          'name',
        ].contains(_normalizeCellValue(c).trim().toLowerCase()),
      );
      if (hasEmployeeLabel) {
        currentEmployee = _normalizeCellValue(
          row.firstWhere((c) {
            final val = _normalizeCellValue(c).trim().toLowerCase();
            return val.isNotEmpty && val != 'employee' && val != 'name';
          }, orElse: () => 'Unknown'),
        );
      }

      for (var cell in row) {
        String val = _normalizeCellValue(cell).trim();
        if (RegExp(
          r'\d{2,4}[-/]\d{1,2}[-/]\d{1,4}.*?\d{2,4}[-/]\d{1,2}[-/]\d{1,4}',
        ).hasMatch(val)) {
          currentPayPeriod = val;
        }
      }

      List<String> times = [];
      String rowDate = '';
      String rowDay = '';
      List<String> texts = [];

      for (var cell in row) {
        String val = _normalizeCellValue(cell).trim();
        if (val.isEmpty) continue;

        if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(val)) {
          times.add(val.substring(0, 5));
          continue;
        }
        if (RegExp(r'^\d{1,4}[-/]\d{1,2}[-/]\d{1,4}$').hasMatch(val)) {
          rowDate = val;
          continue;
        }
        final upper = val.toUpperCase();
        if (['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'].contains(upper)) {
          rowDay = upper;
          continue;
        }
        texts.add(val);
      }

      if (rowDate.isNotEmpty) currentDate = rowDate;
      if (rowDay.isNotEmpty) currentDay = rowDay;

      if (rowDate.isEmpty && times.isNotEmpty) {
        rowDate = currentDate;
        rowDay = currentDay;
      }

      if (times.isNotEmpty) {
        texts.removeWhere(
          (t) =>
              [
                'IN',
                'OUT',
                'Work Time',
                'Daily Total',
                'Note',
                'Date',
                'Day',
                'Employee',
                'Pay Period',
              ].contains(t) ||
              t == currentPayPeriod ||
              t == currentEmployee,
        );

        parsedRows.add({
          'employee': currentEmployee,
          'pay_period': currentPayPeriod,
          'day': rowDay.isNotEmpty ? rowDay : currentDay,
          'date': rowDate,
          'in_time': times.isNotEmpty ? times[0] : 'NaN',
          'out_time': times.length > 1 ? times[1] : 'NaN',
          'work_time': times.length > 2 ? times[2] : 'NaN',
          'daily_total': times.length > 3 ? times[3] : 'NaN',
          'note': texts.isNotEmpty ? texts.join(' | ') : 'NaN',
        });
      }
    }
    return parsedRows;
  }

  Uint8List _convertRowsToXlsx(
    List<Map<String, String>> rows,
    List<String> columns,
  ) {
    final workbook = excel.Excel.createExcel();
    final sheet = workbook['Sheet1'];
    if (sheet == null) return Uint8List(0);

    final headerCells = columns
        .map((c) => excel.TextCellValue(_formatTableHeader(c)))
        .toList();
    sheet.insertRowIterables(headerCells, 0);

    for (int i = 0; i < rows.length; i++) {
      final values = columns.map((column) {
        final rawValue = rows[i][column] ?? '';
        final displayValue = _formatDisplayValue(column, rawValue);
        return excel.TextCellValue(displayValue);
      }).toList();
      sheet.insertRowIterables(values, i + 1);
    }

    // CHANGED: Use encode() instead of save() to prevent the double-download on Web
    return Uint8List.fromList(workbook.encode() ?? []);
  }
}
