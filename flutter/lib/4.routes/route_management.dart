import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constant.dart';
import '../layouts/enterprise/enterprise_theme.dart';
import '../utilities/file_download.dart';
import '../layouts/enterprise/enterprise_data_grid.dart';
import '../layouts/enterprise/enterprise_states.dart';


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
  String _currentSort = 'Name (A to Z)';
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
    List<Map<String, dynamic>> result = _routes;

    if (query.isNotEmpty) {
      result = result.where((route) {
        return (route['route_name'] ?? '').toString().toLowerCase().contains(query) ||
            (route['route_id'] ?? '').toString().contains(query);
      }).toList();
    } else {
      result = List.from(_routes);
    }

    result.sort((a, b) {
      final nameA = (a['route_name'] ?? '').toString().toLowerCase();
      final nameB = (b['route_name'] ?? '').toString().toLowerCase();

      switch (_currentSort) {
        case 'Name (Z to A)':
          return nameB.compareTo(nameA);
        case 'Most Trips':
          return _tripCount(b).compareTo(_tripCount(a));
        case 'Least Trips':
          return _tripCount(a).compareTo(_tripCount(b));
        case 'Name (A to Z)':
        default:
          return nameA.compareTo(nameB);
      }
    });

    return result;
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

  List<Widget> _selectedRouteActions(
    BuildContext context,
    List<Map<String, dynamic>> selectedRoutes,
  ) {
    if (selectedRoutes.length != 1) return const [];
    final route = selectedRoutes.first;
    if (_tripCount(route) > 0) return const [];
    return [
      FilledButton.icon(
        onPressed: () async {
          final routeName = (route['route_name'] ?? 'this route').toString();
          final confirmed = await showEnterpriseDestructiveConfirmation(
            context,
            title: 'Delete route?',
            message:
                'This will permanently delete $routeName. Type DELETE to continue.',
          );
          if (!confirmed) return;
          try {
            await _deleteRoute(route);
            if (mounted) {
              EnterpriseToasts.success(context, 'Route deleted.');
            }
          } catch (error) {
            if (mounted) {
              EnterpriseToasts.error(context, 'Unable to delete route: $error');
            }
          }
        },
        icon: const Icon(Icons.delete_outline, size: 16),
        label: const Text('Delete'),
        style: FilledButton.styleFrom(
          backgroundColor: EnterpriseColors.danger,
        ),
      ),
    ];
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

  InputDecoration _inputDecoration(String label, String helper, String? error, {String? prefixText}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      errorText: error,
      prefixText: prefixText,
      filled: true,
      fillColor: Theme.of(context).cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
    );
  }

Widget _sortDropdown(bool isDark) {
    final sortOptions = ['Name (A to Z)', 'Name (Z to A)', 'Most Trips', 'Least Trips'];

    return Container(
      height: 34, // Slightly taller for breathing room
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _currentSort,
          isExpanded: true, 
          isDense: true, // <-- THIS IS THE FIX. It forces the text to fit the small box.
          icon: const Padding(
            padding: EdgeInsets.only(left: 8.0),
            child: Icon(Icons.sort, size: 16),
          ),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          dropdownColor: Theme.of(context).cardColor,
          selectedItemBuilder: (BuildContext context) {
            return sortOptions.map((String value) {
              return Text(
                'Sort: $value',
                overflow: TextOverflow.ellipsis,
              );
            }).toList();
          },
          items: sortOptions
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _currentSort = val);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final routes = _filteredRoutes;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. TOP ROW: Title on Left, Search + Refresh on Right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Route Management',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 280,
                      height: 42,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _search = value),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search route or ID',
                          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                          filled: true,
                          fillColor: Theme.of(context).cardColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Theme.of(context).dividerColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _loadRoutes,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 2. FORM AREA & GREEN KPI CARD
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 900;
                
                final formWidget = Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: [
                      SizedBox(
                        width: 320,
                        child: TextField(
                          controller: _nameController,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: _inputDecoration(
                            'Route name',
                            'Use the dispatch-facing route label.',
                            _nameError,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: _inputDecoration(
                            'Rate',
                            'Non-negative amount.',
                            _priceError,
                            prefixText: 'PHP ',
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton.icon(
                              onPressed: _isSaving ? null : _saveRoute,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: EnterpriseLoadingIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.save_outlined, size: 17),
                              label: Text(_editingRouteId == null ? 'Add route' : 'Update route'),
                              style: FilledButton.styleFrom(
                                backgroundColor: EnterpriseColors.generativeAction,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              ),
                            ),
                            if (_editingRouteId != null) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _clearForm,
                                child: const Text('Cancel'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );

                final kpiWidget = EnterpriseSummaryCard(
                  label: 'Total Destinations',
                  value: '${_routes.length}',
                  icon: Icons.map_outlined,
                  color: const Color(0xFF10B981), // Solid Green match
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      formWidget,
                      const SizedBox(height: 16),
                      kpiWidget,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start, // Shrink-wraps the form vertically
                  children: [
                    Expanded(
                      flex: 5,
                      child: formWidget,
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 3, // Expands horizontally to fill remaining dead space
                      child: kpiWidget,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // 3. MAIN WORKSPACE TABLE
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: EnterpriseDataGrid<Map<String, dynamic>>(
                      loading: _isLoading,
                      rows: routes,
                      rowKey: (route) => route['route_id'] ?? route.hashCode,
                      height: double.infinity,
                      showDateRange: false, // Disables the Date Range button
                      filterFields: [
                        _sortDropdown(isDark), // Top-Left Anchored Dropdown filter
                      ],
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
                          onChanged: (route, value) => _updateRouteField(route, 'name', value),
                        ),
                        EnterpriseGridColumn(
                          label: 'Rate',
                          width: 170,
                          value: (route) => 'PHP ${_priceOf(route).toStringAsFixed(2)}',
                          editable: true,
                          compare: (first, second) => _priceOf(first).compareTo(_priceOf(second)),
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
                          compare: (first, second) => _tripCount(first).compareTo(_tripCount(second)),
                        ),
                      ],
                      emptyTitle: _routes.isEmpty
                          ? 'Create the first route'
                          : 'Nothing matches the current search',
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
                      canDelete: (route) => _tripCount(route) == 0,
                      onBulkDelete: _bulkDelete,
                      selectionActionsBuilder: _selectedRouteActions,
                      onExportSelection: _exportRoutes,
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
}

abstract final class EnterpriseToasts {
  static void success(BuildContext context, String message) {
    _show(
      context,
      message,
      EnterpriseColors.success,
      Icons.check_circle_outline,
    );
  }

  static void error(BuildContext context, String message) {
    _show(context, message, EnterpriseColors.danger, Icons.error_outline);
  }

  static void warning(BuildContext context, String message) {
    _show(context, message, EnterpriseColors.warning, Icons.warning_amber);
  }

  static void information(BuildContext context, String message) {
    _show(context, message, EnterpriseColors.information, Icons.info_outline);
  }

  static void _show(
    BuildContext context,
    String message,
    Color color,
    IconData icon,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showEnterpriseDestructiveConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  String confirmationText = 'DELETE',
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
                helperText: 'This second step prevents accidental data loss.',
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
            onPressed: valid ? () => Navigator.pop(dialogContext, true) : null,
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
