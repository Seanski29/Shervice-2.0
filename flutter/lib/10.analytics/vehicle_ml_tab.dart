import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../layouts/enterprise/enterprise_theme.dart';
import 'package:http/http.dart' as http;

class VehicleMlTab extends StatefulWidget {
  final List<dynamic> vehicles;
  final String backendUrl;
  final VoidCallback onSyncAction;

  const VehicleMlTab({
    super.key,
    required this.vehicles,
    required this.backendUrl,
    required this.onSyncAction,
  });

  @override
  State<VehicleMlTab> createState() => _VehicleMlTabState();
}

class _VehicleMlChip extends StatelessWidget {
  const _VehicleMlChip({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: outlined ? 0.08 : 0.1),
        border: outlined
            ? Border.all(color: color.withValues(alpha: 0.5))
            : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _VehicleMlTabState extends State<VehicleMlTab> {
  String _searchQuery = '';
  String _currentSort = 'Due Maintenance first';
  int _currentPage = 0;
  static const int _itemsPerPage = 10;

  List<dynamic> get _processedVehicles {
    List<dynamic> tempV = widget.vehicles.where((v) {
      final plate = (v['plate_number'] ?? '').toString().toLowerCase();
      final type = (v['bus_type'] ?? '').toString().toLowerCase();
      final dbStatus = (v['health_status'] ?? 'Excellent').toString();

      final double daysRemaining =
          (v['live_risk_score'] as num?)?.toDouble() ?? 0.0;

      String dynamicStatus = 'Excellent';
      if (v['needs_attention'] == true) {
        dynamicStatus = v['maintenance_due_type'] == 'repair'
            ? 'Due Repair'
            : 'Due Maintenance';
      } else if (daysRemaining <= 30.0) {
        dynamicStatus = 'Fair';
      } else if (daysRemaining <= 90.0) {
        dynamicStatus = 'Good';
      } else {
        dynamicStatus = 'Excellent';
      }

      bool matchesSearch =
          plate.contains(_searchQuery.toLowerCase()) ||
          type.contains(_searchQuery.toLowerCase());
      bool matchesFilter = true;
      if (_currentSort.startsWith('Condition: ')) {
        matchesFilter =
            dynamicStatus == _currentSort.replaceAll('Condition: ', '');
      }
      return matchesSearch && matchesFilter;
    }).toList();

    tempV.sort((a, b) {
      final pA = (a['plate_number'] ?? '').toString().toLowerCase();
      final pB = (b['plate_number'] ?? '').toString().toLowerCase();
      if (_currentSort == 'A to Z') return pA.compareTo(pB);
      if (_currentSort == 'Z to A') return pB.compareTo(pA);
      final attentionA = _conditionRank(a);
      final attentionB = _conditionRank(b);
      if (attentionA != attentionB) return attentionA.compareTo(attentionB);
      return pA.compareTo(pB);
    });
    return tempV;
  }

  int _conditionRank(dynamic vehicle) {
    final dbStatus = (vehicle['health_status'] ?? 'Excellent').toString();
    final daysRemaining =
        (vehicle['live_risk_score'] as num?)?.toDouble() ?? 0.0;
    if (vehicle['needs_attention'] == true) {
      return 0;
    }
    if (daysRemaining <= 30.0) return 1;
    if (daysRemaining <= 90.0) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color borderColor = isDark
        ? Colors.grey.shade700
        : Colors.grey.shade300;

    final vehicles = _processedVehicles;
    final int totalPages = max(1, (vehicles.length / _itemsPerPage).ceil());
    final List<dynamic> paginatedVehicles = vehicles.isEmpty
        ? []
        : vehicles.sublist(
            _currentPage * _itemsPerPage,
            min((_currentPage + 1) * _itemsPerPage, vehicles.length),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 350,
                minWidth: isMobile ? double.infinity : 200,
              ),
              child: SizedBox(
                height: 42,
                child: TextField(
                  onChanged: (value) => setState(() {
                    _searchQuery = value;
                    _currentPage = 0;
                  }),
                  style: TextStyle(color: textColor, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search vehicles...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: Colors.grey.shade500,
                    ),
                    filled: true,
                    fillColor: cardBg,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor),
                    ),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 230,
                minWidth: isMobile ? double.infinity : 150,
              ),
              child: SizedBox(
                height: 42,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _currentSort,
                      dropdownColor: cardBg,
                      icon: Icon(
                        Icons.sort,
                        size: 18,
                        color: Colors.grey.shade500,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                      items:
                          [
                                'Due Maintenance first',
                                'Due Repair first',
                                'A to Z',
                                'Z to A',
                                'Condition: Excellent',
                                'Condition: Good',
                                'Condition: Fair',
                                'Condition: Due Maintenance',
                                'Condition: Due Repair',
                              ]
                              .map(
                                (String value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _currentSort = val;
                            _currentPage = 0;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: cardBg,
                border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                tooltip: 'Sync AI Forecasts',
                onPressed: widget.onSyncAction,
                icon: const Icon(
                  Icons.sync,
                  color: Color(0xFF3B82F6),
                  size: 20,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: vehicles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.car_crash,
                        size: 48,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No records found.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: paginatedVehicles.length,
                  itemBuilder: (context, index) {
                    final vehicle = paginatedVehicles[index];
                    final String dbStatus =
                        vehicle['health_status'] ?? 'Excellent';
                    final double daysRemaining =
                        (vehicle['live_risk_score'] as num?)?.toDouble() ?? 0.0;

                    String statusLabel = 'Excellent';
                    Color statusColor = const Color(0xFF10B981);
                    if (vehicle['needs_attention'] == true) {
                      if (vehicle['maintenance_due_type'] == 'repair') {
                        statusLabel = 'Due Repair';
                        statusColor = const Color(0xFFF97316);
                      } else {
                        statusLabel = 'Due Maintenance';
                        statusColor = const Color(0xFFEF4444);
                      }
                    } else if (daysRemaining <= 30.0) {
                      statusLabel = 'Fair';
                      statusColor = const Color(0xFFF97316);
                    } else if (daysRemaining <= 90.0) {
                      statusLabel = 'Good';
                      statusColor = const Color(0xFFF59E0B);
                    } else {
                      statusLabel = 'Excellent';
                      statusColor = const Color(0xFF10B981);
                    }

                    Color mlColor = daysRemaining <= 7.0
                        ? const Color(0xFFEF4444)
                        : (daysRemaining <= 30.0
                              ? const Color(0xFFF97316)
                              : (daysRemaining <= 90.0
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF10B981)));

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: borderColor),
                      ),
                      color: cardBg,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => MlPredictionDialog(
                              vehicle: vehicle,
                              backendUrl: widget.backendUrl,
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: isMobile
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.directions_car,
                                            color: Colors.purple,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                vehicle['plate_number'] ??
                                                    'Unknown',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: textColor,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.directions_bus,
                                                    size: 14,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      vehicle['bus_type'] ??
                                                          'Unknown Type',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Color(
                                                          0xFF64748B,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _VehicleMlChip(
                                          label:
                                              '${daysRemaining.toStringAsFixed(0)} Days',
                                          color: mlColor,
                                          outlined: true,
                                        ),
                                        _VehicleMlChip(
                                          label: statusLabel,
                                          color: statusColor,
                                        ),
                                        if (vehicle['maintenance_target_date'] !=
                                            null)
                                          _VehicleMlChip(
                                            label:
                                                'Target: ${vehicle['maintenance_target_date']}',
                                            color: statusColor,
                                            outlined: true,
                                          ),
                                      ],
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.directions_car,
                                        color: Colors.purple,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            vehicle['plate_number'] ??
                                                'Unknown',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: textColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.directions_bus,
                                                size: 14,
                                                color: Color(0xFF64748B),
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  vehicle['bus_type'] ??
                                                      'Unknown Type',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        alignment: WrapAlignment.end,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: mlColor.withValues(
                                                  alpha: 0.5,
                                                ),
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              color: mlColor.withValues(
                                                alpha: 0.08,
                                              ),
                                            ),
                                            child: Text(
                                              '${daysRemaining.toStringAsFixed(0)} Days',
                                              style: TextStyle(
                                                color: mlColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              statusLabel,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          if (vehicle['maintenance_target_date'] !=
                                              null)
                                            Text(
                                              'Target: ${vehicle['maintenance_target_date']}',
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: Colors.grey,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (totalPages > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${(_currentPage * _itemsPerPage) + 1} - ${min((_currentPage + 1) * _itemsPerPage, vehicles.length)} of ${vehicles.length} records',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                  const SizedBox(width: 24),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.chevron_left, color: textColor),
                        onPressed: _currentPage > 0
                            ? () => setState(() => _currentPage--)
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_currentPage + 1} / $totalPages',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3B82F6),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.chevron_right, color: textColor),
                        onPressed: _currentPage < totalPages - 1
                            ? () => setState(() => _currentPage++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class MlPredictionDialog extends StatefulWidget {
  final dynamic vehicle;
  final String backendUrl;

  const MlPredictionDialog({
    super.key,
    required this.vehicle,
    required this.backendUrl,
  });

  @override
  State<MlPredictionDialog> createState() => _MlPredictionDialogState();
}

class _MlPredictionDialogState extends State<MlPredictionDialog> {
  bool _isRunning = true;
  Map<String, dynamic>? _results;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    try {
      // 🔥 FIX: Reverted to /vehicles/predict/ because backendUrl already includes /api
      final res = await http
          .get(
            Uri.parse(
              '${widget.backendUrl}/vehicles/predict/${widget.vehicle['vehicle_id']}',
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _results = jsonDecode(res.body);
          _isRunning = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _error = "Server returned ${res.statusCode}.";
            _isRunning = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Connection error.";
          _isRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: isMobile ? double.infinity : 760,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'ML Forecast: ${widget.vehicle['plate_number']}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isDark
                        ? Colors.grey.shade400
                        : const Color(0xFF64748B),
                  ),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            Divider(
              height: 24,
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            ),
            if (_isRunning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Colors.purple),
                      SizedBox(height: 16),
                      Text(
                        "Building maintenance forecast...",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              )
            else
              _buildResultsView(isMobile, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsView(bool isMobile, bool isDark) {
    final responseDays = (_results!['risk_index'] as num?)?.toDouble() ?? 0.0;
    final storedDays = (widget.vehicle['live_risk_score'] as num?)?.toDouble();
    final double daysRemaining = storedDays ?? responseDays;
    final Map<String, dynamic> telemetry = _results!['telemetry_metrics'] ?? {};
    final bool dueMaintenance = widget.vehicle['needs_attention'] == true;
    final bool dueRepair =
        dueMaintenance && widget.vehicle['maintenance_due_type'] == 'repair';

    Color statusColor;
    Color bgColor;
    String statusLabel;
    String statusDesc;

    if (dueMaintenance) {
      statusColor = dueRepair
          ? const Color(0xFFF97316)
          : const Color(0xFFEF4444);
      bgColor = dueRepair
          ? (isDark ? const Color(0xFF451A03) : const Color(0xFFFFF7ED))
          : (isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2));
      statusLabel = dueRepair ? 'DUE REPAIR' : 'DUE MAINTENANCE';
      statusDesc = dueRepair
          ? 'Staff recorded an unresolved repair issue for this vehicle.'
          : 'Staff recorded an unresolved maintenance issue for this vehicle.';
    } else if (daysRemaining <= 7.0) {
      statusColor = const Color(0xFFDC2626);
      bgColor = isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2);
      statusLabel = 'CRITICAL FORECAST';
      statusDesc =
          'The model forecasts that maintenance may be required within 7 days.';
    } else if (daysRemaining <= 30.0) {
      statusColor = const Color(0xFFF97316);
      bgColor = isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB);
      statusLabel = 'FAIR CONDITION';
      statusDesc =
          'Asset is operational, but workload indicates maintenance is approaching.';
    } else if (daysRemaining <= 90.0) {
      statusColor = const Color(0xFFF59E0B);
      bgColor = isDark ? const Color(0xFF422006) : const Color(0xFFFEF3C7);
      statusLabel = 'GOOD CONDITION';
      statusDesc =
          'Asset is performing well, with nominal wear and tear detected.';
    } else {
      statusColor = const Color(0xFF10B981);
      bgColor = isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5);
      statusLabel = 'EXCELLENT CONDITION';
      statusDesc =
          'Trip workload and maintenance history forecast stable operations for now.';
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                '${(_results!['telemetry_metrics']?['model'] ?? 'WORKLOAD').toString().toUpperCase()} MAINTENANCE FORECAST',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                statusDesc,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final int columns = isMobile ? 2 : 3;
            final double cardWidth =
                (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildStatCard(
                  'Days',
                  '${daysRemaining.toStringAsFixed(0)} Days Left',
                  Icons.calendar_month,
                  statusColor,
                  cardWidth,
                  isDark,
                ),
                _buildStatCard(
                  'Trips',
                  '${telemetry['total_trips']} trips',
                  Icons.route,
                  const Color(0xFF3B82F6),
                  cardWidth,
                  isDark,
                ),
                _buildStatCard(
                  'Age',
                  '${telemetry['age_years']} yrs',
                  Icons.calendar_today,
                  const Color(0xFFF59E0B),
                  cardWidth,
                  isDark,
                ),
                _buildStatCard(
                  'Repairs',
                  '${telemetry['repair_count'] ?? telemetry['past_repairs_count'] ?? 0}',
                  Icons.build,
                  const Color(0xFF8B5CF6),
                  cardWidth,
                  isDark,
                ),
                _buildStatCard(
                  'Maintenance',
                  '${telemetry['maintenance_count'] ?? 0}',
                  Icons.handyman,
                  const Color(0xFF14B8A6),
                  cardWidth,
                  isDark,
                ),
                _buildStatCard(
                  'Pax 90d',
                  '${telemetry['passengers_last_90_days'] ?? 0}',
                  Icons.groups,
                  const Color(0xFF0EA5E9),
                  cardWidth,
                  isDark,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    double width,
    bool isDark,
  ) {
    final fill = Color.lerp(
      isDark ? const Color(0xFF0F172A) : Colors.white,
      color,
      isDark ? 0.18 : 0.07,
    )!;
    return Container(
      width: width,
      height: 108,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.72)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : EnterpriseColors.main,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
