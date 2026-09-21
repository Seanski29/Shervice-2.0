import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/enterprise_theme.dart';
import 'enterprise_states.dart';
import '../../widgets/interface/universal_pagination.dart';

typedef EnterpriseCellChanged<T> = Future<void> Function(T row, String value);

class EnterpriseGridColumn<T> {
  const EnterpriseGridColumn({
    required this.label,
    required this.value,
    this.width = 150,
    this.editable = false,
    this.onChanged,
    this.compare,
    this.cellBuilder,
  });

  final String label;
  final String Function(T row) value;
  final double width;
  final bool editable;
  final EnterpriseCellChanged<T>? onChanged;
  final int Function(T first, T second)? compare;
  final Widget Function(BuildContext context, T row)? cellBuilder;
}

class EnterpriseDataGrid<T> extends StatefulWidget {
  const EnterpriseDataGrid({
    super.key,
    required this.rows,
    required this.columns,
    required this.rowKey,
    required this.emptyTitle,
    required this.emptyMessage,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.loading = false,
    this.onDelete,
    this.canDelete,
    this.onExportSelection,
    this.onBulkDelete,
    this.filterFields = const [],
    this.showDateRange = true,
    this.height = 560,
    this.paginate = true,
  });

  final List<T> rows;
  final List<EnterpriseGridColumn<T>> columns;
  final Object Function(T row) rowKey;
  final bool loading;
  final String emptyTitle;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final Future<void> Function(T row)? onDelete;
  final bool Function(T row)? canDelete;
  final Future<void> Function(List<T> rows)? onExportSelection;
  final Future<void> Function(List<T> rows)? onBulkDelete;
  final List<Widget> filterFields;
  final bool showDateRange;
  final double height;
  final bool paginate;

  @override
  State<EnterpriseDataGrid<T>> createState() => _EnterpriseDataGridState<T>();
}

