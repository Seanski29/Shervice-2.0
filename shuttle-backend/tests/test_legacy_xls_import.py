import io

import pytest
import xlwt

from roles.admin import _attendance_payload_from_row, parse_legacy_xls_bytes


def test_parse_legacy_xls_bytes_reads_rows_and_writes_xlsx():
    workbook = xlwt.Workbook()
    sheet = workbook.add_sheet('Attendance')
    sheet.write(0, 0, 'Employee ID')
    sheet.write(0, 1, 'Employee Name')
    sheet.write(0, 2, 'Date')
    sheet.write(0, 3, 'Time In')
    sheet.write(1, 0, '1001')
    sheet.write(1, 1, 'Juan Dela Cruz')
    sheet.write(1, 2, '2026-08-29')
    sheet.write(1, 3, '07:30')

    buffer = io.BytesIO()
    workbook.save(buffer)
    payload = buffer.getvalue()

    result = parse_legacy_xls_bytes(payload)

    assert result['success'] is True
    assert result['sheet_name'] == 'Attendance'
    assert result['row_count'] == 1
    assert result['headers'] == ['Employee ID', 'Employee Name', 'Date', 'Time In']
    assert result['rows'][0]['Employee ID'] == '1001'
    assert result['rows'][0]['Employee Name'] == 'Juan Dela Cruz'
    assert result['xlsx_bytes']


def test_attendance_payload_from_imported_row_normalizes_fields():
    row = {
        'employee': 'Juan Dela Cruz (1001)',
        'pay_period': '2026-08-01 - 2026-08-15',
        'day': 'MON',
        'date': '08/03/2026',
        'in_time': '07:30',
        'out_time': '17:05',
        'work_time': '8:00',
        'daily_total': '8:00',
        'note': 'On time',
    }

    payload = _attendance_payload_from_row(row, 'august.xls')

    assert payload['employee_name'] == 'Juan Dela Cruz'
    assert payload['employee_id'] == '1001'
    assert payload['work_date'] == '2026-08-03'
    assert payload['time_in'] == '07:30'
    assert payload['source_file'] == 'august.xls'
    assert payload['raw_payload'] == row
