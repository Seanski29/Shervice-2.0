import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constant.dart';

/// Formatting and parsing utilities for timecard/attendance data
/// Shared across admin and staff views

String getDayOfWeek(DateTime date) {
  const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  return days[date.weekday - 1];
}

String formatTableHeader(String value) {
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

  final words = cleaned.split(' ');
  return words
      .map((word) {
        if (word.isEmpty) return '';
        final lowerWord = word.toLowerCase();
        if (lowerWord == 'id' || lowerWord == 'ids') return 'ID';
        if (word.length <= 2) return lowerWord.toUpperCase();
        return lowerWord[0].toUpperCase() + lowerWord.substring(1);
      })
      .join(' ');
}

String formatTimeValue(String val) {
  if (val.isEmpty || val == 'null' || val == 'NaN') return '-';
  final amPmRegex = RegExp(r'^\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)$');
  if (amPmRegex.hasMatch(val.trim())) return val.trim().toUpperCase();

  try {
    final parsed = DateTime.parse(val);
    return formatDateTimeToTime(parsed);
  } catch (_) {}

  try {
    final parts = val.trim().split(' ');
    if (parts.length == 2) {
      final timeParts = parts[1].split(':');
      if (timeParts.length >= 2) {
        return formatHoursMinutes(
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
      }
    }
  } catch (_) {}

  try {
    final parts = val.trim().split(':');
    if (parts.length >= 2) {
      return formatHoursMinutes(int.parse(parts[0]), int.parse(parts[1]));
    }
  } catch (_) {}

  return val;
}

String formatDateTimeToTime(DateTime dt) =>
    formatHoursMinutes(dt.hour, dt.minute);

String formatHoursMinutes(int hour, int minute) {
  final ampm = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  final displayMin = minute.toString().padLeft(2, '0');
  return '${displayHour.toString().padLeft(2, '0')}:$displayMin $ampm';
}

String formatDurationValue(String val) {
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

String formatDateValue(String val) {
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
      return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
    }
    return cleanDate;
  } catch (_) {
    return val;
  }
}

String normalizeCellValue(dynamic value) {
  if (value == null) return '';
  if (value is DateTime) return value.toIso8601String();
  if (value is num) return value.toString();
  if (value is Map)
    return value.entries
        .map((entry) => '${entry.key}: ${normalizeCellValue(entry.value)}')
        .join(', ');
  if (value is Iterable)
    return value.map((item) => normalizeCellValue(item)).join(', ');
  return value.toString().trim();
}

/// DataTableSource for timecard/attendance display
class TimecardDataSource extends DataTableSource {
  TimecardDataSource({required this.columns, required this.rows});

  final List<String> columns;
  final List<Map<String, String>> rows;

  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;

    final row = rows[index];
    return DataRow(
      cells: columns.map((column) {
        String rawValue = row[column] ?? '';
        String displayValue = rawValue;

        if (column == 'in_time' || column == 'out_time')
          displayValue = formatTimeValue(rawValue);
        else if (column == 'work_time' || column == 'daily_total')
          displayValue = formatDurationValue(rawValue);
        else if (column == 'date')
          displayValue = formatDateValue(rawValue);
        else if (column == 'day')
          displayValue = displayValue.toUpperCase();

        return DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 180),
            child: Text(
              displayValue,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => rows.length;

  @override
  int get selectedRowCount => 0;
}

/// File parsing utilities
List<List<dynamic>> extractRawRows(Uint8List bytes, bool isCsv) {
  List<List<dynamic>> rawRows = [];
  if (isCsv) {
    final content = utf8.decode(bytes);
    final lines = const LineSplitter().convert(content);
    for (var line in lines) {
      List<String> values = [];
      StringBuffer buffer = StringBuffer();
      bool inQuotes = false;
      for (int i = 0; i < line.length; i++) {
        if (line[i] == '"') {
          if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            inQuotes = !inQuotes;
          }
        } else if (line[i] == ',' && !inQuotes) {
          values.add(buffer.toString());
          buffer.clear();
        } else {
          buffer.write(line[i]);
        }
      }
      values.add(buffer.toString());
      rawRows.add(values);
    }
  } else {
    final workbook = excel.Excel.decodeBytes(bytes);
    if (workbook.tables.isNotEmpty) {
      final sheet = workbook.tables[workbook.tables.keys.first]!;
      rawRows = sheet.rows;
    }
  }
  return rawRows;
}

Future<List<List<dynamic>>> convertLegacyXlsDirectly(
  Uint8List fileBytes,
  String fileName,
  String endpoint,
) async {
  try {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$backendUrl$endpoint'),
    );
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) return [];

    final decoded = jsonDecode(response.body);
    final rows = decoded['rows'] as List<dynamic>? ?? const [];
    return rows
        .map<List<dynamic>>((row) => (row as Map).values.toList())
        .toList();
  } catch (_) {
    return [];
  }
}

