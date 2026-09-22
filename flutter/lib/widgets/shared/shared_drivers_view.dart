import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constant.dart';
import '../../layouts/enterprise/enterprise_theme.dart';
import '../../utils/file_download.dart';
import '../driver/driver_profile_model.dart';
import '../../layouts/enterprise/enterprise_data_grid.dart';
import '../../layouts/enterprise/enterprise_states.dart';

class SharedDriversView extends StatefulWidget {
  const SharedDriversView({
    super.key,
    required this.canManage,
    required this.title,
    required this.subtitle,
    this.actionWidget,
    this.onDriverTapped,
  });

  final bool canManage;
  final String title;
  final String subtitle;
  final Widget? actionWidget;
  final Function(BuildContext context, DriverProfileModel? driver)?
  onDriverTapped;

  @override
  State<SharedDriversView> createState() => SharedDriversViewState();
}

class SharedDriversViewState extends State<SharedDriversView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedStatusFilter = 'All';
  List<DriverProfileModel> _drivers = [];
  List<DriverProfileModel> _filteredDriversCache = [];

  @override
  void initState() {
    super.initState();
    _fetchDrivers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void refreshData() => _fetchDrivers();

  List<DriverProfileModel> get _filteredDrivers => _filteredDriversCache;

  void _rebuildFilteredDrivers() {
    final query = _searchQuery.trim().toLowerCase();
    _filteredDriversCache = _drivers.where((driver) {
      final matchesSearch =
          query.isEmpty ||
          driver.name.toLowerCase().contains(query) ||
          driver.id.toString().toLowerCase().contains(query);
      final matchesStatus =
          _selectedStatusFilter == 'All' ||
          driver.status.toLowerCase() == _selectedStatusFilter.toLowerCase();
      return matchesSearch && matchesStatus;
    }).toList();
  }

  Future<void> _fetchDrivers() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final response = await http
          .get(Uri.parse('$backendUrl/driver/all'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Request failed with status ${response.statusCode}.');
      }
      final data = jsonDecode(response.body);
      if (data['connection_status'] != 'SUCCESS') {
        throw Exception('The driver directory could not be synchronized.');
      }
      final rawList = data['sample_data_payload'] as List<dynamic>? ?? [];
      if (!mounted) return;
      final drivers = rawList
          .whereType<Map>()
          .map(
            (json) =>
                DriverProfileModel.fromJson(Map<String, dynamic>.from(json)),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _drivers = drivers;
        _rebuildFilteredDrivers();
      });
    } catch (error) {
      if (mounted) {
        EnterpriseToasts.error(context, 'Unable to load drivers: $error');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteDriver(DriverProfileModel driver) async {
    final response = await http
        .delete(Uri.parse('$backendUrl/auth/delete-driver/${driver.id}'))
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Unable to delete driver.');
    }
    await _fetchDrivers();
  }

  Future<void> _bulkDelete(List<DriverProfileModel> drivers) async {
    for (final driver in drivers) {
      await _deleteDriver(driver);
    }
  }

  Future<void> _exportDrivers(List<DriverProfileModel> drivers) async {
    final buffer = StringBuffer('Driver ID,Name,Phone,Status,Date Hired\n');
    for (final driver in drivers) {
      buffer.writeln(
        '${driver.id},"${_csv(driver.name)}","${_csv(driver.phoneNumber)}",'
        '"${_csv(driver.status)}",${driver.dateHired}',
      );
    }
    await downloadFileBytes(
      fileName: 'shervice-drivers.csv',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
    );
    if (mounted) {
      EnterpriseToasts.success(context, '${drivers.length} drivers exported.');
    }
  }

  String _csv(String value) => value.replaceAll('"', '""');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final drivers = _filteredDrivers;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. TOP ROW: Title on Left, Actions on Right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade400
                            : const Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.actionWidget != null) ...[
                      widget.actionWidget!,
                      const SizedBox(width: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _fetchDrivers,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 2. CARDS BEFORE FILTERS
            if (_isLoading)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 800;
                  if (isNarrow) {
                    return Column(
                      children: List.generate(
                        4,
                        (_) => const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: SizedBox(
                            height: 112,
                            width: double.infinity,
                            child: EnterpriseSummaryCardSkeleton(),
                          ),
                        ),
                      ),
                    );
                  }
                  return Row(
                    children: const [
                      Expanded(
                        child: SizedBox(
                          height: 112,
                          child: EnterpriseSummaryCardSkeleton(),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 112,
                          child: EnterpriseSummaryCardSkeleton(),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 112,
                          child: EnterpriseSummaryCardSkeleton(),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 112,
                          child: EnterpriseSummaryCardSkeleton(),
                        ),
                      ),
                    ],
                  );
                },
              )
            else
              _buildSummaryCards(isDark),

            const SizedBox(height: 15),

            // 3. FILTERS (Anchored Left)
            Align(
              alignment: Alignment.centerLeft,
              child: _buildFilters(isDark),
            ),

            const SizedBox(height: 10),

            // 4. MAIN WORKSPACE TABLE
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Expanded(
                    child: EnterpriseDataGrid<DriverProfileModel>(
                      loading: _isLoading,
                      rows: drivers,
                      rowKey: (driver) => driver.id,
                      height: double.infinity,
                      showDateRange:
                          false, // Clean look, disables the top-right date range picker
                      columns: [
                        EnterpriseGridColumn(
                          label: 'Driver ID',
                          width: 110,
                          value: (driver) => driver.id.toString(),
                        ),
                        EnterpriseGridColumn(
                          label: 'Driver',
                          width: 240,
                          value: (driver) => driver.name,
                        ),
                        EnterpriseGridColumn(
                          label: 'Status',
                          width: 150,
                          value: (driver) => driver.status,
                          cellBuilder: (context, driver) =>
                              _StatusLabel(status: driver.status),
                        ),
                        EnterpriseGridColumn(
                          label: 'Phone',
                          width: 160,
                          value: (driver) => driver.phoneNumber,
                        ),
                        EnterpriseGridColumn(
                          label: 'Date hired',
                          width: 150,
                          value: (driver) => driver.dateHired,
                        ),
                        EnterpriseGridColumn(
                          label: 'Record actions',
                          width: 160,
                          value: (_) => '',
                          cellBuilder: (context, driver) => Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              onPressed: () =>
                                  widget.onDriverTapped?.call(context, driver),
                              child: Text(widget.canManage ? 'Update' : 'View'),
                            ),
                          ),
                        ),
                      ],
                      filterFields:
                          const [], // Removed to prevent duplicate search rendering
                      emptyTitle: _drivers.isEmpty
                          ? 'Assign the first driver'
                          : 'Nothing matches the current search or filters',
                      emptyMessage: _drivers.isEmpty
                          ? 'Driver profiles are required before schedules and vehicle assignments can be completed.'
                          : 'No driver records match the current search and status filters.',
                      emptyActionLabel: _drivers.isEmpty && widget.canManage
                          ? 'Add first driver'
                          : null,
                      onEmptyAction: _drivers.isEmpty && widget.canManage
                          ? () => widget.onDriverTapped?.call(context, null)
                          : null,
                      onDelete: widget.canManage ? _deleteDriver : null,
                      onBulkDelete: widget.canManage ? _bulkDelete : null,
                      onExportSelection: _exportDrivers,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(bool isDark) {
    final active = _drivers
        .where((driver) => driver.status.toLowerCase() == 'active')
        .length;
    final onLeave = _drivers
        .where((driver) => driver.status.toLowerCase() == 'on leave')
        .length;
    final suspended = _drivers
        .where((driver) => driver.status.toLowerCase() == 'suspended')
        .length;

    final cards = [
      (
        'Total Drivers',
        '${_drivers.length}',
        'All profiles',
        Icons.badge_outlined,
        const Color(0xFF3B82F6),
      ),
      (
        'Active Drivers',
        '$active',
        'Available for dispatch',
        Icons.check_circle_outline,
        const Color(0xFF10B981),
      ),
      (
        'On Leave',
        '$onLeave',
        'Currently unavailable',
        Icons.pause_circle_outline,
        const Color(0xFFF59E0B),
      ),
      (
        'Suspended',
        '$suspended',
        'Action required',
        Icons.block_outlined,
        const Color(0xFFEF4444),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;

        final cardWidgets = cards.map((card) {
          final Color baseColor = card.$5;
          return Container(
            constraints: const BoxConstraints(minHeight: 112),
            width: isNarrow ? double.infinity : null,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: 0.08),
              border: Border.all(color: baseColor.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(card.$4, color: baseColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        card.$1,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: baseColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  card.$2,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  card.$3,
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }).toList();

        if (isNarrow) {
          return Column(
            children: cardWidgets
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: c,
                  ),
                )
                .toList(),
          );
        }

        return Row(
          children: [
            Expanded(child: cardWidgets[0]),
            const SizedBox(width: 16),
            Expanded(child: cardWidgets[1]),
            const SizedBox(width: 16),
            Expanded(child: cardWidgets[2]),
            const SizedBox(width: 16),
            Expanded(child: cardWidgets[3]),
          ],
        );
      },
    );
  }

  Widget _buildFilters(bool isDark) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.start,
      children: [
        SizedBox(
          width: 280,
          height: 42,
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 180), () {
                if (!mounted) return;
                setState(() {
                  _searchQuery = value;
                  _rebuildFilteredDrivers();
                });
              });
            },
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search driver ID or name',
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF64748B),
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedStatusFilter,
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
                return ['All', 'Active', 'On Leave', 'Suspended'].map((
                  String value,
                ) {
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
                DropdownMenuItem(value: 'All', child: Text('All statuses')),
                DropdownMenuItem(value: 'Active', child: Text('Active')),
                DropdownMenuItem(value: 'On Leave', child: Text('On Leave')),
                DropdownMenuItem(value: 'Suspended', child: Text('Suspended')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedStatusFilter = value ?? 'All';
                  _rebuildFilteredDrivers();
                });
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final color = normalized == 'active'
        ? EnterpriseColors.success
        : normalized.contains('suspend')
        ? EnterpriseColors.danger
        : EnterpriseColors.warning;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          status,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
