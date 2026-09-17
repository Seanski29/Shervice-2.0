import io

import pytest
import xlwt

from roles.admin import parse_legacy_xls_bytes


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