/// Smart biometric data parser that handles missing dates/names
List<Map<String, String>> applySmartHeuristics(List<List<dynamic>> rawRows) {
  String currentEmployee = 'Unknown';
  String currentPayPeriod = 'NaN';
  String currentDate = 'NaN';
  String currentDay = 'NaN';

  final parsedRows = <Map<String, String>>[];

  for (var row in rawRows) {
    bool hasEmployeeLabel = false;
    bool hasPayPeriodLabel = false;

    // 1. Check for headers/labels in the current row
    for (int c = 0; c < row.length; c++) {
      String val = normalizeCellValue(row[c]).trim();
      String lowerVal = val.toLowerCase();

      if (lowerVal == 'employee' || lowerVal == 'name') hasEmployeeLabel = true;
      if (lowerVal.contains('pay period')) hasPayPeriodLabel = true;

      if (RegExp(
        r'\d{2,4}[-/]\d{1,2}[-/]\d{1,4}.*?\d{2,4}[-/]\d{1,2}[-/]\d{1,4}',
      ).hasMatch(val)) {
        currentPayPeriod = val;
      }
    }

    // 2. Update active employee if found on this row
    if (hasEmployeeLabel) {
      for (int c = 0; c < row.length; c++) {
        String val = normalizeCellValue(row[c]).trim();
        String lowerVal = val.toLowerCase();
        if (val.isNotEmpty && lowerVal != 'employee' && lowerVal != 'name') {
          currentEmployee = val;
          break;
        }
      }
    }

    // 3. Update active pay period if found on this row
    if (hasPayPeriodLabel) {
      for (int c = 0; c < row.length; c++) {
        String val = normalizeCellValue(row[c]).trim();
        String lowerVal = val.toLowerCase();
        if (val.isNotEmpty && !lowerVal.contains('pay period')) {
          currentPayPeriod = val;
          break;
        }
      }
    }

    // 4. Extract Data (Times, Dates, Days)
    String rowDate = '';
    String rowDay = '';
    List<String> times = [];
    List<String> texts = [];

    for (var cell in row) {
      String val = normalizeCellValue(cell).trim();
      if (val.isEmpty) continue;

      bool isIsoDate =
          val.contains('T') && RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(val);
      if (isIsoDate) {
        final datePart = val.split('T')[0];
        final timePart = val.split('T').length > 1
            ? val.split('T')[1].substring(0, 5)
            : '';

        if (datePart == '1899-12-30' || datePart == '1899-12-31') {
          times.add(timePart);
          continue;
        } else if (timePart.isNotEmpty && timePart != '00:00') {
          rowDate = datePart;
          times.add(timePart);
          continue;
        } else {
          rowDate = datePart;
          continue;
        }
      }

      if (RegExp(r'^\d{1,4}[-/]\d{1,2}[-/]\d{1,4}$').hasMatch(val)) {
        rowDate = val;
        continue;
      }

      final upperVal = val.toUpperCase();
      if ([
        'SUN',
        'MON',
        'TUE',
        'WED',
        'THU',
        'FRI',
        'SAT',
      ].contains(upperVal)) {
        rowDay = upperVal;
        continue;
      }

      if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(val)) {
        times.add(val.substring(0, 5));
        continue;
      }
      texts.add(val);
    }

    // 5. The "Waterfall" Fix: Inherit missing dates/days from previous rows
    if (rowDate.isNotEmpty) currentDate = rowDate;
    if (rowDay.isNotEmpty) currentDay = rowDay;

    // If this row has times but the biometric machine left the date blank, inherit it!
    if (rowDate.isEmpty && times.isNotEmpty) {
      rowDate = currentDate;
      rowDay = currentDay;
    }

    // 6. Save the row if it contains actual timecard entries
    if (times.isNotEmpty) {
      String inTime = times.isNotEmpty ? times[0] : 'NaN';
      String outTime = times.length > 1 ? times[1] : 'NaN';
      String workTime = times.length > 2 ? times[2] : 'NaN';
      String dailyTotal = times.length > 3 ? times[3] : 'NaN';

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
              'File',
              'Timecard Report',
              'Column',
            ].contains(t) ||
            t == currentPayPeriod ||
            t == currentEmployee,
      );

      parsedRows.add({
        'employee': currentEmployee,
        'pay_period': currentPayPeriod,
        'day': rowDay.isNotEmpty ? rowDay : 'NaN',
        'date': rowDate.isNotEmpty ? rowDate : 'NaN',
        'in_time': inTime,
        'out_time': outTime,
        'work_time': workTime,
        'daily_total': dailyTotal,
        'note': texts.isNotEmpty ? texts.join(' | ') : 'NaN',
      });
    }
  }
  return parsedRows;
}

