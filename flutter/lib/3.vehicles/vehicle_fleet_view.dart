import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import '../constant.dart';
import '../core/session_manager.dart';
import '../layouts/enterprise/enterprise_theme.dart';
import '../utilities/file_download.dart';
import '../layouts/enterprise/enterprise_data_grid.dart';
import '../layouts/enterprise/enterprise_states.dart';

class VehicleFleetView extends StatefulWidget {
  final String userRole;
  final String? userId;
  final VoidCallback onRefreshNeeded;
  final String title;
  final String subtitle;

  const VehicleFleetView({
    super.key,
    required this.userRole,
    this.userId,
    required this.onRefreshNeeded,
    required this.title,
    required this.subtitle,
  });

  @override
  State<VehicleFleetView> createState() => _VehicleFleetViewState();
}

class _VehicleFleetViewState extends State<VehicleFleetView> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<dynamic> _allVehicles = [];
  List<dynamic> _filteredVehicles = [];

  String _searchQuery = '';
  String _statusFilter = 'All';
  String _currentSort = 'Plate (A to Z)';
  final List<String> _sortOptions = [
    'Plate (A to Z)',
    'Plate (Z to A)',
    'Vehicle Type',
  ];

  int _currentPage = 0;
  final int _itemsPerPage = 10;

  bool get _isAdmin => widget.userRole.toLowerCase() == 'admin';

  Future<Map<String, String>> _maintenanceHeaders() async {
    final session = await SessionManager.getUserData();
    final token = session['accessToken'];
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  @override
  void initState() {
    super.initState();
    _fetchLiveFleetData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchLiveFleetData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isRefreshing = true;
    });

    try {
      final response = await http
          .get(Uri.parse('$backendUrl/vehicles'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _allVehicles = data['data'] ?? [];
      }
    } catch (e) {
      debugPrint("Failed to fetch vehicles: $e");
      _allVehicles = [];
    } finally {
      if (mounted) {
        _applyFiltersAndSort();
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<List<dynamic>> _fetchVehicleLogHistory(int vehicleId) async {
    try {
      final res = await http.get(Uri.parse('$backendUrl/vehicles/maintenance'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'] ?? [];
        return data.where((log) => log['vehicle_id'] == vehicleId).toList();
      }
    } catch (e) {
      debugPrint("Error fetching log history: $e");
    }
    return [];
  }

  void _applyFiltersAndSort() {
    if (!mounted) return;
    List<dynamic> temp = _allVehicles.where((v) {
      final plate = (v['plate_number'] ?? '').toString().toLowerCase();
      final type = (v['bus_type'] ?? '').toString().toLowerCase();

      final status = (v['health_status'] ?? 'Good').toString().toLowerCase();
      final dueType =
          (v['maintenance_due_type'] ??
                  (v['needs_attention'] == true ? 'maintenance' : ''))
              .toString()
              .toLowerCase();

      final matchesSearch =
          plate.contains(_searchQuery.toLowerCase()) ||
          type.contains(_searchQuery.toLowerCase());

      bool matchesStatus = true;
      if (_statusFilter == 'Available') {
        matchesStatus = status == 'good' || status == 'excellent';
      } else if (_statusFilter == 'Due Maintenance') {
        matchesStatus = dueType == 'maintenance';
      } else if (_statusFilter == 'Due Repair') {
        matchesStatus = dueType == 'repair';
      }

      return matchesSearch && matchesStatus;
    }).toList();

    temp.sort((a, b) {
      final plateA = (a['plate_number'] ?? '').toString().toLowerCase();
      final plateB = (b['plate_number'] ?? '').toString().toLowerCase();
      final typeA = (a['bus_type'] ?? '').toString().toLowerCase();
      final typeB = (b['bus_type'] ?? '').toString().toLowerCase();

      switch (_currentSort) {
        case 'Plate (Z to A)':
          return plateB.compareTo(plateA);
        case 'Vehicle Type':
          return typeA.compareTo(typeB);
        case 'Plate (A to Z)':
        default:
          return plateA.compareTo(plateB);
      }
    });

    setState(() {
      _filteredVehicles = temp;
      _currentPage = 0;
      _isLoading = false;
    });
  }

  int get _totalPages =>
      max(1, (_filteredVehicles.length / _itemsPerPage).ceil());

  List<dynamic> get _paginatedVehicles {
    if (_isLoading) {
      return List.generate(
        5,
        (index) => {
          'vehicle_id': index,
          'plate_number': 'LOD-1234',
          'bus_type': '15 Seats - Standard Shuttle',
          'health_status': 'Good Condition',
        },
      );
    }
    if (_filteredVehicles.isEmpty) return [];
    int start = _currentPage * _itemsPerPage;
    int end = min(start + _itemsPerPage, _filteredVehicles.length);
    return _filteredVehicles.sublist(start, end);
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) setState(() => _currentPage++);
  }

  void _prevPage() {
    if (_currentPage > 0) setState(() => _currentPage--);
  }

  Iterable<dynamic> get _baseVehicles => _allVehicles.where((v) {
    final plate = (v['plate_number'] ?? '').toString().toLowerCase();
    final type = (v['bus_type'] ?? '').toString().toLowerCase();
    return plate.contains(_searchQuery.toLowerCase()) ||
        type.contains(_searchQuery.toLowerCase());
  });

  int get _totalVehicles => _isLoading ? 0 : _baseVehicles.length;
  int get _availableVehicles => _isLoading
      ? 0
      : _baseVehicles.where((v) {
          final s = (v['health_status'] ?? 'Good').toString().toLowerCase();
          return (s == 'good' || s == 'excellent') &&
              v['needs_attention'] != true;
        }).length;
  int get _maintenanceVehicles => _isLoading
      ? 0
      : _baseVehicles.where((v) {
          return (v['maintenance_due_type'] ??
                  (v['needs_attention'] == true ? 'maintenance' : '')) ==
              'maintenance';
        }).length;
  int get _repairVehicles => _isLoading
      ? 0
      : _baseVehicles
            .where((v) => v['maintenance_due_type'] == 'repair')
            .length;

  Color _getStatusColor(String rawStatus) {
    final status = rawStatus.toLowerCase();
    if (status.contains('maintenance') || status.contains('repair')) {
      return const Color(0xFFEF4444);
    }
    return const Color(0xFF10B981);
  }

  Future<void> _confirmPurgeVehicle(Map<String, dynamic> vehicle) async {
    if (!_isAdmin) return;
    final confirmed = await showEnterpriseDestructiveConfirmation(
      context,
      title: 'Delete vehicle record?',
      message:
          'This permanently removes ${vehicle['plate_number'] ?? 'the selected vehicle'} and its master fleet record.',
    );
    if (!confirmed) return;
    try {
      await _purgeVehicleDirect(vehicle);
      if (mounted) EnterpriseToasts.success(context, 'Vehicle record deleted.');
    } catch (error) {
      if (mounted) {
        EnterpriseToasts.error(context, 'Unable to delete vehicle: $error');
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showVehicleModal(
    BuildContext context, {
    Map<String, dynamic>? vehicle,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return RegisterVehicleDialog(
          vehicle: vehicle,
          isAdmin: _isAdmin,
          onDelete: (vehicle == null || !_isAdmin)
              ? null
              : () => _confirmPurgeVehicle(vehicle),
        );
      },
    ).then((_) {
      if (mounted) {
        setState(() => _isLoading = true);
        _fetchLiveFleetData();
      }
    });
  }

  Future<void> _purgeVehicleDirect(Map<String, dynamic> vehicle) async {
    if (!_isAdmin) return;
    final rawId =
        vehicle['vehicle_id'] ?? vehicle['id'] ?? vehicle['plate_number'];
    if (rawId == null) throw Exception('Vehicle record has no identifier.');
    final response = await http
        .delete(Uri.parse('$backendUrl/vehicles/$rawId'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Deletion failed with status ${response.statusCode}.');
    }
    widget.onRefreshNeeded();
    await _fetchLiveFleetData();
  }

  Future<void> _exportVehicles(List<Map<String, dynamic>> vehicles) async {
    final buffer = StringBuffer(
      'Vehicle ID,Plate,Type,Capacity,Health Status\n',
    );
    for (final vehicle in vehicles) {
      final rawType = (vehicle['bus_type'] ?? '').toString();
      final parts = rawType.split(' - ');
      final capacity = parts.length > 1 ? parts.first : '';
      final model = parts.length > 1 ? parts.sublist(1).join(' - ') : rawType;
      String escape(String value) => value.replaceAll('"', '""');
      buffer.writeln(
        '${vehicle['vehicle_id'] ?? vehicle['id'] ?? ''},'
        '"${escape((vehicle['plate_number'] ?? '').toString())}",'
        '"${escape(model)}","${escape(capacity)}",'
        '"${escape((vehicle['health_status'] ?? '').toString())}"',
      );
    }
    await downloadFileBytes(
      fileName: 'shervice-vehicles.csv',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
    );
    if (mounted) {
      EnterpriseToasts.success(
        context,
        '${vehicles.length} vehicles exported.',
      );
    }
  }

  List<Widget> _selectedVehicleActions(
    BuildContext context,
    List<Map<String, dynamic>> selectedVehicles,
  ) {
    if (selectedVehicles.length != 1) return const [];
    final vehicle = selectedVehicles.first;

    return [
      OutlinedButton.icon(
        onPressed: () => _showVehicleModal(context, vehicle: vehicle),
        icon: Icon(
          _isAdmin ? Icons.edit_outlined : Icons.visibility_outlined,
          size: 16,
        ),
        label: Text(_isAdmin ? 'Update' : 'View Details'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF667085)),
        ),
      ),
      if (_isAdmin) ...[
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: () async {
            final vehicleId =
                int.tryParse((vehicle['vehicle_id'] ?? '').toString()) ?? 0;
            final logs = await _fetchVehicleLogHistory(vehicleId);
            if (context.mounted) {
              _showMaintenanceManagerModal(context, vehicle, logs);
            }
          },
          icon: const Icon(Icons.history, size: 16),
          label: const Text('View Maintenance Logs'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF667085)),
          ),
        ),
      ],
      if (!_isAdmin) ...[
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: () async {
            final vehicleId =
                int.tryParse((vehicle['vehicle_id'] ?? '').toString()) ?? 0;
            final logs = await _fetchVehicleLogHistory(vehicleId);
            if (context.mounted) {
              _showMaintenanceManagerModal(context, vehicle, logs);
            }
          },
          icon: const Icon(Icons.build_circle_outlined, size: 16),
          label: const Text('Log Maintenance'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF667085)),
          ),
        ),
      ],
    ];
  }

  void _showLogIssueDialog(Map<String, dynamic> vehicle) {
    final formKey = GlobalKey<FormState>();
    String description = '';
    String chosenType = 'repair';
    String chosenCategory = 'General';
    DateTime? incidentDate = DateTime.now();
    TimeOfDay? incidentTime = TimeOfDay.now();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final inputBg = isDark
              ? const Color(0xFF0F172A)
              : const Color(0xFFF1F5F9);
          final borderColor = isDark
              ? Colors.grey.shade700
              : Colors.grey.shade300;
          final textColor = isDark ? Colors.white : Colors.black87;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            title: Text(
              'Log Issue: ${vehicle['plate_number']}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: chosenType,
                        dropdownColor: isDark
                            ? const Color(0xFF1E293B)
                            : Colors.white,
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Record Type',
                          labelStyle: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          filled: true,
                          fillColor: inputBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: borderColor),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'repair',
                            child: Text('Repair'),
                          ),
                          DropdownMenuItem(
                            value: 'maintenance',
                            child: Text('Maintenance'),
                          ),
                        ],
                        onChanged: (val) =>
                            setModalState(() => chosenType = val ?? 'repair'),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: chosenCategory,
                        dropdownColor: isDark
                            ? const Color(0xFF1E293B)
                            : Colors.white,
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Issue Category',
                          labelStyle: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          filled: true,
                          fillColor: inputBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: borderColor),
                          ),
                        ),
                        items:
                            [
                                  'General',
                                  'Engine',
                                  'Exterior',
                                  'Interior',
                                  'Electrical',
                                  'Tires/Wheels',
                                ]
                                .map(
                                  (s) => DropdownMenuItem<String>(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) => setModalState(
                          () => chosenCategory = val ?? 'General',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: incidentDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (picked != null) {
                                  setModalState(() => incidentDate = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Incident Date',
                                  filled: true,
                                  fillColor: inputBg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                ),
                                child: Text(
                                  incidentDate != null
                                      ? "${incidentDate!.month}/${incidentDate!.day}/${incidentDate!.year}"
                                      : "Select Date",
                                  style: TextStyle(color: textColor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: incidentTime ?? TimeOfDay.now(),
                                );
                                if (picked != null) {
                                  setModalState(() => incidentTime = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Incident Time',
                                  filled: true,
                                  fillColor: inputBg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                ),
                                child: Text(
                                  incidentTime != null
                                      ? incidentTime!.format(context)
                                      : "Select Time",
                                  style: TextStyle(color: textColor),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          labelText: 'Short Description',
                          labelStyle: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          filled: true,
                          fillColor: inputBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: borderColor),
                          ),
                        ),
                        maxLines: 2,
                        validator: (val) => (val == null || val.trim().isEmpty)
                            ? 'Required'
                            : null,
                        onSaved: (val) => description = val ?? '',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (formKey.currentState?.validate() ?? false) {
                          formKey.currentState?.save();
                          setModalState(() => isSaving = true);
                          final session = await SessionManager.getUserData();
                          String? formatTime(TimeOfDay? time) {
                            if (time == null) return null;
                            return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
                          }

                          final payload = {
                            'description': description,
                            'maintenance_type': chosenType,
                            'vehicle_id': vehicle['vehicle_id'],
                            'user_id': session['userId'],
                            'category': chosenCategory,
                            'incident_date': incidentDate != null
                                ? '${incidentDate!.year}-${incidentDate!.month.toString().padLeft(2, '0')}-${incidentDate!.day.toString().padLeft(2, '0')}'
                                : null,
                            'incident_time': formatTime(incidentTime),
                            'is_resolved': false,
                          };
                          try {
                            final response = await http
                                .post(
                                  Uri.parse('$backendUrl/vehicles/maintenance'),
                                  headers: await _maintenanceHeaders(),
                                  body: jsonEncode(payload),
                                )
                                .timeout(const Duration(seconds: 15));
                            if (response.statusCode == 200 ||
                                response.statusCode == 201) {
                              widget.onRefreshNeeded();
                              _fetchLiveFleetData();
                              if (context.mounted) {
                                Navigator.pop(context);
                                Navigator.pop(context);
                                _showSnackBar(
                                  'New issue logged. Status updated.',
                                  Colors.orange,
                                );
                              }
                            } else {
                              if (context.mounted) {
                                String message =
                                    'Failed to log issue (${response.statusCode}).';
                                try {
                                  final decoded = jsonDecode(response.body);
                                  if (decoded is Map &&
                                      decoded['message'] != null) {
                                    message = decoded['message'].toString();
                                  }
                                } catch (_) {}
                                _showSnackBar(message, Colors.red);
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              _showSnackBar(
                                e.toString().contains('TimeoutException')
                                    ? 'The server took too long to save the incident.'
                                    : 'Unable to save the incident: $e',
                                Colors.red,
                              );
                            }
                          } finally {
                            setModalState(() => isSaving = false);
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: EnterpriseLoadingIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Log Incident',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMarkRepairedDialog(Map<String, dynamic> log, int vehicleId) {
    DateTime? repairDate = DateTime.now();
    TimeOfDay? repairTime = TimeOfDay.now();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            title: Text(
              'Mark Issue as Repaired',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Resolving this issue will update the vehicle's status back to 'Good' and release it for dispatch.",
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: repairDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setModalState(() => repairDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Date Repaired',
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: Text(
                              repairDate != null
                                  ? "${repairDate!.month}/${repairDate!.day}/${repairDate!.year}"
                                  : "Select Date",
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: repairTime ?? TimeOfDay.now(),
                            );
                            if (picked != null) {
                              setModalState(() => repairTime = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Time Repaired',
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: Text(
                              repairTime != null
                                  ? repairTime!.format(context)
                                  : "Select Time",
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        setModalState(() => isSaving = true);
                        String? formatTime(TimeOfDay? time) {
                          if (time == null) return null;
                          return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
                        }

                        final payload = {
                          'maintenance_id': log['maintenance_id'],
                          'vehicle_id': vehicleId,
                          'repair_date': repairDate != null
                              ? '${repairDate!.year}-${repairDate!.month.toString().padLeft(2, '0')}-${repairDate!.day.toString().padLeft(2, '0')}'
                              : null,
                          'repair_time': formatTime(repairTime),
                        };
                        try {
                          final response = await http.put(
                            Uri.parse('$backendUrl/vehicles/maintenance'),
                            headers: await _maintenanceHeaders(),
                            body: jsonEncode(payload),
                          );
                          if (response.statusCode == 200) {
                            widget.onRefreshNeeded();
                            _fetchLiveFleetData();
                            if (context.mounted) {
                              Navigator.pop(context);
                              Navigator.pop(context);
                              _showSnackBar(
                                'Vehicle marked as repaired!',
                                Colors.green,
                              );
                            }
                          } else {
                            if (context.mounted) {
                              _showSnackBar(
                                'Failed to update log (${response.statusCode}).',
                                Colors.red,
                              );
                            }
                          }
                        } catch (e) {
                          if (context.mounted) {
                            _showSnackBar('Network error.', Colors.red);
                          }
                        } finally {
                          setModalState(() => isSaving = false);
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: EnterpriseLoadingIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Confirm Repair',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMaintenanceManagerModal(
    BuildContext context,
    Map<String, dynamic> vehicle,
    List<dynamic> logs,
  ) {
    String currentSort = 'Ongoing First';
    int selectedMonth = 0;
    int selectedYear = 0;
    DateTime? selectedDate;
    int currentPage = 0;
    const int pageSize = 8;
    final int vehicleId = int.tryParse(vehicle['vehicle_id'].toString()) ?? 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          DateTime? parseLogDate(dynamic item) {
            final raw = item['incident_date'] ?? item['repair_date'];
            return DateTime.tryParse(raw?.toString() ?? '');
          }

          final availableYears =
              logs
                  .map(parseLogDate)
                  .whereType<DateTime>()
                  .map((date) => date.year)
                  .toSet()
                  .toList()
                ..sort((a, b) => b.compareTo(a));
          final filteredLogs = logs.where((log) {
            final logDate = parseLogDate(log);
            if (logDate == null)
              return selectedYear == 0 &&
                  selectedMonth == 0 &&
                  selectedDate == null;
            final matchesYear =
                selectedYear == 0 || logDate.year == selectedYear;
            final matchesMonth =
                selectedMonth == 0 || logDate.month == selectedMonth;
            final matchesDate =
                selectedDate == null ||
                (logDate.year == selectedDate!.year &&
                    logDate.month == selectedDate!.month &&
                    logDate.day == selectedDate!.day);
            return matchesYear && matchesMonth && matchesDate;
          }).toList();
          List<dynamic> sortedLogs = List.from(filteredLogs);

          sortedLogs.sort((a, b) {
            DateTime parseDateTime(dynamic item) {
              final date = item['incident_date']?.toString() ?? '';
              final time = item['incident_time']?.toString() ?? '00:00:00';
              return DateTime.tryParse("$date $time") ?? DateTime(2000);
            }

            DateTime dateA = parseDateTime(a);
            DateTime dateB = parseDateTime(b);
            bool aResolved = a['is_resolved'] == true;
            bool bResolved = b['is_resolved'] == true;

            if (currentSort == 'Newest First') return dateB.compareTo(dateA);
            if (currentSort == 'Oldest First') return dateA.compareTo(dateB);
            if (currentSort == 'Ongoing First') {
              if (aResolved != bResolved) return aResolved ? 1 : -1;
            }
            if (currentSort == 'Fixed First') {
              if (aResolved != bResolved) return aResolved ? -1 : 1;
            }
            return dateB.compareTo(dateA);
          });

          final totalPages = max(1, (sortedLogs.length / pageSize).ceil());
          final safePage = min(currentPage, totalPages - 1);
          final pageStart = safePage * pageSize;
          final pageLogs = sortedLogs.sublist(
            pageStart,
            min(pageStart + pageSize, sortedLogs.length),
          );

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Maintenance: ${vehicle['plate_number']}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            content: SizedBox(
              width: 700,
              height: 500,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (!_isAdmin)
                        ElevatedButton.icon(
                          onPressed: () => _showLogIssueDialog(vehicle),
                          icon: const Icon(
                            Icons.add_alert,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: const Text(
                            "Log New Issue",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      Container(
                        width: 180,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: currentSort,
                            isExpanded: true,
                            dropdownColor: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 14,
                            ),
                            items:
                                [
                                      'Newest First',
                                      'Oldest First',
                                      'Ongoing First',
                                      'Fixed First',
                                    ]
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (val) => setModalState(
                              () => currentSort = val ?? 'Ongoing First',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _maintenanceFilterDropdown<int>(
                        label: 'Year',
                        value: selectedYear,
                        items: [0, ...availableYears],
                        itemLabel: (value) =>
                            value == 0 ? 'All Years' : '$value',
                        onChanged: (value) => setModalState(() {
                          selectedYear = value ?? 0;
                          currentPage = 0;
                        }),
                        isDark: isDark,
                      ),
                      _maintenanceFilterDropdown<int>(
                        label: 'Month',
                        value: selectedMonth,
                        items: [0, ...List.generate(12, (index) => index + 1)],
                        itemLabel: (value) =>
                            value == 0 ? 'All Months' : _monthName(value),
                        onChanged: (value) => setModalState(() {
                          selectedMonth = value ?? 0;
                          currentPage = 0;
                        }),
                        isDark: isDark,
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null) {
                            setModalState(() {
                              selectedDate = picked;
                              currentPage = 0;
                            });
                          }
                        },
                        icon: const Icon(Icons.event, size: 16),
                        label: Text(
                          selectedDate == null
                              ? 'Any Date'
                              : '${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}',
                        ),
                      ),
                      if (selectedDate != null ||
                          selectedMonth != 0 ||
                          selectedYear != 0)
                        TextButton(
                          onPressed: () => setModalState(() {
                            selectedDate = null;
                            selectedMonth = 0;
                            selectedYear = 0;
                            currentPage = 0;
                          }),
                          child: const Text('Clear Filters'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (sortedLogs.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Showing ${pageStart + 1}-${min(pageStart + pageSize, sortedLogs.length)} of ${sortedLogs.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade700,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Previous page',
                              onPressed: safePage > 0
                                  ? () => setModalState(() => currentPage--)
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text('${safePage + 1} / $totalPages'),
                            IconButton(
                              tooltip: 'Next page',
                              onPressed: safePage < totalPages - 1
                                  ? () => setModalState(() => currentPage++)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ],
                    ),
                  Expanded(
                    child: sortedLogs.isEmpty
                        ? Center(
                            child: Text(
                              "No maintenance records found.",
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.separated(
                            itemCount: pageLogs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final log = pageLogs[index];
                              final bool isResolved =
                                  log['is_resolved'] == true;
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1E293B)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isResolved
                                        ? Colors.green.withValues(alpha: 0.5)
                                        : Colors.orange.withValues(alpha: 0.5),
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                log['category'] ?? 'General',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.withValues(
                                                    alpha: 0.12,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  (log['maintenance_type'] ??
                                                          'repair')
                                                      .toString()
                                                      .toUpperCase(),
                                                  style: const TextStyle(
                                                    color: Colors.blue,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isResolved
                                                      ? Colors.green.withValues(
                                                          alpha: 0.2,
                                                        )
                                                      : Colors.orange
                                                            .withValues(
                                                              alpha: 0.2,
                                                            ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  isResolved
                                                      ? "FIXED"
                                                      : "ONGOING",
                                                  style: TextStyle(
                                                    color: isResolved
                                                        ? Colors.green
                                                        : Colors.orange,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            log['description'] ?? 'No details',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDark
                                                  ? Colors.grey.shade300
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "Incident: ${log['incident_date'] ?? 'N/A'} at ${log['incident_time'] ?? 'N/A'}",
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.grey.shade500
                                                  : Colors.grey.shade700,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (isResolved)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: Text(
                                                "Repaired: ${log['repair_date'] ?? 'N/A'} at ${log['repair_time'] ?? 'N/A'}",
                                                style: TextStyle(
                                                  color: isDark
                                                      ? Colors.green.shade400
                                                      : Colors.green.shade700,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (!isResolved && !_isAdmin)
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            _showMarkRepairedDialog(
                                              log,
                                              vehicleId,
                                            ),
                                        icon: const Icon(
                                          Icons.check_circle,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          "Mark Repaired",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.green.shade600,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _monthName(int month) {
    const names = [
      'All Months',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month.clamp(0, 12).toInt()];
  }

  Widget _maintenanceFilterDropdown<T extends Object>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T value) itemLabel,
    required ValueChanged<T?> onChanged,
    required bool isDark,
  }) {
    return Container(
      width: 145,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 12,
          ),
          hint: Text(label),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(itemLabel(item), overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // UI BUILD METHODS
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vehicles = _filteredVehicles
        .map((vehicle) => Map<String, dynamic>.from(vehicle as Map))
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 768;
          return ListView(
            padding: EdgeInsets.all(compact ? 16 : 24),
            children: [
              // 1. TOP ROW: Title on Left, Reload/Actions on Right
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: compact ? double.infinity : null,
                    child: Column(
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
                        const SizedBox(height: 4),
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
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // --- SEARCH BAR TOP RIGHT ---
                      SizedBox(
                        width: compact ? constraints.maxWidth - 32 : 260,
                        height: 42,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) => setState(() {
                            _searchQuery = value;
                            if (value.trim().isEmpty) _statusFilter = 'All';
                            _applyFiltersAndSort();
                          }),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 13,
                          ),
                          decoration: _inputDecoration(
                            isDark,
                            'Search plate or type',
                            Icons.search,
                          ),
                        ),
                      ),
                      if (_isAdmin) ...[
                        FilledButton.icon(
                          onPressed: () => _showVehicleModal(context),
                          icon: const Icon(Icons.add, size: 17),
                          label: const Text('Add Vehicle'),
                          style: FilledButton.styleFrom(
                            backgroundColor: EnterpriseColors.generativeAction,
                          ),
                        ),
                      ],
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _fetchLiveFleetData,
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: compact ? 12 : 24),

              // 2. CARDS BEFORE FILTERS
              if (_isLoading)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 800;
                    if (isNarrow) {
                      return GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.95,
                        children: List.generate(
                          4,
                          (_) => const EnterpriseSummaryCardSkeleton(),
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
                      ],
                    );
                  },
                )
              else
                _buildSummaryCards(isDark),

              SizedBox(height: compact ? 12 : 32),

              // 3. MAIN WORKSPACE TABLE (WITH FILTERS INSIDE)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EnterpriseDataGrid<Map<String, dynamic>>(
                    loading: _isLoading,
                    rows: vehicles,
                    rowKey: (vehicle) =>
                        vehicle['vehicle_id'] ??
                        vehicle['id'] ??
                        vehicle.hashCode,
                    height: 560,
                    readOnlyOnMobile: !_isAdmin,
                    // --- FILTERS INSIDE TABLE TOP LEFT ---
                    filterFields: [
                      _dropdown(
                        isDark: isDark,
                        width: 170,
                        value: _statusFilter,
                        values: [
                          'All',
                          'Available',
                          'Due Maintenance',
                          'Due Repair',
                        ],
                        onChanged: (value) {
                          setState(() {
                            _statusFilter = value ?? 'All';
                            _applyFiltersAndSort();
                          });
                        },
                      ),
                      const SizedBox(width: 12),
                      _dropdown(
                        isDark: isDark,
                        width: 170,
                        value: _currentSort,
                        values: _sortOptions,
                        onChanged: (value) {
                          setState(() {
                            _currentSort = value ?? 'Plate (A to Z)';
                            _applyFiltersAndSort();
                          });
                        },
                      ),
                    ],
                    columns: [
                      EnterpriseGridColumn(
                        label: 'Vehicle ID',
                        width: 110,
                        value: (vehicle) =>
                            (vehicle['vehicle_id'] ?? vehicle['id'] ?? '')
                                .toString(),
                      ),
                      EnterpriseGridColumn(
                        label: 'Plate number',
                        width: 170,
                        value: (vehicle) =>
                            (vehicle['plate_number'] ?? 'Unassigned')
                                .toString(),
                      ),
                      EnterpriseGridColumn(
                        label: 'Vehicle type',
                        width: 260,
                        value: (vehicle) =>
                            (vehicle['bus_type'] ?? 'Not specified').toString(),
                      ),
                      EnterpriseGridColumn(
                        label: 'Health status',
                        width: 190,
                        value: (vehicle) =>
                            (vehicle['health_status'] ?? 'Good').toString(),
                        cellBuilder: (context, vehicle) => Align(
                          alignment: Alignment.center,
                          child: _FleetStatusLabel(
                            status: (vehicle['health_status'] ?? 'Good')
                                .toString(),
                            dueType: vehicle['maintenance_due_type']
                                ?.toString(),
                            needsAttention: vehicle['needs_attention'] == true,
                          ),
                        ),
                      ),
                    ],
                    emptyTitle: _allVehicles.isEmpty
                        ? 'Register the first vehicle'
                        : 'Nothing matches the current search or filters',
                    emptyMessage: _allVehicles.isEmpty
                        ? 'Vehicle records are required before fleet assignments and maintenance can be tracked.'
                        : 'No vehicle records match the current plate, type, and status filters.',
                    emptyActionLabel: null,
                    onEmptyAction: null,
                    selectionActionsBuilder: _selectedVehicleActions,
                    onExportSelection: _exportVehicles,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards(bool isDark) {
    final cards = [
      (
        'Total Fleet',
        '$_totalVehicles',
        'Registered assets',
        Icons.directions_bus_outlined,
        const Color(0xFF3B82F6),
      ),
      (
        'Available',
        '$_availableVehicles',
        'Ready for dispatch',
        Icons.check_circle_outline,
        const Color(0xFF10B981),
      ),
      (
        'Due Maintenance',
        '$_maintenanceVehicles',
        'Maintenance due',
        Icons.build_circle_outlined,
        const Color(0xFFEF4444),
      ),
      (
        'Due Repair',
        '$_repairVehicles',
        'Repair unresolved',
        Icons.car_repair,
        const Color(0xFFF97316),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;

        final cardWidgets = cards.map((card) {
          final Color baseColor = card.$5;
          return Container(
            constraints: BoxConstraints(minHeight: isNarrow ? 70 : 112),
            width: isNarrow ? null : null,
            padding: EdgeInsets.all(isNarrow ? 10 : 16),
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: 0.08),
              border: Border.all(color: baseColor.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                if (!isNarrow)
                  Align(
                    alignment: Alignment.topLeft,
                    child: Icon(card.$4, color: baseColor, size: 20),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize:
                        MainAxisSize.min, // Prevents vertical overflow
                    children: [
                      Text(
                        card.$1,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: baseColor,
                          fontSize: isNarrow ? 11 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: isNarrow ? 2 : 8),
                      Text(
                        card.$2,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: isNarrow ? 19 : 28,
                          height: 1.0,
                        ),
                      ),
                      SizedBox(height: isNarrow ? 1 : 4),
                      Text(
                        card.$3,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          fontSize: isNarrow ? 10 : 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList();

        if (isNarrow) {
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.95,
            children: cardWidgets,
          );
        }

        final cardWidth = (constraints.maxWidth - 48) / 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cardWidgets
              .map((card) => SizedBox(width: cardWidth, child: card))
              .toList(),
        );
      },
    );
  }

  InputDecoration _inputDecoration(bool isDark, String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF64748B)),
      filled: true,
      fillColor: Theme.of(context).cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
    );
  }

  Widget _dropdown({
    required bool isDark,
    required double width,
    required String value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = values.contains(value) ? value : values.first;
    return Container(
      width: width,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          dropdownColor: Theme.of(context).cardColor,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          items: values
              .toSet()
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item == 'All' ? 'All statuses' : item),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _FleetStatusLabel extends StatelessWidget {
  const _FleetStatusLabel({
    required this.status,
    this.dueType,
    this.needsAttention = false,
  });

  final String status;
  final String? dueType;
  final bool needsAttention;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final effectiveDueType = dueType ?? (needsAttention ? 'maintenance' : null);
    final isDue =
        effectiveDueType == 'maintenance' || effectiveDueType == 'repair';
    final displayStatus = isDue
        ? (effectiveDueType == 'repair' ? 'Due Repair' : 'Due Maintenance')
        : (normalized.contains('maintenance') || normalized.contains('repair')
              ? 'Good'
              : status);
    final color = isDue
        ? (effectiveDueType == 'repair'
              ? const Color(0xFFF97316)
              : EnterpriseColors.danger)
        : EnterpriseColors.success;
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            displayStatus,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// REGISTER VEHICLE DIALOG
// ============================================================================
class RegisterVehicleDialog extends StatefulWidget {
  final Map<String, dynamic>? vehicle;
  final bool isAdmin;
  final VoidCallback? onDelete;

  const RegisterVehicleDialog({
    super.key,
    this.vehicle,
    required this.isAdmin,
    this.onDelete,
  });

  @override
  State<RegisterVehicleDialog> createState() => _RegisterVehicleDialogState();
}

class _RegisterVehicleDialogState extends State<RegisterVehicleDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isWritingUnlocked = false;

  late TextEditingController _plateController;
  late TextEditingController _modelController;
  late TextEditingController _vehicleTypeController;
  late TextEditingController _modelYearController;
  late TextEditingController _insuranceNoController;
  late TextEditingController _insuranceExpiryController;
  late TextEditingController _crNoController;
  late TextEditingController _crDateController;
  late TextEditingController _orNoController;
  late TextEditingController _orExpiryController;

  String _selectedCapacity = '15 Seats';

  @override
  void initState() {
    super.initState();
    final bool isEdit = widget.vehicle != null;
    _isWritingUnlocked = !isEdit && widget.isAdmin;

    String parsedModel = '';
    if (isEdit) {
      String rawBusType = widget.vehicle!['bus_type'] ?? '';
      if (rawBusType.contains(' - ')) {
        _selectedCapacity = rawBusType.split(' - ').first;
        parsedModel = rawBusType.split(' - ').last;
      } else {
        parsedModel = rawBusType;
      }
    }

    _plateController = TextEditingController(
      text: isEdit ? (widget.vehicle!['plate_number'] ?? '') : '',
    );
    _modelController = TextEditingController(text: parsedModel);
    _vehicleTypeController = TextEditingController(
      text: isEdit
          ? (widget.vehicle!['vehicle_type'] ?? 'Van').toString()
          : 'Van',
    );
    _modelYearController = TextEditingController(
      text: isEdit ? (widget.vehicle!['model_year'] ?? '') : '',
    );
    _insuranceNoController = TextEditingController(
      text: isEdit ? (widget.vehicle!['insurance_policy_no'] ?? '') : '',
    );
    _insuranceExpiryController = TextEditingController(
      text: isEdit ? (widget.vehicle!['insurance_expiry'] ?? '') : '',
    );
    _crNoController = TextEditingController(
      text: isEdit ? (widget.vehicle!['cr_no'] ?? '') : '',
    );
    _crDateController = TextEditingController(
      text: isEdit ? (widget.vehicle!['cr_date'] ?? '') : '',
    );
    _orNoController = TextEditingController(
      text: isEdit ? (widget.vehicle!['or_no'] ?? '') : '',
    );
    _orExpiryController = TextEditingController(
      text: isEdit ? (widget.vehicle!['or_expiry'] ?? '') : '',
    );
  }

  InputDecoration _fieldStyle({
    required BuildContext context,
    required String label,
    required IconData icon,
    bool isDatePicker = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool active = _isWritingUnlocked;
    final fillColor = active
        ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))
        : Theme.of(context).cardColor;
    final textColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);
    final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: textColor, size: 20),
      suffixIcon: isDatePicker
          ? Icon(Icons.calendar_today, size: 18, color: textColor)
          : null,
      filled: true,
      fillColor: fillColor,
      labelStyle: TextStyle(
        color: textColor,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
    );
  }

  Future<void> _selectDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    if (!_isWritingUnlocked) return;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2040),
    );
    if (picked != null) {
      setState(
        () => controller.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}",
      );
    }
  }

  Future<void> _submitVehicleForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final bool isEditMode = widget.vehicle != null;

    String cleanStr(TextEditingController controller, String fallback) {
      final txt = controller.text.trim();
      return txt.isEmpty ? fallback : txt;
    }

    try {
      final http.Response response;
      final bodyData = jsonEncode({
        'role': 'admin',
        'plate_number': cleanStr(
          _plateController,
          'TBD-${Random().nextInt(900) + 100}',
        ),
        'bus_type':
            "$_selectedCapacity - ${cleanStr(_modelController, 'Standard Shuttle')}",
        'vehicle_type': cleanStr(_vehicleTypeController, 'Van'),
        'model_year': cleanStr(_modelYearController, '2026'),
        'insurance_policy_no': cleanStr(_insuranceNoController, 'N/A'),
        'insurance_expiry': cleanStr(_insuranceExpiryController, '2027-01-01'),
        'cr_no': cleanStr(_crNoController, 'N/A'),
        'cr_date': cleanStr(_crDateController, 'N/A'),
        'or_no': cleanStr(_orNoController, 'N/A'),
        'or_expiry': cleanStr(_orExpiryController, 'N/A'),
      });

      if (isEditMode) {
        response = await http
            .put(
              Uri.parse(
                '$backendUrl/vehicles/update/${widget.vehicle!['vehicle_id']}',
              ),
              headers: {'Content-Type': 'application/json'},
              body: bodyData,
            )
            .timeout(const Duration(seconds: 15));
      } else {
        response = await http
            .post(
              Uri.parse('$backendUrl/vehicles'),
              headers: {'Content-Type': 'application/json'},
              body: bodyData,
            )
            .timeout(const Duration(seconds: 15));
      }

      final responseData = jsonDecode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          responseData['success'] == true) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditMode
                  ? "Asset profile changes committed!"
                  : "Fleet vehicle added to registry securely!",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        throw Exception(responseData['message'] ?? "Operational rejection.");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Submission Error: $e",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _plateController.dispose();
    _modelController.dispose();
    _vehicleTypeController.dispose();
    _modelYearController.dispose();
    _insuranceNoController.dispose();
    _insuranceExpiryController.dispose();
    _crNoController.dispose();
    _crDateController.dispose();
    _orNoController.dispose();
    _orExpiryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditMode = widget.vehicle != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      title: Text(
        isEditMode ? 'Fleet Vehicle Specification' : 'Register System Vehicle',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 24,
          color: textColor,
        ),
      ),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Basic Information",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3B82F6),
                    fontSize: 14,
                  ),
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _plateController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: textColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Plate Number',
                          icon: Icons.badge_outlined,
                        ),
                        validator: (val) => val!.isEmpty ? "Required" : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _modelController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: textColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Vehicle Model',
                          icon: Icons.directions_car_outlined,
                        ),
                        validator: (val) => val!.isEmpty ? "Required" : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _vehicleTypeController,
                  readOnly: !_isWritingUnlocked,
                  style: TextStyle(color: textColor),
                  decoration: _fieldStyle(
                    context: context,
                    label: 'Vehicle Type (e.g. Van, Jeep)',
                    icon: Icons.category_outlined,
                  ),
                  validator: (val) => val!.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _modelYearController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: textColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Model Year',
                          icon: Icons.date_range_outlined,
                        ),
                        validator: (val) => val!.isEmpty ? "Required" : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCapacity,
                        dropdownColor: Theme.of(context).cardColor,
                        style: TextStyle(color: textColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Capacity',
                          icon: Icons.group_outlined,
                        ),
                        onChanged: !_isWritingUnlocked
                            ? null
                            : (val) => setState(() => _selectedCapacity = val!),
                        items: ['12 Seats', '15 Seats', '18 Seats']
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  "Documents & Expirations",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3B82F6),
                    fontSize: 14,
                  ),
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _insuranceNoController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: textColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Insurance Policy No.',
                          icon: Icons.gavel_outlined,
                        ),
                        validator: (val) => val!.isEmpty ? "Required" : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _insuranceExpiryController,
                        readOnly: true,
                        style: TextStyle(color: textColor),
                        onTap: () =>
                            _selectDate(context, _insuranceExpiryController),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Expiry',
                          icon: Icons.event_busy_outlined,
                          isDatePicker: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _crNoController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: textColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'CR No.',
                          icon: Icons.article_outlined,
                        ),
                        validator: (val) => val!.isEmpty ? "Required" : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _crDateController,
                        readOnly: true,
                        style: TextStyle(color: textColor),
                        onTap: () => _selectDate(context, _crDateController),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'CR Date',
                          icon: Icons.calendar_today_outlined,
                          isDatePicker: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _orNoController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: textColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'OR No.',
                          icon: Icons.receipt_long_outlined,
                        ),
                        validator: (val) => val!.isEmpty ? "Required" : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _orExpiryController,
                        readOnly: true,
                        style: TextStyle(color: textColor),
                        onTap: () => _selectDate(context, _orExpiryController),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'OR Expiry',
                          icon: Icons.history_toggle_off_outlined,
                          isDatePicker: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.only(bottom: 24, right: 24, left: 24),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (isEditMode && widget.isAdmin)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (widget.onDelete != null) widget.onDelete!();
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.isAdmin && isEditMode && !_isWritingUnlocked)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF64748B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    onPressed: () => setState(() => _isWritingUnlocked = true),
                    child: const Text(
                      'Update Details',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (widget.isAdmin)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    onPressed: _isLoading ? null : _submitVehicleForm,
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: EnterpriseLoadingIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            isEditMode ? 'Save Changes' : 'Register Vehicle',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
