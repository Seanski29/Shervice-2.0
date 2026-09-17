import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
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

class _VehicleMlTabState extends State<VehicleMlTab> {
  String _searchQuery = '';
  String _currentSort = 'Needs Attention first';
  int _currentPage = 0;
  final int _itemsPerPage = 6;

  List<dynamic> get _processedVehicles {
    List<dynamic> tempV = widget.vehicles.where((v) {
      final plate = (v['plate_number'] ?? '').toString().toLowerCase();
      final type = (v['bus_type'] ?? '').toString().toLowerCase();
      final dbStatus = (v['health_status'] ?? 'Excellent').toString();

      final double daysRemaining =
          (v['live_risk_score'] as num?)?.toDouble() ?? 0.0;

      String dynamicStatus = 'Excellent';
      if (v['needs_attention'] == true ||
          dbStatus.toLowerCase().contains('maintenance') ||
          dbStatus.toLowerCase().contains('repair') ||
          daysRemaining <= 7.0) {
        dynamicStatus = 'Needs Attention';
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
    if (vehicle['needs_attention'] == true ||
        dbStatus.toLowerCase().contains('maintenance') ||
        dbStatus.toLowerCase().contains('repair') ||
        daysRemaining <= 7.0) {
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
                                'Needs Attention first',
                                'A to Z',
                                'Z to A',
                                'Condition: Excellent',
                                'Condition: Good',
                                'Condition: Fair',
                                'Condition: Needs Attention',
                              ]
                              .map(
                                (String value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                      onChanged: (val) {
                        if (val != null)
                          setState(() {
                            _currentSort = val;
                            _currentPage = 0;
                          });
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
                    if (vehicle['needs_attention'] == true ||
                        dbStatus.toLowerCase().contains('maintenance') ||
                        dbStatus.toLowerCase().contains('repair') ||
                        daysRemaining <= 7.0) {
                      statusLabel = 'Needs Attention';
                      statusColor = const Color(0xFFEF4444);
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
                          child: Row(
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      vehicle['plate_number'] ?? 'Unknown',
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
                                            overflow: TextOverflow.ellipsis,
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
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: mlColor.withOpacity(0.5),
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        color: mlColor.withOpacity(0.08),
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
                                        color: statusColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
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
        if (mounted)
          setState(() {
            _error = "Server returned ${res.statusCode}.";
            _isRunning = false;
          });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = "Connection error.";
          _isRunning = false;
        });
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
        width: isMobile ? double.infinity : 550,
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
                        "Compiling Multiple Linear Regression...",
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
    final double daysRemaining = (_results!['risk_index'] ?? 0.0);
    final Map<String, dynamic> telemetry = _results!['telemetry_metrics'] ?? {};

    Color statusColor;
    Color bgColor;
    String statusLabel;
    String statusDesc;

    if (daysRemaining <= 7.0) {
      statusColor = const Color(0xFFEF4444);
      bgColor = isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2);
      statusLabel = 'NEEDS MAINTENANCE';
      statusDesc =
          'Multiple Linear Regression forecasts breakdown within 7 days. Lockout triggered.';
    } else if (daysRemaining <= 30.0) {
      statusColor = const Color(0xFFF97316);
      bgColor = isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB);
      statusLabel = 'FAIR CONDITION';
      statusDesc =
          'Asset is operational, but structural wear indicates maintenance needed soon.';
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
          'Telemetry parameters forecast stable operations for the foreseeable future.';
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
          ),
          child: Column(
            children: [
              Text(
                'MULTIPLE LINEAR REGRESSION FORECAST',
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
            double cardWidth = isMobile
                ? (constraints.maxWidth - 12) / 2
                : (constraints.maxWidth - 36) / 4;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildStatCard(
                  'Forecast',
                  '${daysRemaining.toStringAsFixed(0)} Days Left',
                  Icons.calendar_month,
                  statusColor,
                  cardWidth,
                  isDark,
                ),
                _buildStatCard(
                  'Odometer',
                  '${telemetry['total_mileage_km']} km',
                  Icons.speed,
                  const Color(0xFF3B82F6),
                  cardWidth,
                  isDark,
                ),
                _buildStatCard(
                  'Fleet Age',
                  '${telemetry['age_years']} yrs',
                  Icons.calendar_today,
                  const Color(0xFFF59E0B),
                  cardWidth,
                  isDark,
                ),
                _buildStatCard(
                  'Repairs',
                  '${telemetry['past_repairs_count']} logs',
                  Icons.build,
                  const Color(0xFF8B5CF6),
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
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Colors.grey.shade400
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
