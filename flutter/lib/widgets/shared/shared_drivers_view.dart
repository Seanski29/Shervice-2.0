import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constant.dart';
import '../../theme/enterprise_theme.dart';
import '../../utils/file_download.dart';
import '../driver/driver_profile_model.dart';
import 'enterprise_data_grid.dart';
import 'enterprise_states.dart';

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
          driver.id.toString().toLowerCase().contains(query) ||
          driver.email.toLowerCase().contains(query);
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
    final buffer = StringBuffer(
      'Driver ID,Name,Email,Phone,Status,Date Hired,Rating\n',
    );
    for (final driver in drivers) {
      buffer.writeln(
        '${driver.id},"${_csv(driver.name)}","${_csv(driver.email)}",'
        '"${_csv(driver.phoneNumber)}","${_csv(driver.status)}",'
        '${driver.dateHired},${driver.rating.toStringAsFixed(1)}',
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
    final drivers = _filteredDrivers;
    final active = _drivers
        .where((driver) => driver.status.toLowerCase() == 'active')
        .length;
    final unavailable = _drivers.length - active;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = <Widget>[
                if (_isLoading) ...[
                  const EnterpriseSummaryCardSkeleton(),
                  const EnterpriseSummaryCardSkeleton(),
                  const EnterpriseSummaryCardSkeleton(),
                ] else ...[
                  EnterpriseSummaryCard(
                    label: 'Total drivers',
                    value: '${_drivers.length}',
                    icon: Icons.badge_outlined,
                    color: EnterpriseColors.information,
                  ),
                  EnterpriseSummaryCard(
                    label: 'Active drivers',
                    value: '$active',
                    icon: Icons.check_circle_outline,
                    color: EnterpriseColors.success,
                  ),
                  EnterpriseSummaryCard(
                    label: 'Unavailable',
                    value: '$unavailable',
                    icon: Icons.pause_circle_outline,
                    color: EnterpriseColors.warning,
                  ),
                ],
              ];
              if (constraints.maxWidth >= 900) {
                return Row(
                  children: [
                    for (final card in cards) Expanded(child: card),
                    if (widget.actionWidget != null) ...[
                      const SizedBox(width: 12),
                      widget.actionWidget!,
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ...cards,
                  if (widget.actionWidget != null) widget.actionWidget!,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: EnterpriseDataGrid<DriverProfileModel>(
              loading: _isLoading,
              rows: drivers,
              rowKey: (driver) => driver.id,
              height: double.infinity,
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
                  label: 'Email',
                  width: 240,
                  value: (driver) =>
                      driver.email.isEmpty ? 'Not provided' : driver.email,
                ),
                EnterpriseGridColumn(
                  label: 'Date hired',
                  width: 150,
                  value: (driver) => driver.dateHired,
                ),
                EnterpriseGridColumn(
                  label: 'Rating',
                  width: 120,
                  value: (driver) => '⭐ ${driver.rating.toStringAsFixed(1)}',
                  compare: (first, second) =>
                      first.rating.compareTo(second.rating),
                ),
                EnterpriseGridColumn(
                  label: 'Record actions',
                  width: 160,
                  value: (_) => '',
                  cellBuilder: (context, driver) => Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          widget.onDriverTapped?.call(context, driver),
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: Text(widget.canManage ? 'Open / edit' : 'Open'),
                    ),
                  ),
                ),
              ],
              filterFields: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 180),
                        () {
                          if (!mounted) return;
                          setState(() {
                            _searchQuery = value;
                            _rebuildFilteredDrivers();
                          });
                        },
                      );
                    },
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Filter driver, ID, or email',
                    ),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedStatusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(
                        value: 'All',
                        child: Text('All statuses'),
                      ),
                      DropdownMenuItem(value: 'Active', child: Text('Active')),
                      DropdownMenuItem(
                        value: 'On Leave',
                        child: Text('On leave'),
                      ),
                      DropdownMenuItem(
                        value: 'Suspended',
                        child: Text('Suspended'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedStatusFilter = value ?? 'All';
                        _rebuildFilteredDrivers();
                      });
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _fetchDrivers,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('Refresh'),
                ),
              ],
              emptyTitle: _drivers.isEmpty
                  ? 'Assign the first driver'
                  : 'Adjust the active filters',
              emptyMessage: _drivers.isEmpty
                  ? 'Driver profiles are required before schedules and vehicle assignments can be completed.'
                  : 'No driver records match the current search and status filters.',
              emptyActionLabel: _drivers.isEmpty && widget.canManage
                  ? 'Add first driver'
                  : 'Clear filters',
              onEmptyAction: () {
                if (_drivers.isEmpty && widget.canManage) {
                  widget.onDriverTapped?.call(context, null);
                } else {
                  _searchDebounce?.cancel();
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _selectedStatusFilter = 'All';
                    _rebuildFilteredDrivers();
                  });
                }
              },
              onDelete: widget.canManage ? _deleteDriver : null,
              onBulkDelete: widget.canManage ? _bulkDelete : null,
              onExportSelection: _exportDrivers,
            ),
          ),
        ],
      ),
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
