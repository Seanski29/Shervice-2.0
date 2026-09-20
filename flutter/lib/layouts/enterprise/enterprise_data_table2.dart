import 'package:data_table_2/data_table_2.dart' as dt2;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' as mui;

import '../../theme/enterprise_theme.dart';
import 'enterprise_states.dart';

class EnterpriseTableColumn<T> {
  const EnterpriseTableColumn({
    required this.label,
    required this.value,
    this.numeric = false,
  });

  final String label;
  final String Function(T row) value;
  final bool numeric;
}

class EnterpriseDataTable2<T> extends StatefulWidget {
  const EnterpriseDataTable2({
    super.key,
    required this.rows,
    required this.columns,
    required this.rowKey,
    this.onDelete,
    this.onEdit,
    this.onExport,
    this.onBulkDelete,
    this.height = 360,
    this.loading = false,
    this.emptyTitle = 'Nothing to display yet',
    this.emptyMessage = 'Add a record to see it appear in this workspace.',
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  final List<T> rows;
  final List<EnterpriseTableColumn<T>> columns;
  final Object Function(T row) rowKey;
  final Future<void> Function(T row)? onDelete;
  final Future<void> Function(T row)? onEdit;
  final Future<void> Function(List<T> rows)? onExport;
  final Future<void> Function(List<T> rows)? onBulkDelete;
  final double height;
  final bool loading;
  final String emptyTitle;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  @override
  State<EnterpriseDataTable2<T>> createState() => _EnterpriseDataTable2State<T>();
}

class _EnterpriseDataTable2State<T> extends State<EnterpriseDataTable2<T>> {
  final Set<Object> _selected = {};
  final Map<int, FocusNode> _focusNodes = {};
  final FocusNode _tableFocus = FocusNode();
  double _zoom = 1;
  int _activeRow = 0;
  int _activeColumn = 0;
  int? _hoveredRow;

  List<T> get _selectedRows => widget.rows
      .where((row) => _selected.contains(widget.rowKey(row)))
      .toList();

  @override
  void dispose() {
    _tableFocus.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _focusNode(int index) =>
      _focusNodes.putIfAbsent(index, FocusNode.new);

  void _move(int rowDelta, int columnDelta) {
    if (widget.rows.isEmpty || widget.columns.isEmpty) return;
    setState(() {
      _activeRow = (_activeRow + rowDelta).clamp(0, widget.rows.length - 1);
      _activeColumn =
          (_activeColumn + columnDelta).clamp(0, widget.columns.length - 1);
    });
    _focusNode(_activeRow * widget.columns.length + _activeColumn).requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _move(1, 0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _move(-1, 0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _move(0, 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _move(0, -1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _runMutation(
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (mounted) EnterpriseToasts.success(context, successMessage);
    } catch (error) {
      if (mounted) EnterpriseToasts.error(context, 'Action failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedRows = _selectedRows;
    final table = Focus(
      focusNode: _tableFocus,
      onKeyEvent: _handleKey,
      child: dt2.DataTable2(
        minWidth: _tableWidth(context),
        columnSpacing: 0,
        horizontalMargin: 0,
        headingRowHeight: 36,
        dataRowHeight: 38,
        headingRowColor: WidgetStatePropertyAll(theme.cardColor),
        headingTextStyle: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        columns: [
          const dt2.DataColumn2(label: Text(''), fixedWidth: 36),
          for (final column in widget.columns)
            dt2.DataColumn2(
              label: Text(column.label),
              numeric: column.numeric,
              size: dt2.ColumnSize.M,
            ),
          const dt2.DataColumn2(label: Text('Record actions'), fixedWidth: 150),
        ],
        rows: [
          for (var rowIndex = 0; rowIndex < widget.rows.length; rowIndex++)
            _buildRow(context, rowIndex, widget.rows[rowIndex]),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedRows.isNotEmpty)
          Material(
            color: EnterpriseColors.main,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Text(
                    '${selectedRows.length} selected',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: widget.onExport == null
                        ? null
                        : () => _runMutation(
                            () => widget.onExport!(selectedRows),
                            '${selectedRows.length} records exported.',
                          ),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export'),
                  ),
                  TextButton.icon(
                    onPressed: widget.onBulkDelete == null
                        ? null
                        : () => _runMutation(
                            () => widget.onBulkDelete!(selectedRows),
                            '${selectedRows.length} records deleted.',
                          ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Bulk delete'),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
            IconButton(
              tooltip: 'Zoom out',
              onPressed: _zoom <= 0.7
                  ? null
                  : () => setState(() => _zoom -= 0.1),
              icon: const Icon(Icons.zoom_out),
            ),
            Text('${(_zoom * 100).round()}%'),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: _zoom >= 1.4
                  ? null
                  : () => setState(() => _zoom += 0.1),
              icon: const Icon(Icons.zoom_in),
            ),
            ],
          ),
        ),
        SizedBox(
          height: widget.height,
          child: widget.loading
              ? const EnterpriseTableSkeleton()
              : widget.rows.isEmpty
              ? EnterpriseEmptyState(
                  icon: Icons.table_rows_outlined,
                  title: widget.emptyTitle,
                  message: widget.emptyMessage,
                  actionLabel: widget.emptyActionLabel,
                  onAction: widget.onEmptyAction,
                )
              : Scrollbar(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: table,
                  ),
                ),
        ),
      ],
    );
  }

  mui.DataRow _buildRow(BuildContext context, int rowIndex, T row) {
    final key = widget.rowKey(row);
    final active = _selected.contains(key);
    final actionVisible = _hoveredRow == rowIndex;
    final cells = <mui.DataCell>[
      mui.DataCell(
        Checkbox(
          value: active,
          onChanged: (value) => setState(() {
            if (value == true) {
              _selected.add(key);
            } else {
              _selected.remove(key);
            }
          }),
        ),
      ),
      for (var columnIndex = 0;
          columnIndex < widget.columns.length;
          columnIndex++)
        mui.DataCell(
          Focus(
            focusNode: _focusNode(rowIndex * widget.columns.length + columnIndex),
            child: Text(widget.columns[columnIndex].value(row)),
          ),
        ),
      mui.DataCell(
        AnimatedOpacity(
          opacity: actionVisible ? 1 : 0,
          duration: const Duration(milliseconds: 100),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onEdit != null)
                OutlinedButton(
                  onPressed: actionVisible
                      ? () => _runMutation(
                          () => widget.onEdit!(row),
                          'Record updated successfully.',
                        )
                      : null,
                  child: const Text('Update'),
                ),
              if (widget.onDelete != null)
                OutlinedButton(
                  onPressed: actionVisible
                      ? () => _runMutation(
                          () => widget.onDelete!(row),
                          'Record deleted successfully.',
                        )
                      : null,
                  child: const Text('Delete'),
                ),
            ],
          ),
        ),
      ),
    ];
    return dt2.DataRow2(
      color: WidgetStateProperty.resolveWith(
        (states) => rowIndex.isEven
            ? EnterpriseColors.white
            : EnterpriseColors.lightSurfaceMuted,
      ),
      selected: active,
      onHover: (hovered) => setState(
        () => _hoveredRow = hovered ? rowIndex : null,
      ),
      onSelectChanged: (value) => setState(() {
        if (value == true) {
          _selected.add(key);
        } else {
          _selected.remove(key);
        }
      }),
      cells: [
        cells.first,
        ...cells.skip(1).take(widget.columns.length),
        mui.DataCell(
          cells.last.child,
        ),
      ],
    );
  }

  double _tableWidth(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final painter = TextPainter(textDirection: TextDirection.ltr);
    var width = 36.0 + 72.0;
    for (final column in widget.columns) {
      var maxWidth = painter
        ..text = TextSpan(text: column.label, style: textStyle);
      maxWidth.layout();
      var columnWidth = maxWidth.width;
      for (final row in widget.rows) {
        painter.text = TextSpan(text: column.value(row), style: textStyle);
        painter.layout();
        columnWidth = columnWidth > painter.width ? columnWidth : painter.width;
      }
      width += (columnWidth + 16) * _zoom;
    }
    return width;
  }
}
