import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constant.dart';

class RouteManagement extends StatefulWidget {
  const RouteManagement({super.key});

  @override
  State<RouteManagement> createState() => _RouteManagementState();
}

class _RouteManagementState extends State<RouteManagement> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController(text: '0');
  final _searchController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  int? _editingRouteId;
  String _search = '';
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
      return (route['route_name'] ?? '').toString().toLowerCase().contains(query) ||
          (route['route_id'] ?? '').toString().contains(query);
    }).toList();
  }

  double _priceOf(Map<String, dynamic> route) {
    final value = route['price'];
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '0').toString()) ?? 0;
  }

  Future<void> _loadRoutes() async {
    setState(() => _isLoading = true);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load routes: $error')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveRoute() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final body = jsonEncode({
        'route_name': name,
        'price': double.tryParse(_priceController.text.trim()) ?? 0,
      });
      final routeId = _editingRouteId;
      final response = routeId == null
          ? await http.post(
              Uri.parse('$backendUrl/routes'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
          : await http.put(
              Uri.parse('$backendUrl/routes/$routeId'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            );
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(decoded['message'] ?? 'Unable to save route.');
      }
      _clearForm();
      await _loadRoutes();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save route: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteRoute(Map<String, dynamic> route) async {
    final routeId = route['route_id'];
    final name = (route['route_name'] ?? '').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Route'),
        content: Text('Delete "$name"? Routes already used by trips cannot be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await http.delete(Uri.parse('$backendUrl/routes/$routeId'));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(decoded['message'] ?? 'Unable to delete route.');
      }
      await _loadRoutes();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  void _editRoute(Map<String, dynamic> route) {
    setState(() {
      _editingRouteId = int.tryParse((route['route_id'] ?? '').toString());
      _nameController.text = (route['route_name'] ?? '').toString();
      _priceController.text = _priceOf(route).toStringAsFixed(2);
    });
  }

  void _clearForm() {
    setState(() {
      _editingRouteId = null;
      _nameController.clear();
      _priceController.text = '0';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final routes = _filteredRoutes;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Route Management', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF0F172A))),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 280, child: TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Route name', border: OutlineInputBorder(), isDense: true))),
                SizedBox(width: 180, child: TextField(controller: _priceController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Rate', prefixText: 'PHP ', border: OutlineInputBorder(), isDense: true))),
                ElevatedButton.icon(onPressed: _isSaving ? null : _saveRoute, icon: const Icon(Icons.save_outlined), label: Text(_editingRouteId == null ? 'Add Route' : 'Save Route')),
                if (_editingRouteId != null) TextButton(onPressed: _clearForm, child: const Text('Cancel')),
                SizedBox(width: 280, child: TextField(controller: _searchController, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search routes', border: OutlineInputBorder(), isDense: true), onChanged: (value) => setState(() => _search = value))),
                IconButton(onPressed: _loadRoutes, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
              ),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('Route')),
                  DataColumn(label: Text('Rate')),
                  DataColumn(label: Text('Trips')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: routes.map((route) {
                  final tripCount = int.tryParse((route['trip_count'] ?? '0').toString()) ?? 0;
                  return DataRow(cells: [
                    DataCell(Text((route['route_id'] ?? '').toString())),
                    DataCell(Text((route['route_name'] ?? '').toString())),
                    DataCell(Text('PHP ${_priceOf(route).toStringAsFixed(2)}')),
                    DataCell(Text('$tripCount')),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(onPressed: () => _editRoute(route), icon: const Icon(Icons.edit_outlined), tooltip: 'Edit'),
                      IconButton(onPressed: tripCount > 0 ? null : () => _deleteRoute(route), icon: const Icon(Icons.delete_outline), tooltip: tripCount > 0 ? 'Route is used by trips' : 'Delete'),
                    ])),
                  ]);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
