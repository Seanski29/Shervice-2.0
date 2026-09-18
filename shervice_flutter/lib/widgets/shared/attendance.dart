import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart' as excel;

import '../../constant.dart';
import '../../utils/file_download.dart';
import 'universal_pagination.dart';

class Attendance extends StatefulWidget {
  final String userRole;

  const Attendance({super.key, required this.userRole});

  @override
  State<Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<Attendance> {
  bool _isImporting = false;
  bool _isLoadingSystemData = false;
  String _sourceFileName = 'No file selected';
  String? _selectedSourceFile;

  int _rowsPerPage = 10;
  int _currentPage = 0;
  bool _sortDateAscending = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  String _selectedRange = 'Today';
  DateTimeRange? _customDateRange;

  final List<String> _attendanceColumns = [
    'employee',
    'date',
    'morning_in',
    'morning_out',
    'afternoon_in',
    'afternoon_out',
    'overtime_in',
    'overtime_out',
    'total_minutes_late',
  ];

  List<String> _columns = [];
  List<Map<String, String>> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadAttendanceData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _processedRows {
    List<Map<String, String>> result = List.from(_rows);

    if (_selectedSourceFile != null) {
      result = result
          .where((row) => row['source_file'] == _selectedSourceFile)
          .toList();
    }

    DateTime now = DateTime.now();
    DateTime? startDate;
    DateTime? endDate;

    if (_selectedRange == 'Today') {
      startDate = DateTime(now.year, now.month, now.day);
      endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_selectedRange == 'This Week') {
      startDate = DateTime(now.year, now.month, now.day);
      endDate = startDate.add(
        const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
      );
    } else if (_selectedRange == 'Custom Week' && _customDateRange != null) {
      startDate = _customDateRange!.start;
      endDate = DateTime(
        _customDateRange!.end.year,
        _customDateRange!.end.month,
        _customDateRange!.end.day,
        23,
        59,
        59,
      );
    } else if (_selectedRange == 'Month' && _customDateRange != null) {
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
      final filterStart = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      );
      final filterEnd = DateTime(endDate.year, endDate.month, endDate.day);
      result = result.where((row) {
        final dateStr = _extractDateFromRow(row);
        if (dateStr == 'NaN' || dateStr.isEmpty) return false;
        try {
          final parsed = DateTime.parse(dateStr.split('T')[0]);
          final parsedDay = DateTime(parsed.year, parsed.month, parsed.day);
          return !parsedDay.isBefore(filterStart) &&
              !parsedDay.isAfter(filterEnd);
        } catch (_) {
          return false;
        }
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((row) {
        return row.values.any(
          (val) => _formatDisplayValue('', val).toLowerCase().contains(query),
        );
      }).toList();
    }

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
    return row['date'] ?? '';
  }

  Future<void> _loadAttendanceData() async {
    setState(() {
      _isLoadingSystemData = true;
      _currentPage = 0;
      _selectedRange = 'Today';
      _customDateRange = null;
    });

    try {
      var response = await http.get(
        Uri.parse('$backendUrl/${widget.userRole}/attendance'),
      );
      if (response.statusCode != 200) {
        response = await http.get(Uri.parse('$backendUrl/admin/attendance'));
      }

      if (response.statusCode != 200) {
        _setEmptyState();
        return;
      }

      final decoded = jsonDecode(response.body);
      final rawList =
          (decoded is Map
              ? decoded['data'] ?? decoded['attendance']
              : decoded) ??
          [];
      final normalized = _normalizeAttendanceRows(rawList);

      if (!mounted) return;
      setState(() {
        _sourceFileName = _selectedSourceFile == null
            ? 'System attendance records'
            : 'Imported attendance: $_selectedSourceFile';
        _columns = _attendanceColumns;
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
      _columns = _attendanceColumns;
      _rows = [];
    });
  }

  Widget _buildAttendanceTitle(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attendance',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Import, view, and export attendance records.',
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
      onPressed: _isImporting ? null : _pickExcelFile,
      icon: _isImporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_file_outlined),
      label: Text(_isImporting ? 'Importing...' : 'Import Excel'),
    );
  }

  Widget _buildExportButton() {
    return OutlinedButton.icon(
      onPressed: _showExportDialog,
      icon: const Icon(Icons.download_outlined),
      label: const Text('Export'),
    );
  }

  Future<void> _pickExcelFile() async {
    setState(() => _isImporting = true);

    try {
      // 🔥 FIX: Version 13 Syntax Applied
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xls', 'xlsx', 'csv'],
      );

      if (result == null || result.isEmpty) {
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

      final importedRows = parsedRows
          .map((row) => {...row, 'source_file': file.name})
          .toList();

      _selectedSourceFile = file.name;
      final savedCount = await _saveImportedAttendance(importedRows, file.name);
      if (!mounted) return;

      setState(() {
        _sourceFileName = file.name;
        _columns = _attendanceColumns;
        _rows = importedRows;
        _currentPage = 0;
        _selectedRange = 'Today';
        _customDateRange = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported and saved $savedCount attendance rows from ${file.name}',
          ),
        ),
      );

      await _loadAttendanceData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to read the spreadsheet: $error')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<int> _saveImportedAttendance(
    List<Map<String, String>> rows,
    String fileName,
  ) async {
    final endpoints = [
      '/${widget.userRole}/attendance/import',
      '/admin/attendance/import',
    ];

    Object? lastError;
    for (final endpoint in endpoints) {
      try {
        final response = await http.post(
          Uri.parse('$backendUrl$endpoint'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'source_file': fileName, 'rows': rows}),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          return int.tryParse('${decoded['saved_count'] ?? rows.length}') ??
              rows.length;
        }

        lastError = response.body;
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception('Attendance import was not saved: $lastError');
  }

  Future<List<List<dynamic>>> _convertLegacyXlsDirectly(
    Uint8List fileBytes,
    String fileName,
  ) async {
    final endpoints = [
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
          title: const Text('Export Attendance'),
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
    final exportColumns = _attendanceColumns;

    if (!_canExportCurrentDateFilter()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose Today, This Week, Custom Week, or Month before exporting attendance.',
          ),
        ),
      );
      return;
    }

    final baseName = _exportBaseName(filteredRows);
    final fileName = '$baseName.${format.toLowerCase()}';

    try {
      final bytes = format == 'XLSX'
          ? _convertRowsToXlsx(
              filteredRows.isEmpty
                  ? [
                      {for (final column in exportColumns) column: ''},
                    ]
                  : filteredRows,
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
        // 🔥 FIX: Version 13 Syntax Applied
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
        SnackBar(content: Text('Unable to export attendance: $error')),
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
              isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAttendanceTitle(isDark),
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
                        Expanded(child: _buildAttendanceTitle(isDark)),
                        const SizedBox(width: 16),
                        _buildImportButton(),
                        const SizedBox(width: 12),
                        _buildExportButton(),
                      ],
                    ),
              const SizedBox(height: 20),

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

              Flex(
                direction: isMobile ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_columns.isNotEmpty && _rows.isNotEmpty) ...[
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Total: ${activeData.length} rows',
                        style: const TextStyle(
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(width: isMobile ? 0 : 8, height: isMobile ? 8 : 0),
                    Container(
                      height: 42,
                      width: isMobile ? double.infinity : 560,
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
                        tooltip: 'Date',
                        offset: const Offset(0, 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Date: ${_dateFilterLabel()}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF111827),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 18,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ],
                          ),
                        ),
                        onSelected: (val) async {
                          if (val == 'Custom Week') {
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
                              final dayCount =
                                  picked.end.difference(picked.start).inDays +
                                  1;
                              if (dayCount > 7) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Attendance print range can only be one week at most.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                _selectedRange = val;
                                _customDateRange = picked;
                                _currentPage = 0;
                              });
                            }
                          } else if (val == 'Month') {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDate:
                                  _customDateRange?.start ?? DateTime.now(),
                              helpText: 'Select month',
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
                              final start = DateTime(
                                picked.year,
                                picked.month,
                                1,
                              );
                              final end = DateTime(
                                picked.year,
                                picked.month + 1,
                                0,
                              );
                              setState(() {
                                _selectedRange = val;
                                _customDateRange = DateTimeRange(
                                  start: start,
                                  end: end,
                                );
                                _currentPage = 0;
                              });
                            }
                          } else {
                            setState(() {
                              _selectedRange = val;
                              _customDateRange = null;
                              _currentPage = 0;
                            });
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'Today',
                            child: Text('Today'),
                          ),
                          const PopupMenuItem(
                            value: 'This Week',
                            child: Text('This Week'),
                          ),
                          const PopupMenuItem(
                            value: 'Custom Week',
                            child: Text('Custom Week...'),
                          ),
                          const PopupMenuItem(
                            value: 'Month',
                            child: Text('Month...'),
                          ),
                        ],
                      ),
                    ),
                    if (!isMobile) const Spacer(),
                    SizedBox(width: isMobile ? 0 : 8, height: isMobile ? 8 : 0),
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
                    SizedBox(width: isMobile ? 0 : 8, height: isMobile ? 8 : 0),
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
              const SizedBox(height: 16),

              Expanded(
                child: _isLoadingSystemData
                    ? const Center(child: CircularProgressIndicator())
                    : activeData.isEmpty
                    ? const Center(
                        child: Text(
                          'No attendance data matches current filters',
                        ),
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
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final tableWidth =
                                        constraints.maxWidth < 1100
                                        ? 1100.0
                                        : constraints.maxWidth;

                                    return SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minWidth: tableWidth,
                                        ),
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.vertical,
                                          child: DataTable(
                                            headingRowColor:
                                                WidgetStatePropertyAll(
                                                  isDark
                                                      ? const Color(0xFF1E293B)
                                                      : const Color(0xFFF8FAFC),
                                                ),
                                            columnSpacing: 24,
                                            horizontalMargin: 30,
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
                                                  final isLateColumn =
                                                      col ==
                                                      'total_minutes_late';
                                                  final lateMinutes =
                                                      int.tryParse(
                                                        row[col] ?? '',
                                                      ) ??
                                                      0;
                                                  final isHalfDay =
                                                      (row[col] ?? '')
                                                          .toLowerCase()
                                                          .contains('half');
                                                  final isAbsent =
                                                      (row[col] ?? '')
                                                          .toLowerCase()
                                                          .contains('absent');
                                                  return DataCell(
                                                    ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                            minWidth: 80,
                                                            maxWidth: 220,
                                                          ),
                                                      child: Text(
                                                        displayValue,
                                                        style:
                                                            isLateColumn &&
                                                                (lateMinutes >
                                                                        0 ||
                                                                    isHalfDay ||
                                                                    isAbsent)
                                                            ? const TextStyle(
                                                                color: Color(
                                                                  0xFFEF4444,
                                                                ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              )
                                                            : null,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        maxLines: 2,
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
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

  String _formatDisplayValue(String column, String rawValue) {
    if (column == 'in_time' ||
        column == 'out_time' ||
        column.endsWith('_in') ||
        column.endsWith('_out')) {
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
    } else if (column == 'total_minutes_late') {
      final minutes = int.tryParse(rawValue) ?? 0;
      if (rawValue.toLowerCase().contains('half')) return 'Half Day';
      if (rawValue.toLowerCase().contains('absent')) return 'Absent';
      return minutes > 0 ? '$minutes' : '-';
    }
    return rawValue;
  }

  bool _canExportCurrentDateFilter() {
    if (_selectedRange == 'Today' || _selectedRange == 'This Week') {
      return true;
    }
    if (_selectedRange == 'Custom Week' && _customDateRange != null) {
      return _customDateRange!.end.difference(_customDateRange!.start).inDays <
          7;
    }
    return _selectedRange == 'Month' && _customDateRange != null;
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
    return '$displayHour:$displayMin $ampm';
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
    if (lowerVal == 'morning_in') return 'Morning IN';
    if (lowerVal == 'morning_out') return 'Morning OUT';
    if (lowerVal == 'afternoon_in') return 'Afternoon IN';
    if (lowerVal == 'afternoon_out') return 'Afternoon OUT';
    if (lowerVal == 'overtime_in') return 'Overtime IN';
    if (lowerVal == 'overtime_out') return 'Overtime OUT';
    if (lowerVal == 'total_minutes_late') return 'Total Minutes Late';
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

  List<Map<String, String>> _normalizeAttendanceRows(List<dynamic> rawList) {
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

      final dateStr = (map['date'] ?? map['work_date'] ?? '').toString();
      var dayOfWeek = (map['day'] ?? map['day_label'] ?? '').toString();

      if ((dayOfWeek.isEmpty || dayOfWeek == 'null') &&
          dateStr.isNotEmpty &&
          dateStr != 'null' &&
          dateStr != 'NaN') {
        try {
          final date = DateTime.parse(dateStr);
          const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
          dayOfWeek = days[date.weekday - 1];
        } catch (_) {}
      }

      final shiftValues = _resolveShiftValues(map);
      final row = {
        'employee': employeeName.isNotEmpty && employeeId.isNotEmpty
            ? '$employeeName ($employeeId)'
            : (employeeName.isNotEmpty ? employeeName : 'Unknown'),
        'pay_period': (map['pay_period'] ?? '').toString(),
        'day': dayOfWeek.isNotEmpty && dayOfWeek != 'null' ? dayOfWeek : 'NaN',
        'date': dateStr,
        'in_time': (map['in_time'] ?? map['time_in'] ?? '').toString(),
        'out_time': (map['out_time'] ?? map['time_out'] ?? '').toString(),
        'work_time': (map['work_time'] ?? map['work_hours'] ?? '').toString(),
        'daily_total': (map['daily_total'] ?? map['total_hours'] ?? '')
            .toString(),
        'note': (map['note'] ?? map['notes'] ?? '').toString(),
        'source_file': (map['source_file'] ?? '').toString(),
        ...shiftValues,
      };
      row['total_minutes_late'] = _finalAttendanceValue(row);
      normalized.add(row);
    }
    return _mergeAttendanceRows(normalized);
  }

  Map<String, String> _resolveShiftValues(Map<String, dynamic> map) {
    final existing = {
      'morning_in': _firstValue(map, ['morning_in']),
      'morning_out': _firstValue(map, ['morning_out']),
      'afternoon_in': _firstValue(map, ['afternoon_in']),
      'afternoon_out': _firstValue(map, ['afternoon_out']),
      'overtime_in': _firstValue(map, ['overtime_in']),
      'overtime_out': _firstValue(map, ['overtime_out']),
    };

    if (existing.values.any((value) => _hasAttendanceValue(value))) {
      return existing;
    }

    final punchTimes = _collectPunchTimes(map);
    if (punchTimes.isNotEmpty) return _buildShiftValues(punchTimes);

    return existing;
  }

  String _firstValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = _normalizeCellValue(map[key]);
      if (_hasAttendanceValue(value)) return value;
    }
    return 'NaN';
  }

  List<String> _collectPunchTimes(Map<String, dynamic> map) {
    final values = <String>[];
    for (final key in ['in_time', 'time_in', 'out_time', 'time_out']) {
      final value = _normalizeCellValue(map[key]);
      if (_parseTimeToMinutes(value) != null) values.add(value);
    }
    return values;
  }

  bool _hasAttendanceValue(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != 'nan' &&
        normalized != 'null' &&
        normalized != '-';
  }

  Map<String, String> _buildShiftValues(List<String> times) {
    final shifts = {
      'morning_in': 'NaN',
      'morning_out': 'NaN',
      'afternoon_in': 'NaN',
      'afternoon_out': 'NaN',
      'overtime_in': 'NaN',
      'overtime_out': 'NaN',
    };

    for (var index = 0; index < times.length; index += 2) {
      final inTime = times[index];
      final outTime = index + 1 < times.length ? times[index + 1] : 'NaN';
      final inMinutes = _parseTimeToMinutes(inTime);
      final outMinutes = _parseTimeToMinutes(outTime);
      if (inMinutes == null && outMinutes == null) continue;

      _applyPunchPairToShifts(shifts, inTime, outTime, inMinutes, outMinutes);
    }

    return shifts;
  }

  void _applyPunchPairToShifts(
    Map<String, String> shifts,
    String inTime,
    String outTime,
    int? inMinutes,
    int? outMinutes,
  ) {
    const morningEnd = 7 * 60;
    const afternoonStart = 15 * 60;
    const afternoonEnd = 19 * 60;

    final start = inMinutes ?? outMinutes;
    if (start == null) return;

    if (start < morningEnd) {
      _setShiftPair(
        shifts,
        'morning',
        inTime,
        outMinutes != null && outMinutes > morningEnd
            ? _formatMinutesAsTime(morningEnd)
            : outTime,
      );
      if (outMinutes != null && outMinutes > morningEnd) {
        _setShiftPair(
          shifts,
          'overtime',
          _formatMinutesAsTime(morningEnd),
          outTime,
        );
      }
      return;
    }

    if (start >= afternoonStart && start < afternoonEnd) {
      _setShiftPair(
        shifts,
        'afternoon',
        inTime,
        outMinutes != null && outMinutes > afternoonEnd
            ? _formatMinutesAsTime(afternoonEnd)
            : outTime,
      );
      if (outMinutes != null && outMinutes > afternoonEnd) {
        _setShiftPair(
          shifts,
          'overtime',
          _formatMinutesAsTime(afternoonEnd),
          outTime,
        );
      }
      return;
    }

    _setShiftPair(shifts, 'overtime', inTime, outTime);
  }

  void _setShiftPair(
    Map<String, String> shifts,
    String shift,
    String inTime,
    String outTime,
  ) {
    final inKey = '${shift}_in';
    final outKey = '${shift}_out';
    final currentIn = shifts[inKey] ?? '';
    final currentOut = shifts[outKey] ?? '';

    if (!_hasAttendanceValue(currentIn) || _isEarlierTime(inTime, currentIn)) {
      shifts[inKey] = inTime;
    }
    if (_hasAttendanceValue(outTime) &&
        (!_hasAttendanceValue(currentOut) ||
            _isLaterTime(outTime, currentOut))) {
      shifts[outKey] = outTime;
    }
  }

  String _exportBaseName(List<Map<String, String>> rows) {
    final range = _activeDateFilterRange(rows);
    if (range != null) {
      return 'attendance_${_dateRangeFileSegment(range.start, range.end)}';
    }

    if (_sourceFileName != 'No file selected' &&
        !_sourceFileName.startsWith('System ')) {
      final source = _sourceFileName.replaceAll(RegExp(r'\.[^.]+$'), '');
      return 'attendance_${_fileSafeSegment(source)}';
    }

    final suffix = _selectedRange == 'All Time'
        ? 'all_time'
        : _fileSafeSegment(_selectedRange);
    return 'attendance_$suffix';
  }

  DateTimeRange? _activeDateFilterRange(List<Map<String, String>> rows) {
    final now = DateTime.now();
    if (_selectedRange == 'Today') {
      final day = DateTime(now.year, now.month, now.day);
      return DateTimeRange(start: day, end: day);
    }
    if (_selectedRange == 'This Week') {
      final start = DateTime(now.year, now.month, now.day);
      return DateTimeRange(
        start: start,
        end: start.add(const Duration(days: 6)),
      );
    }
    if ((_selectedRange == 'Custom Week' || _selectedRange == 'Month') &&
        _customDateRange != null) {
      return _customDateRange;
    }

    final dates =
        rows
            .map((row) => _parseFlexibleDate(_extractDateFromRow(row)))
            .whereType<DateTime>()
            .toList()
          ..sort();
    if (dates.isEmpty) return null;
    return DateTimeRange(start: dates.first, end: dates.last);
  }

  String _dateRangeFileSegment(DateTime start, DateTime end) {
    final sameMonth = start.year == end.year && start.month == end.month;
    final month = _monthName(start.month).toLowerCase();
    if (sameMonth) {
      return '${month}_${start.day}-${end.day}';
    }
    return '${month}_${start.day}_${_monthName(end.month).toLowerCase()}_${end.day}';
  }

  String _monthName(int month) {
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
    if (month < 1 || month > 12) return 'Unknown';
    return months[month - 1];
  }

  String _fileSafeSegment(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _dateFilterLabel() {
    final now = DateTime.now();
    if (_selectedRange == 'Today') {
      return 'Today(${_longDateLabel(DateTime(now.year, now.month, now.day))})';
    }
    if (_selectedRange == 'This Week') {
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 6));
      return 'This Week(${_longDateLabel(start)} - ${_longDateLabel(end)})';
    }
    if (_selectedRange == 'Custom Week' && _customDateRange != null) {
      return 'Custom Week(${_longDateLabel(_customDateRange!.start)} - ${_longDateLabel(_customDateRange!.end)})';
    }
    if (_selectedRange == 'Month' && _customDateRange != null) {
      return _monthName(_customDateRange!.start.month);
    }
    return _selectedRange;
  }

  String _longDateLabel(DateTime date) {
    return '${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  bool _isEarlierTime(String candidate, String current) {
    final candidateMinutes = _parseTimeToMinutes(candidate);
    final currentMinutes = _parseTimeToMinutes(current);
    if (candidateMinutes == null) return false;
    if (currentMinutes == null) return true;
    return candidateMinutes < currentMinutes;
  }

  bool _isLaterTime(String candidate, String current) {
    final candidateMinutes = _parseTimeToMinutes(candidate);
    final currentMinutes = _parseTimeToMinutes(current);
    if (candidateMinutes == null) return false;
    if (currentMinutes == null) return true;
    return candidateMinutes > currentMinutes;
  }

  String _formatMinutesAsTime(int minutes) {
    final hour = (minutes ~/ 60) % 24;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  int? _parseTimeToMinutes(String value) {
    if (!_hasAttendanceValue(value)) return null;
    final trimmed = value.trim();

    final amPmMatch = RegExp(
      r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (amPmMatch != null) {
      var hour = int.parse(amPmMatch.group(1)!);
      final minute = int.parse(amPmMatch.group(2)!);
      final meridiem = amPmMatch.group(3)!.toUpperCase();
      if (meridiem == 'PM' && hour != 12) hour += 12;
      if (meridiem == 'AM' && hour == 12) hour = 0;
      return hour * 60 + minute;
    }

    try {
      final parsed = DateTime.parse(trimmed);
      return parsed.hour * 60 + parsed.minute;
    } catch (_) {}

    final timeMatch = RegExp(
      r'(\d{1,2}):(\d{2})(?::\d{2})?',
    ).firstMatch(trimmed);
    if (timeMatch == null) return null;

    final hour = int.tryParse(timeMatch.group(1)!);
    final minute = int.tryParse(timeMatch.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  int _calculateTotalMinutesLate(Map<String, String> row) {
    var total = 0;
    final morningIn = _parseTimeToMinutes(row['morning_in'] ?? '');
    if (morningIn != null && morningIn > 3 * 60) {
      total += morningIn - 3 * 60;
    }

    final afternoonIn = _parseTimeToMinutes(row['afternoon_in'] ?? '');
    if (afternoonIn != null && afternoonIn > 15 * 60) {
      total += afternoonIn - 15 * 60;
    }
    return total;
  }

  bool _isHalfDay(Map<String, String> row) {
    if (_isAbsent(row)) return false;
    final hasMorning =
        _hasAttendanceValue(row['morning_in'] ?? '') ||
        _hasAttendanceValue(row['morning_out'] ?? '');
    final hasAfternoon =
        _hasAttendanceValue(row['afternoon_in'] ?? '') ||
        _hasAttendanceValue(row['afternoon_out'] ?? '');
    return hasMorning != hasAfternoon;
  }

  bool _isAbsent(Map<String, String> row) {
    final note = (row['note'] ?? '').toLowerCase();
    if (note.contains('absent') || note.contains('whole day')) return true;

    final hasRegularOrOvertime = [
      'morning_in',
      'morning_out',
      'afternoon_in',
      'afternoon_out',
      'overtime_in',
      'overtime_out',
    ].any((key) => _hasAttendanceValue(row[key] ?? ''));
    return !hasRegularOrOvertime;
  }

  String _finalAttendanceValue(Map<String, String> row) {
    if (_isAbsent(row)) return 'Absent';
    if (_isHalfDay(row)) return 'Half Day';
    return _calculateTotalMinutesLate(row).toString();
  }

  List<Map<String, String>> _mergeAttendanceRows(
    List<Map<String, String>> rows,
  ) {
    final grouped = <String, Map<String, String>>{};

    for (final row in rows) {
      final key =
          '${row['source_file'] ?? ''}|${row['employee']}|${row['date']}';
      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = Map<String, String>.from(row);
        continue;
      }

      for (final entry in row.entries) {
        final existingValue = existing[entry.key] ?? '';
        if (!_hasAttendanceValue(existingValue) &&
            _hasAttendanceValue(entry.value)) {
          existing[entry.key] = entry.value;
        }
      }

      for (final shift in ['morning', 'afternoon', 'overtime']) {
        final inValue = row['${shift}_in'] ?? '';
        final outValue = row['${shift}_out'] ?? '';
        if (_hasAttendanceValue(inValue) || _hasAttendanceValue(outValue)) {
          _setShiftPair(existing, shift, inValue, outValue);
        }
      }
    }

    for (final row in grouped.values) {
      row['total_minutes_late'] = _finalAttendanceValue(row);
    }

    return grouped.values.toList();
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

  String _extractEmployeeTitle(List<dynamic> row) {
    final nonEmpty = row
        .map((cell) => _normalizeCellValue(cell).trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (nonEmpty.length != 1) return '';

    final value = nonEmpty.first.replaceAll('\n', ' ').trim();
    if (!RegExp(r'\(\s*\d+\s*\)$').hasMatch(value)) return '';

    final lower = value.toLowerCase();
    if (lower.contains('total') ||
        lower.contains('pay period') ||
        lower.contains('employee')) {
      return '';
    }
    return value;
  }

  String _dateFromGroupedLabel(String label, String payPeriod) {
    final match = RegExp(r'^(\d{1,2})/(\d{1,2})').firstMatch(label.trim());
    if (match == null) return '';

    final yearMatch = RegExp(
      r'\b(\d{4})[-/]\d{1,2}[-/]\d{1,2}',
    ).firstMatch(payPeriod);
    final year = int.tryParse(yearMatch?.group(1) ?? '');
    final month = int.tryParse(match.group(1) ?? '');
    final day = int.tryParse(match.group(2) ?? '');
    if (year == null || month == null || day == null) return '';

    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  String _dayFromGroupedLabel(String label) {
    final match = RegExp(r'\(([A-Za-z]{3})\)').firstMatch(label);
    return match?.group(1)?.toUpperCase() ?? '';
  }

  List<Map<String, String>> _applySmartHeuristics(List<List<dynamic>> rawRows) {
    String currentEmployee = 'Unknown';
    String currentPayPeriod = 'NaN';
    String currentDate = 'NaN';
    String currentDay = 'NaN';
    final parsedRows = <Map<String, String>>[];

    for (var row in rawRows) {
      final employeeTitle = _extractEmployeeTitle(row);
      if (employeeTitle.isNotEmpty) {
        currentEmployee = employeeTitle;
        continue;
      }

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

      final groupedDate = row.isNotEmpty
          ? _normalizeCellValue(row[0]).trim()
          : '';
      final groupedWorkDate = _dateFromGroupedLabel(
        groupedDate,
        currentPayPeriod,
      );
      if (groupedWorkDate.isNotEmpty) {
        final groupedDay = _dayFromGroupedLabel(groupedDate);
        final shiftValues = {
          'morning_in': row.length > 1 ? _normalizeCellValue(row[1]) : 'NaN',
          'morning_out': row.length > 2 ? _normalizeCellValue(row[2]) : 'NaN',
          'afternoon_in': row.length > 3 ? _normalizeCellValue(row[3]) : 'NaN',
          'afternoon_out': row.length > 4 ? _normalizeCellValue(row[4]) : 'NaN',
          'overtime_in': row.length > 5 ? _normalizeCellValue(row[5]) : 'NaN',
          'overtime_out': row.length > 6 ? _normalizeCellValue(row[6]) : 'NaN',
        };
        final hasShiftValue = shiftValues.values.any(_hasAttendanceValue);
        final finalCell = row.length > 7 ? _normalizeCellValue(row[7]) : '';
        final absent =
            !hasShiftValue &&
            (finalCell.toLowerCase().contains('absent') ||
                finalCell.toLowerCase().contains('whole day') ||
                groupedDate.isNotEmpty);

        if (hasShiftValue || absent) {
          currentDate = groupedWorkDate;
          if (groupedDay.isNotEmpty) currentDay = groupedDay;
          parsedRows.add({
            'employee': currentEmployee,
            'pay_period': currentPayPeriod,
            'day': groupedDay.isNotEmpty ? groupedDay : currentDay,
            'date': groupedWorkDate,
            'in_time': shiftValues['morning_in'] ?? 'NaN',
            'out_time': shiftValues['morning_out'] ?? 'NaN',
            'work_time': 'NaN',
            'daily_total': 'NaN',
            'note': absent ? 'Absent' : 'NaN',
            ...shiftValues,
          });
          continue;
        }
      }

      List<String> times = [];
      String rowDate = '';
      String rowDay = '';
      List<String> texts = [];
      String workTime = 'NaN';
      String dailyTotal = 'NaN';

      final indexedDay = row.isNotEmpty
          ? _normalizeCellValue(row[0]).trim()
          : '';
      final indexedDate = row.length > 1
          ? _normalizeCellValue(row[1]).trim()
          : '';
      final indexedIn = row.length > 2
          ? _normalizeCellValue(row[2]).trim()
          : '';
      final indexedOut = row.length > 3
          ? _normalizeCellValue(row[3]).trim()
          : '';
      final indexedWork = row.length > 4
          ? _normalizeCellValue(row[4]).trim()
          : '';
      final indexedTotal = row.length > 5
          ? _normalizeCellValue(row[5]).trim()
          : '';
      final indexedNote = row.length > 6
          ? _normalizeCellValue(row[6]).trim()
          : '';
      final upperIndexedDay = indexedDay.toUpperCase();
      final hasIndexedDay = [
        'SUN',
        'MON',
        'TUE',
        'WED',
        'THU',
        'FRI',
        'SAT',
      ].contains(upperIndexedDay);
      final hasIndexedDate = RegExp(
        r'^\d{1,4}[-/]\d{1,2}[-/]\d{1,4}$',
      ).hasMatch(indexedDate);
      final hasIndexedPunch =
          _parseTimeToMinutes(indexedIn) != null ||
          _parseTimeToMinutes(indexedOut) != null;

      if (hasIndexedDay || hasIndexedDate || hasIndexedPunch) {
        if (hasIndexedDay) rowDay = upperIndexedDay;
        if (hasIndexedDate) rowDate = indexedDate;
        if (_parseTimeToMinutes(indexedIn) != null) times.add(indexedIn);
        if (_parseTimeToMinutes(indexedOut) != null) times.add(indexedOut);
        if (_hasAttendanceValue(indexedWork)) workTime = indexedWork;
        if (_hasAttendanceValue(indexedTotal)) dailyTotal = indexedTotal;
        if (_hasAttendanceValue(indexedNote)) texts.add(indexedNote);
      } else {
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
          if ([
            'SUN',
            'MON',
            'TUE',
            'WED',
            'THU',
            'FRI',
            'SAT',
          ].contains(upper)) {
            rowDay = upper;
            continue;
          }
          texts.add(val);
        }
      }

      if (rowDate.isNotEmpty) currentDate = rowDate;
      if (rowDay.isNotEmpty) currentDay = rowDay;

      if (rowDate.isEmpty && times.isNotEmpty) {
        rowDate = currentDate;
        rowDay = currentDay;
      }

      final noteText = texts.join(' | ');
      final isAbsentRow =
          noteText.toLowerCase().contains('absent') ||
          noteText.toLowerCase().contains('whole day');

      if (times.isNotEmpty || isAbsentRow || rowDate.isNotEmpty) {
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

        final shiftValues = _buildShiftValues(times);
        final note = texts.isNotEmpty
            ? texts.join(' | ')
            : (isAbsentRow || times.isEmpty ? 'Absent' : 'NaN');
        parsedRows.add({
          'employee': currentEmployee,
          'pay_period': currentPayPeriod,
          'day': rowDay.isNotEmpty ? rowDay : currentDay,
          'date': rowDate,
          'in_time': times.isNotEmpty ? times[0] : 'NaN',
          'out_time': times.length > 1 ? times[1] : 'NaN',
          'work_time': workTime,
          'daily_total': dailyTotal,
          'note': note,
          ...shiftValues,
        });
      }
    }
    final mergedRows = _mergeAttendanceRows(parsedRows);
    return mergedRows
        .map(
          (row) => {...row, 'total_minutes_late': _finalAttendanceValue(row)},
        )
        .toList();
  }

  Uint8List _convertRowsToXlsx(List<Map<String, String>> rows) {
    final workbook = excel.Excel.createExcel();
    final sheet = workbook['Sheet1'];
    if (sheet == null) return Uint8List(0);

    // ==========================================
    // ATTENDANCE EXPORT (Grouped Format)
    // ==========================================

    // 1. Group rows by employee
    final Map<String, List<Map<String, String>>> groupedRows = {};
    for (var row in rows) {
      final employee = row['employee'] ?? 'Unknown Employee';
      groupedRows.putIfAbsent(employee, () => []).add(row);
    }

    int currentRow = 0;
    final blackBorder = excel.Border(
      borderStyle: excel.BorderStyle.Thick,
      borderColorHex: excel.ExcelColor.fromHexString('#000000'),
    );

    excel.CellStyle printStyle({
      String background = '#FFFFFF',
      String fontColor = '#000000',
      int fontSize = 12,
    }) {
      return excel.CellStyle(
        backgroundColorHex: excel.ExcelColor.fromHexString(background),
        fontColorHex: excel.ExcelColor.fromHexString(fontColor),
        fontFamily: 'Arial',
        fontSize: fontSize,
        bold: true,
        textWrapping: excel.TextWrapping.Clip,
        horizontalAlign: excel.HorizontalAlign.Center,
        verticalAlign: excel.VerticalAlign.Center,
        leftBorder: blackBorder,
        rightBorder: blackBorder,
        topBorder: blackBorder,
        bottomBorder: blackBorder,
      );
    }

    final titleStyle = printStyle(background: '#9EA000', fontSize: 16);
    final headerStyle = printStyle(background: '#D9D9D9', fontSize: 11);
    final normalDataStyle = printStyle(fontSize: 11);
    final redTextStyle = printStyle(fontColor: '#FF0000', fontSize: 11);
    final yellowRedStyle = printStyle(
      background: '#FFFF00',
      fontColor: '#FF0000',
      fontSize: 11,
    );

    for (var entry in groupedRows.entries) {
      final employeeName = entry.key.toUpperCase();
      final employeeData = entry.value
        ..sort((a, b) {
          final aDate = _parseFlexibleDate(a['date'] ?? '') ?? DateTime(1970);
          final bDate = _parseFlexibleDate(b['date'] ?? '') ?? DateTime(1970);
          return aDate.compareTo(bDate);
        });

      // Row 1: Employee Title
      sheet.setRowHeight(currentRow, 24);
      sheet.merge(
        excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
        excel.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: currentRow),
      );
      for (int c = 0; c <= 7; c++) {
        sheet
                .cell(
                  excel.CellIndex.indexByColumnRow(
                    columnIndex: c,
                    rowIndex: currentRow,
                  ),
                )
                .cellStyle =
            titleStyle;
      }
      sheet.cell(
          excel.CellIndex.indexByColumnRow(
            columnIndex: 0,
            rowIndex: currentRow,
          ),
        )
        ..value = excel.TextCellValue(employeeName)
        ..cellStyle = titleStyle;
      currentRow++;

      // Row 2: Shift Headers (Morning, Afternoon, Overtime)
      sheet.setRowHeight(currentRow, 21);
      sheet.merge(
        excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow),
        excel.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentRow),
      );
      sheet.cell(
          excel.CellIndex.indexByColumnRow(
            columnIndex: 1,
            rowIndex: currentRow,
          ),
        )
        ..value = excel.TextCellValue('MORNING')
        ..cellStyle = headerStyle;
      sheet
              .cell(
                excel.CellIndex.indexByColumnRow(
                  columnIndex: 2,
                  rowIndex: currentRow,
                ),
              )
              .cellStyle =
          headerStyle;

      sheet.merge(
        excel.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow),
        excel.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentRow),
      );
      sheet.cell(
          excel.CellIndex.indexByColumnRow(
            columnIndex: 3,
            rowIndex: currentRow,
          ),
        )
        ..value = excel.TextCellValue('AFTERNOON')
        ..cellStyle = headerStyle;
      sheet
              .cell(
                excel.CellIndex.indexByColumnRow(
                  columnIndex: 4,
                  rowIndex: currentRow,
                ),
              )
              .cellStyle =
          headerStyle;

      sheet.merge(
        excel.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow),
        excel.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow),
      );
      sheet.cell(
          excel.CellIndex.indexByColumnRow(
            columnIndex: 5,
            rowIndex: currentRow,
          ),
        )
        ..value = excel.TextCellValue('OVERTIME')
        ..cellStyle = headerStyle;
      sheet
              .cell(
                excel.CellIndex.indexByColumnRow(
                  columnIndex: 6,
                  rowIndex: currentRow,
                ),
              )
              .cellStyle =
          headerStyle;

      sheet.cell(
          excel.CellIndex.indexByColumnRow(
            columnIndex: 7,
            rowIndex: currentRow,
          ),
        )
        ..value = excel.TextCellValue('TOTAL MINUTES LATE')
        ..cellStyle = headerStyle;

      sheet
              .cell(
                excel.CellIndex.indexByColumnRow(
                  columnIndex: 0,
                  rowIndex: currentRow,
                ),
              )
              .cellStyle =
          headerStyle;
      currentRow++;

      // Row 3: IN/OUT Headers
      sheet.setRowHeight(currentRow, 21);
      sheet.cell(
          excel.CellIndex.indexByColumnRow(
            columnIndex: 0,
            rowIndex: currentRow,
          ),
        )
        ..value = excel.TextCellValue('DATE')
        ..cellStyle = headerStyle;

      for (int c = 1; c <= 6; c++) {
        sheet.cell(
            excel.CellIndex.indexByColumnRow(
              columnIndex: c,
              rowIndex: currentRow,
            ),
          )
          ..value = excel.TextCellValue(c % 2 != 0 ? 'IN' : 'OUT')
          ..cellStyle = headerStyle;
      }
      sheet
              .cell(
                excel.CellIndex.indexByColumnRow(
                  columnIndex: 7,
                  rowIndex: currentRow,
                ),
              )
              .cellStyle =
          headerStyle;
      currentRow++;

      // Data Rows
      for (var row in employeeData) {
        sheet.setRowHeight(currentRow, 23);
        String dateVal = row['date'] ?? '';
        String dayVal = row['day'] ?? '';
        String shortDate = dateVal;

        try {
          final parsedDate = DateTime.parse(dateVal.split('T')[0]);
          shortDate = '${parsedDate.month}/${parsedDate.day}';
        } catch (_) {}

        String displayDate = dayVal != 'NaN' && dayVal.isNotEmpty
            ? '$shortDate ($dayVal)'
            : shortDate;

        sheet.cell(
            excel.CellIndex.indexByColumnRow(
              columnIndex: 0,
              rowIndex: currentRow,
            ),
          )
          ..value = excel.TextCellValue(displayDate)
          ..cellStyle = normalDataStyle;

        sheet.cell(
            excel.CellIndex.indexByColumnRow(
              columnIndex: 1,
              rowIndex: currentRow,
            ),
          )
          ..value = excel.TextCellValue(
            _formatDisplayValue('morning_in', row['morning_in'] ?? ''),
          )
          ..cellStyle = normalDataStyle;
        sheet.cell(
            excel.CellIndex.indexByColumnRow(
              columnIndex: 2,
              rowIndex: currentRow,
            ),
          )
          ..value = excel.TextCellValue(
            _formatDisplayValue('morning_out', row['morning_out'] ?? ''),
          )
          ..cellStyle = normalDataStyle;

        sheet.cell(
            excel.CellIndex.indexByColumnRow(
              columnIndex: 3,
              rowIndex: currentRow,
            ),
          )
          ..value = excel.TextCellValue(
            _formatDisplayValue('afternoon_in', row['afternoon_in'] ?? ''),
          )
          ..cellStyle = normalDataStyle;
        sheet.cell(
            excel.CellIndex.indexByColumnRow(
              columnIndex: 4,
              rowIndex: currentRow,
            ),
          )
          ..value = excel.TextCellValue(
            _formatDisplayValue('afternoon_out', row['afternoon_out'] ?? ''),
          )
          ..cellStyle = normalDataStyle;
        sheet.cell(
            excel.CellIndex.indexByColumnRow(
              columnIndex: 5,
              rowIndex: currentRow,
            ),
          )
          ..value = excel.TextCellValue(
            _formatDisplayValue('overtime_in', row['overtime_in'] ?? ''),
          )
          ..cellStyle = normalDataStyle;
        sheet.cell(
            excel.CellIndex.indexByColumnRow(
              columnIndex: 6,
              rowIndex: currentRow,
            ),
          )
          ..value = excel.TextCellValue(
            _formatDisplayValue('overtime_out', row['overtime_out'] ?? ''),
          )
          ..cellStyle = normalDataStyle;

        final finalValue = row['total_minutes_late'] ?? '';
        final lateMinutes = int.tryParse(finalValue) ?? 0;
        final isHalfDay = finalValue.toLowerCase().contains('half');
        final isAbsent = finalValue.toLowerCase().contains('absent');
        String note = row['note'] ?? '';
        final noteLower = note.toLowerCase();
        final isWholeDay =
            isAbsent ||
            noteLower.contains('whole day') ||
            noteLower.contains('absent');
        final lateCell = sheet.cell(
          excel.CellIndex.indexByColumnRow(
            columnIndex: 7,
            rowIndex: currentRow,
          ),
        );
        lateCell.value = excel.TextCellValue(
          isWholeDay
              ? 'whole day'
              : isHalfDay
              ? 'half day'
              : lateMinutes > 0
              ? '$lateMinutes'
              : '',
        );
        lateCell.cellStyle = lateMinutes > 0 || isHalfDay || isWholeDay
            ? redTextStyle
            : normalDataStyle;

        if (isHalfDay) {
          lateCell.cellStyle = redTextStyle;
        }

        if (isWholeDay) {
          for (int c = 0; c <= 7; c++) {
            sheet
                    .cell(
                      excel.CellIndex.indexByColumnRow(
                        columnIndex: c,
                        rowIndex: currentRow,
                      ),
                    )
                    .cellStyle =
                yellowRedStyle;
          }
        } else if (isHalfDay) {
          sheet
                  .cell(
                    excel.CellIndex.indexByColumnRow(
                      columnIndex: 7,
                      rowIndex: currentRow,
                    ),
                  )
                  .cellStyle =
              redTextStyle;
        }

        currentRow++;
      }
      for (int c = 0; c <= 7; c++) {
        sheet
                .cell(
                  excel.CellIndex.indexByColumnRow(
                    columnIndex: c,
                    rowIndex: currentRow,
                  ),
                )
                .cellStyle =
            normalDataStyle;
      }
      currentRow++;
    }

    sheet.setColumnWidth(0, 15.5);
    for (int i = 1; i <= 6; i++) {
      sheet.setColumnWidth(i, 12.0);
    }
    sheet.setColumnWidth(7, 24.0);

    return Uint8List.fromList(workbook.encode() ?? []);
  }
}