/// Row normalization from API response
List<Map<String, String>> normalizeTimecardRows(List<dynamic> rawList) {
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
      employeeName = (userAccount['full_name'] ?? userAccount['username'] ?? '')
          .toString();
    } else {
      employeeId = (map['employee_id'] ?? '').toString();
      employeeName = (map['employee_name'] ?? '').toString();
    }

    String dateStr = (map['date'] ?? map['work_date'] ?? '').toString();
    String inTime = (map['in_time'] ?? map['time_in'] ?? '').toString();
    String outTime = (map['out_time'] ?? map['time_out'] ?? '').toString();
    String workTime = (map['work_time'] ?? map['work_hours'] ?? '').toString();
    String dailyTotal = (map['daily_total'] ?? map['total_hours'] ?? '')
        .toString();
    String payPeriod = (map['pay_period'] ?? '').toString();
    String note = (map['note'] ?? map['notes'] ?? '').toString();
    String dayOfWeek = 'NaN';

    if (dateStr.isNotEmpty && dateStr != 'null') {
      try {
        final date = DateTime.parse(dateStr);
        dayOfWeek = getDayOfWeek(date);
      } catch (_) {
        dayOfWeek = 'NaN';
      }
    }

    normalized.add({
      'employee': employeeName.isNotEmpty && employeeId.isNotEmpty
          ? '$employeeName ($employeeId)'
          : (employeeName.isNotEmpty ? employeeName : 'Unknown'),
      'pay_period': payPeriod.isNotEmpty && payPeriod != 'null'
          ? payPeriod
          : 'NaN',
      'day': dayOfWeek,
      'date': dateStr.isNotEmpty && dateStr != 'null' ? dateStr : 'NaN',
      'in_time': inTime.isNotEmpty && inTime != 'null' ? inTime : 'NaN',
      'out_time': outTime.isNotEmpty && outTime != 'null' ? outTime : 'NaN',
      'work_time': workTime.isNotEmpty && workTime != 'null' ? workTime : 'NaN',
      'daily_total': dailyTotal.isNotEmpty && dailyTotal != 'null'
          ? dailyTotal
          : 'NaN',
      'note': note.isNotEmpty && note != 'null' ? note : 'NaN',
    });
  }
  return normalized;
}

/// Export rows to XLSX format
Uint8List convertRowsToXlsx(
  List<Map<String, String>> rows,
  List<String> columns,
) {
  final workbook = excel.Excel.createExcel();
  final sheet = workbook['Sheet1'];
  if (sheet == null) return Uint8List(0);

  final headerCells = columns
      .map((column) => excel.TextCellValue(formatTableHeader(column)))
      .toList();
  sheet.insertRowIterables(headerCells, 0);

  for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    final values = columns.map((column) {
      String rawValue = row[column] ?? '';
      String displayValue = rawValue;

      if (column == 'in_time' || column == 'out_time')
        displayValue = formatTimeValue(rawValue);
      else if (column == 'work_time' || column == 'daily_total')
        displayValue = formatDurationValue(rawValue);
      else if (column == 'date')
        displayValue = formatDateValue(rawValue);
      else if (column == 'day')
        displayValue = displayValue.toUpperCase();

      return excel.TextCellValue(displayValue);
    }).toList();
    sheet.insertRowIterables(values, rowIndex + 1);
  }

  final bytes = workbook.save();
  return bytes != null ? Uint8List.fromList(bytes) : Uint8List(0);
}

String escapeCsv(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

List<String> splitCsvLine(String line) {
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