class _EnterpriseDataGridState<T> extends State<EnterpriseDataGrid<T>> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final Map<String, FocusNode> _focusNodes = {};
  final Set<Object> _selectedKeys = {};
  static const double _minZoom = 0.5;
  static const double _maxZoom = 1;
  static const double _zoomStep = 0.1;
  double _zoom = _maxZoom;
  int? _sortColumn;
  bool _sortAscending = true;
  DateTimeRange? _dateRange;
  int _currentPage = 0;
  static const int _rowsPerPage = 10;

  double _columnWidth(
    EnterpriseGridColumn<T> column, {
    double extraWidth = 0,
  }) => (column.width * _zoom) + extraWidth;

  List<T> get _sortedRows {
    final rows = [...widget.rows];
    final sortColumn = _sortColumn;
    if (sortColumn == null) return rows;
    final column = widget.columns[sortColumn];
    rows.sort((first, second) {
      final result =
          column.compare?.call(first, second) ??
          column.value(first).compareTo(column.value(second));
      return _sortAscending ? result : -result;
    });
    return rows;
  }

  List<T> _visibleRows(List<T> rows) {
    if (!widget.paginate) return rows;
    final totalPages = (rows.length / _rowsPerPage).ceil();
    if (totalPages == 0) return const [];
    if (_currentPage >= totalPages) _currentPage = totalPages - 1;
    final start = _currentPage * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  @override
  void didUpdateWidget(covariant EnterpriseDataGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rows.length != widget.rows.length ||
        oldWidget.paginate != widget.paginate) {
      final totalPages = (widget.rows.length / _rowsPerPage).ceil();
      if (totalPages == 0) {
        _currentPage = 0;
      } else if (_currentPage >= totalPages) {
        _currentPage = totalPages - 1;
      }
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return EnterpriseTableSkeleton(columns: widget.columns.length + 1);
    }

    final theme = Theme.of(context);
    final allRows = _sortedRows;
    final rows = _visibleRows(allRows);
    final selectedRows = allRows
        .where((row) => _selectedKeys.contains(widget.rowKey(row)))
        .toList();
    final totalWidth =
        78.0 +
        widget.columns.fold<double>(
          0,
          (sum, column) => sum + _columnWidth(column),
        );
    final totalHeight = 40.0 + (rows.length * 42.0);
    final footerHeight = widget.paginate && allRows.isNotEmpty ? 60.0 : 36.0;
    final tableHeight = widget.rows.isEmpty
        ? (widget.height.isFinite ? widget.height : 260.0)
        : widget.height.isFinite
        ? widget.height
        : 46.0 + totalHeight + footerHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : totalWidth;
        final contentWidth = totalWidth > viewportWidth
            ? totalWidth
            : viewportWidth;
        final extraColumnWidth = widget.columns.isEmpty
            ? 0.0
            : (contentWidth - totalWidth) / widget.columns.length;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: contentWidth,
              height: tableHeight,
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildToolbar(theme),
                  Expanded(
                    child: widget.rows.isEmpty
                        ? EnterpriseEmptyState(
                            icon: Icons.table_rows_outlined,
                            title: widget.emptyTitle,
                            message: widget.emptyMessage,
                            actionLabel: widget.emptyActionLabel,
                            onAction: widget.onEmptyAction,
                          )
                        : Scrollbar(
                            controller: _verticalController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _verticalController,
                              child: Scrollbar(
                                controller: _horizontalController,
                                thumbVisibility: true,
                                trackVisibility: true,
                                interactive: true,
                                notificationPredicate: (notification) =>
                                    notification.metrics.axis ==
                                    Axis.horizontal,
                                child: SingleChildScrollView(
                                  controller: _horizontalController,
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: contentWidth,
                                    height: totalHeight,
                                    child: Column(
                                      children: [
                                        _buildHeader(
                                          theme,
                                          contentWidth,
                                          extraColumnWidth,
                                        ),
                                        for (
                                          var rowIndex = 0;
                                          rowIndex < rows.length;
                                          rowIndex++
                                        )
                                          _buildRow(
                                            theme,
                                            rows[rowIndex],
                                            rowIndex,
                                            contentWidth,
                                            extraColumnWidth,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  if (widget.rows.isNotEmpty) _buildFooter(allRows.length),
                ],
              ),
            ),
            if (selectedRows.isNotEmpty)
              Positioned(
                left: 24,
                right: 24,
                bottom: 22,
                child: _buildBulkBar(selectedRows),
              ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.start, // Anchors to the Top-Left perfectly
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...widget.filterFields,
          if (widget.showDateRange)
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_outlined, size: 17),
              label: Text(
                _dateRange == null
                    ? 'Date range'
                    : '${_shortDate(_dateRange!.start)} - ${_shortDate(_dateRange!.end)}',
              ),
            ),
          if (_dateRange != null)
            IconButton(
              onPressed: () => setState(() => _dateRange = null),
              tooltip: 'Clear date range',
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
          const SizedBox(width: 4),
          _buildZoomControl(theme),
        ],
      ),
    );
  }

  Widget _buildZoomControl(ThemeData theme) {
    final canZoomOut = _zoom > _minZoom;
    final canZoomIn = _zoom < _maxZoom;
    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: Icons.remove,
            tooltip: 'Zoom out',
            enabled: canZoomOut,
            onPressed: canZoomOut
                ? () => setState(
                    () => _zoom = (_zoom - _zoomStep)
                        .clamp(_minZoom, _maxZoom)
                        .toDouble(),
                  )
                : null,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 46),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              '${(_zoom * 100).round()}%',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _ZoomButton(
            icon: Icons.add,
            tooltip: 'Zoom in',
            enabled: canZoomIn,
            onPressed: canZoomIn
                ? () => setState(
                    () => _zoom = (_zoom + _zoomStep)
                        .clamp(_minZoom, _maxZoom)
                        .toDouble(),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    double totalWidth,
    double extraColumnWidth,
  ) {
    final allSelected = _selectedKeys.length == widget.rows.length;
    return Container(
      width: totalWidth,
      height: 40,
      color: theme.cardColor,
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  tristate: _selectedKeys.isNotEmpty && !allSelected,
                  onChanged: (value) {
                    setState(() {
                      _selectedKeys.clear();
                      if (value == true) {
                        _selectedKeys.addAll(widget.rows.map(widget.rowKey));
                      }
                    });
                  },
                ),
                Text('#', style: TextStyle(color: theme.colorScheme.onSurface)),
              ],
            ),
          ),
          for (var index = 0; index < widget.columns.length; index++)
            InkWell(
              onTap: () => _sortBy(index),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: _columnWidth(
                    widget.columns[index],
                    extraWidth: extraColumnWidth,
                  ),
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: theme.dividerColor)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.columns[index].label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _sortColumn == index
                            ? (_sortAscending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward)
                            : Icons.unfold_more,
                        size: 14,
                        color: _sortColumn == index
                            ? EnterpriseColors.primary
                            : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(
    ThemeData theme,
    T row,
    int rowIndex,
    double totalWidth,
    double extraColumnWidth,
  ) {
    final key = widget.rowKey(row);
    final selected = _selectedKeys.contains(key);
    return Container(
      width: totalWidth,
      height: 42,
      color: selected
          ? EnterpriseColors.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: Row(
        children: [
          _GridRowNumber(
            number: rowIndex + 1,
            selected: selected,
            canDelete:
                widget.onDelete != null &&
                (widget.canDelete?.call(row) ?? true),
            onSelected: (value) {
              setState(() {
                if (value) {
                  _selectedKeys.add(key);
                } else {
                  _selectedKeys.remove(key);
                }
              });
            },
            onDelete: widget.onDelete == null
                ? null
                : () => _confirmRowDelete(row),
          ),
          for (
            var columnIndex = 0;
            columnIndex < widget.columns.length;
            columnIndex++
          )
            _buildCell(theme, row, rowIndex, columnIndex, extraColumnWidth),
        ],
      ),
    );
  }

  Widget _buildCell(
    ThemeData theme,
    T row,
    int rowIndex,
    int columnIndex,
    double extraColumnWidth,
  ) {
    final column = widget.columns[columnIndex];
    final node = _focusNodes.putIfAbsent(
      '$rowIndex:$columnIndex',
      () => FocusNode(debugLabel: 'grid-$rowIndex-$columnIndex'),
    );
    return Focus(
      focusNode: node,
      onKeyEvent: (focusNode, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _focusCell(rowIndex, columnIndex + 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _focusCell(rowIndex, columnIndex - 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _focusCell(rowIndex + 1, columnIndex);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _focusCell(rowIndex - 1, columnIndex);
          return KeyEventResult.handled;
        }
        if ((event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.f2) &&
            column.editable) {
          _editCell(row, column);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (cellContext) {
          final focused = Focus.of(cellContext).hasFocus;
          return InkWell(
            onTap: node.requestFocus,
            onDoubleTap: column.editable ? () => _editCell(row, column) : null,
            child: Container(
              width: _columnWidth(column, extraWidth: extraColumnWidth),
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: focused
                    ? EnterpriseColors.primary.withValues(alpha: 0.1)
                    : null,
                border: Border(
                  left: BorderSide(color: theme.dividerColor),
                  bottom: BorderSide(color: theme.dividerColor),
                  top: focused
                      ? const BorderSide(
                          color: EnterpriseColors.primary,
                          width: 2,
                        )
                      : BorderSide.none,
                  right: focused
                      ? const BorderSide(
                          color: EnterpriseColors.primary,
                          width: 2,
                        )
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child:
                        column.cellBuilder?.call(context, row) ??
                        Text(
                          column.value(row),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                  ),
                  if (column.editable)
                    const Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: EnterpriseColors.information,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter(int rowCount) {
    final totalPages = (rowCount / _rowsPerPage).ceil();
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          if (widget.paginate && rowCount > 0)
            Expanded(
              child: UniversalPagination(
                currentPage: _currentPage,
                totalPages: totalPages,
                totalItems: rowCount,
                itemsPerPage: _rowsPerPage,
                itemName: 'rows',
                onPrevPage: _currentPage > 0
                    ? () => setState(() => _currentPage--)
                    : null,
                onNextPage: _currentPage < totalPages - 1
                    ? () => setState(() => _currentPage++)
                    : null,
              ),
            )
          else
            Text(
              '$rowCount rows',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (!widget.paginate || rowCount == 0) const Spacer(),
          Text(
            'Arrow keys move cells | Tab advances | F2 edits',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildBulkBar(List<T> selectedRows) {
    return Material(
      elevation: 8,
      color: EnterpriseColors.darkSurface,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${selectedRows.length} selected',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            if (widget.onExportSelection != null)
              OutlinedButton.icon(
                onPressed: () => widget.onExportSelection!(selectedRows),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Export selection'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF667085)),
                ),
              ),
            if (widget.onBulkDelete != null) ...[
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: () => _confirmBulkDelete(selectedRows),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Bulk delete'),
                style: FilledButton.styleFrom(
                  backgroundColor: EnterpriseColors.danger,
                ),
              ),
            ],
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => setState(_selectedKeys.clear),
              tooltip: 'Clear selection',
              icon: const Icon(Icons.close, color: Colors.white, size: 17),
            ),
          ],
        ),
      ),
    );
  }

  void _sortBy(int index) {
    setState(() {
      if (_sortColumn == index) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = index;
        _sortAscending = true;
      }
    });
  }

  void _focusCell(int row, int column) {
    if (row < 0 || row >= widget.rows.length) return;
    if (column < 0 || column >= widget.columns.length) return;
    _focusNodes['$row:$column']?.requestFocus();
  }

  Future<void> _editCell(T row, EnterpriseGridColumn<T> column) async {
    if (!column.editable || column.onChanged == null) return;
    final controller = TextEditingController(text: column.value(row));
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${column.label}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: column.label,
            helperText: 'Enter a valid value, then select Update.',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    await column.onChanged!(row, value);
    if (mounted) EnterpriseToasts.success(context, '${column.label} updated.');
  }

  Future<void> _confirmRowDelete(T row) async {
    final confirmed = await _showDestructiveConfirmation(
      title: 'Delete this record?',
      message: 'This permanently removes the selected master record.',
      confirmationText: 'DELETE',
    );
    if (!confirmed || widget.onDelete == null) return;
    try {
      await widget.onDelete!(row);
      if (mounted) EnterpriseToasts.success(context, 'Record deleted.');
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        EnterpriseToasts.error(context, 'Delete failed: $message');
      }
    }
  }

  Future<void> _confirmBulkDelete(List<T> rows) async {
    final confirmed = await _showDestructiveConfirmation(
      title: 'Delete ${rows.length} records?',
      message: 'This permanently removes every selected master record.',
      confirmationText: 'DELETE ${rows.length}',
    );
    if (!confirmed || widget.onBulkDelete == null) return;
    try {
      await widget.onBulkDelete!(rows);
      if (!mounted) return;
      setState(_selectedKeys.clear);
      EnterpriseToasts.success(context, '${rows.length} records deleted.');
    } catch (error) {
      if (mounted) {
        EnterpriseToasts.error(
          context,
          'The selected records could not be deleted. ${error.toString()}',
        );
      }
    }
  }

  Future<bool> _showDestructiveConfirmation({
    required String title,
    required String message,
    required String confirmationText,
  }) async {
    final controller = TextEditingController();
    var valid = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                onChanged: (value) => setDialogState(
                  () => valid = value.trim() == confirmationText,
                ),
                decoration: InputDecoration(
                  labelText: 'Type $confirmationText to confirm',
                  helperText:
                      'This confirmation prevents accidental data loss.',
                  errorText: controller.text.isNotEmpty && !valid
                      ? 'Confirmation text does not match.'
                      : null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: EnterpriseColors.danger,
              ),
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return confirmed ?? false;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _dateRange,
    );
    if (result != null) setState(() => _dateRange = result);
  }

  String _shortDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 32,
          height: 30,
          child: Icon(
            icon,
            size: 16,
            color: enabled
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).disabledColor,
          ),
        ),
      ),
    );
  }
}

class _GridRowNumber extends StatefulWidget {
  const _GridRowNumber({
    required this.number,
    required this.selected,
    required this.canDelete,
    required this.onSelected,
    required this.onDelete,
  });

  final int number;
  final bool selected;
  final bool canDelete;
  final ValueChanged<bool> onSelected;
  final VoidCallback? onDelete;

  @override
  State<_GridRowNumber> createState() => _GridRowNumberState();
}

class _GridRowNumberState extends State<_GridRowNumber> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: 78,
        height: 42,
        decoration: BoxDecoration(
          color: _hovered
              ? EnterpriseColors.danger.withValues(alpha: 0.08)
              : null,
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: widget.selected,
              onChanged: (v) => widget.onSelected(v ?? false),
            ),
            Expanded(
              child: _hovered && widget.canDelete
                  ? IconButton(
                      onPressed: widget.onDelete,
                      tooltip: 'Delete row ${widget.number}',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: EnterpriseColors.danger,
                      ),
                    )
                  : Text(
                      '${widget.number}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}