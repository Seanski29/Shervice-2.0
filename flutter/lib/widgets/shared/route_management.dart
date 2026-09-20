import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constant.dart';
import '../../theme/enterprise_theme.dart';
import '../../utils/file_download.dart';
import 'enterprise_data_grid.dart';
import 'enterprise_states.dart';

class RouteDirectory extends StatefulWidget {
  const RouteDirectory({super.key});

  @override
  State<RouteDirectory> createState() => _RouteDirectoryState();
}

class _RouteDirectoryState extends State<RouteDirectory> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController(text: '0');
  final _searchController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  int? _editingRouteId;
  String? _nameError;
  String? _priceError;
  String _search = '';
  DateTime? _lastRefreshed;
  List<Map<String, dynamic>> _routes = [];

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredRoutes {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return _routes;
    return _routes.where((route) {
      return (route['route_name'] ?? '').toString().toLowerCase().contains(
            query,
          ) ||
          (route['route_id'] ?? '').toString().contains(query);
    }).toList();
  }

  double _priceOf(Map<String, dynamic> route) {
    final value = route['price'];
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '0').toString()) ?? 0;
  }

  int _tripCount(Map<String, dynamic> route) =>
      int.tryParse((route['trip_count'] ?? '0').toString()) ?? 0;

  Future<void> _loadRoutes() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('$backendUrl/routes'));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(decoded['message'] ?? 'Unable to load routes.');
      }
      if (!mounted) return;
      setState(() {
        _routes = (decoded['data'] as List? ?? [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _lastRefreshed = DateTime.now();
      });
    } catch (error) {
      if (mounted) {
        EnterpriseToasts.error(context, 'Unable to load routes: $error');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _validateForm() {
    final price = double.tryParse(_priceController.text.trim());
    setState(() {
      _nameError = _nameController.text.trim().isEmpty
          ? 'Route name is required.'
          : null;
      _priceError = price == null || price < 0
          ? 'Enter a valid non-negative rate.'
          : null;
    });
    return _nameError == null && _priceError == null;
  }

  Future<void> _saveRoute() async {
    if (!_validateForm()) return;
    setState(() => _isSaving = true);
    try {
      final routeId = _editingRouteId;
      final response = await _persistRoute(
        routeId: routeId,
        name: _nameController.text.trim(),
        price: double.parse(_priceController.text.trim()),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['message'] ?? 'Unable to save route.');
      }
      _clearForm();
      await _loadRoutes();
      if (mounted) {
        EnterpriseToasts.success(
          context,
          routeId == null ? 'Route created.' : 'Route updated.',
        );
      }
    } catch (error) {
      if (mounted) {
        EnterpriseToasts.error(context, 'Unable to save route: $error');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<http.Response> _persistRoute({
    required int? routeId,
    required String name,
    required double price,
  }) {
    final body = jsonEncode({'route_name': name, 'price': price});
    final headers = {'Content-Type': 'application/json'};
    if (routeId == null) {
      return http.post(
        Uri.parse('$backendUrl/routes'),
        headers: headers,
        body: body,
      );
    }
    return http.put(
      Uri.parse('$backendUrl/routes/$routeId'),
      headers: headers,
      body: body,
    );
  }

  Future<void> _updateRouteField(
    Map<String, dynamic> route,
    String field,
    String value,
  ) async {
    final routeId = int.tryParse((route['route_id'] ?? '').toString());
    if (routeId == null) return;
    final name = field == 'name'
        ? value.trim()
        : (route['route_name'] ?? '').toString();
    final price = field == 'price'
        ? double.tryParse(value.trim())
        : _priceOf(route);
    if (name.isEmpty || price == null || price < 0) {
      throw const FormatException('Enter a valid route name and rate.');
    }
    final response = await _persistRoute(
      routeId: routeId,
      name: name,
      price: price,
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to update route.');
    }
    await _loadRoutes();
  }

  Future<void> _deleteRoute(Map<String, dynamic> route) async {
    if (_tripCount(route) > 0) {
      throw Exception('This route has assigned trips and cannot be deleted.');
    }
    final routeId = route['route_id'];
    final response = await http.delete(
      Uri.parse('$backendUrl/routes/$routeId'),
    );
    if (response.statusCode != 200) {
      Map<String, dynamic> decoded = {};
      try {
        final body = jsonDecode(response.body);
        if (body is Map) decoded = Map<String, dynamic>.from(body);
      } catch (_) {}
      if (response.statusCode == 409) {
        throw Exception(
          decoded['message'] ??
              'This route has assigned trips and cannot be deleted.',
        );
      }
      throw Exception(decoded['message'] ?? 'Unable to delete route.');
    }
    await _loadRoutes();
  }

  Future<void> _bulkDelete(List<Map<String, dynamic>> routes) async {
    final blocked = routes.where((route) => _tripCount(route) > 0).length;
    if (blocked > 0) {
      throw Exception(
        blocked == 1
            ? 'This route has existing trips and cannot be deleted.'
            : '$blocked selected routes have existing trips and cannot be deleted.',
      );
    }
    for (final route in routes.where((route) => _tripCount(route) == 0)) {
      await _deleteRoute(route);
    }
  }

  Future<void> _exportRoutes(List<Map<String, dynamic>> routes) async {
    final buffer = StringBuffer('ID,Route,Rate,Trips\n');
    for (final route in routes) {
      final name = (route['route_name'] ?? '').toString().replaceAll('"', '""');
      buffer.writeln(
        '${route['route_id']},"$name",${_priceOf(route).toStringAsFixed(2)},${_tripCount(route)}',
      );
    }
    await downloadFileBytes(
      fileName: 'shervice-routes.csv',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
    );
    if (mounted) {
      EnterpriseToasts.success(context, '${routes.length} routes exported.');
    }
  }

  void _editRoute(Map<String, dynamic> route) {
    setState(() {
      _editingRouteId = int.tryParse((route['route_id'] ?? '').toString());
      _nameController.text = (route['route_name'] ?? '').toString();
      _priceController.text = _priceOf(route).toStringAsFixed(2);
      _nameError = null;
      _priceError = null;
    });
  }

  void _clearForm() {
    setState(() {
      _editingRouteId = null;
      _nameController.clear();
      _priceController.text = '0';
      _nameError = null;
      _priceError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final routes = _filteredRoutes;
    final lastRefreshed = _lastRefreshed;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MetadataLabel(
                icon: Icons.route_outlined,
                label: '${_routes.length} route records',
              ),
              _MetadataLabel(
                icon: Icons.sync_outlined,
                label: lastRefreshed == null
                    ? 'Awaiting synchronization'
                    : 'Last synchronized ${_timeLabel(lastRefreshed)}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Route name',
                      helperText: 'Use the dispatch-facing route label.',
                      errorText: _nameError,
                    ),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Rate',
                      prefixText: 'PHP ',
                      helperText: 'Non-negative amount.',
                      errorText: _priceError,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _saveRoute,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: EnterpriseLoadingIndicator(
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined, size: 17),
                  label: Text(
                    _editingRouteId == null ? 'Add route' : 'Update route',
                  ),
                ),
                if (_editingRouteId != null)
                  TextButton(
                    onPressed: _clearForm,
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          EnterpriseDataGrid<Map<String, dynamic>>(
            loading: _isLoading,
            rows: routes,
            rowKey: (route) => route['route_id'] ?? route.hashCode,
            columns: [
              EnterpriseGridColumn(
                label: 'Route ID',
                width: 110,
                value: (route) => (route['route_id'] ?? '').toString(),
              ),
              EnterpriseGridColumn(
                label: 'Route',
                width: 280,
                value: (route) => (route['route_name'] ?? '').toString(),
                editable: true,
                onChanged: (route, value) =>
                    _updateRouteField(route, 'name', value),
              ),
              EnterpriseGridColumn(
                label: 'Rate',
                width: 170,
                value: (route) => 'PHP ${_priceOf(route).toStringAsFixed(2)}',
                editable: true,
                compare: (first, second) =>
                    _priceOf(first).compareTo(_priceOf(second)),
                onChanged: (route, value) => _updateRouteField(
                  route,
                  'price',
                  value.replaceAll('PHP', '').trim(),
                ),
              ),
              EnterpriseGridColumn(
                label: 'Assigned trips',
                width: 150,
                value: (route) => '${_tripCount(route)}',
                compare: (first, second) =>
                    _tripCount(first).compareTo(_tripCount(second)),
              ),
              EnterpriseGridColumn(
                label: 'Record actions',
                width: 150,
                value: (_) => '',
                cellBuilder: (context, route) => Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => _editRoute(route),
                    child: const Text('Edit'),
                  ),
                ),
              ),
            ],
            filterFields: [
              SizedBox(
                width: 340,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search route or ID',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loadRoutes,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('Refresh'),
              ),
            ],
            emptyTitle: _routes.isEmpty
                ? 'Create the first route'
                : 'Nothing matches the current search or filters',
            emptyMessage: _routes.isEmpty
                ? 'Routes connect trip assignments, rates, payroll, and operational reporting.'
                : 'No route records match the current search.',
            emptyActionLabel: _routes.isEmpty ? 'Add first route' : null,
            onEmptyAction: _routes.isEmpty
                ? () => _nameController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _nameController.text.length,
                  )
                : null,
            onDelete: _deleteRoute,
            canDelete: (route) => _tripCount(route) == 0,
            onBulkDelete: _bulkDelete,
            onExportSelection: _exportRoutes,
          ),
        ],
      ),
    );
  }

  String _timeLabel(DateTime value) {
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    return '${difference.inHours}h ago';
  }
}

class _MetadataLabel extends StatelessWidget {
  const _MetadataLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: EnterpriseColors.information),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
