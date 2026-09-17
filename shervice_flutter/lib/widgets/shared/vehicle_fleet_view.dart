import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../constant.dart';
import 'universal_pagination.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchLiveFleetData();
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
      debugPrint("❌ Failed to fetch vehicles payload stack: $e");
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
    List<dynamic> temp = _allVehicles.where((v) {
      final plate = (v['plate_number'] ?? '').toString().toLowerCase();
      final type = (v['bus_type'] ?? '').toString().toLowerCase();
      final engine = (v['engine_no'] ?? '').toString().toLowerCase();

      final status = (v['health_status'] ?? 'Good').toString().toLowerCase();

      final matchesSearch =
          plate.contains(_searchQuery.toLowerCase()) ||
          type.contains(_searchQuery.toLowerCase()) ||
          engine.contains(_searchQuery.toLowerCase());

      bool matchesStatus = true;
      if (_statusFilter == 'Available') {
        matchesStatus = status == 'good' || status == 'excellent';
      } else if (_statusFilter == 'Needs Maintenance') {
        matchesStatus =
            status.contains('maintenance') || status.contains('repair');
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
      // Mock data for Skeletonizer
      return List.generate(
        5,
        (index) => {
          'vehicle_id': index,
          'plate_number': 'LOD-1234',
          'bus_type': '15 Seats - Standard Shuttle',
          'health_status': 'Good Condition',
          'engine_no': 'ENG-LOADING-XXXX',
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

  int get _totalVehicles => _isLoading ? 12 : _baseVehicles.length;
  int get _availableVehicles => _isLoading ? 10 : _baseVehicles.where((v) {
    final s = (v['health_status'] ?? 'Good').toString().toLowerCase();
    return s == 'good' || s == 'excellent';
  }).length;
  int get _maintenanceVehicles => _isLoading ? 2 : _baseVehicles.where((v) {
    final s = (v['health_status'] ?? '').toString().toLowerCase();
    return s.contains('maintenance') || s.contains('repair');
  }).length;

  Color _getStatusColor(String rawStatus) {
    final status = rawStatus.toLowerCase();
    if (status.contains('maintenance') || status.contains('repair')) {
      return const Color(0xFFEF4444);
    }
    return const Color(0xFF10B981);
  }

  void _confirmPurgeVehicle(Map<String, dynamic> vehicle) {
    if (!_isAdmin) return;
    final dynamic rawId =
        vehicle['vehicle_id'] ?? vehicle['id'] ?? vehicle['plate_number'];
    if (rawId == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Deletion',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to permanently erase fleet asset record entry ${vehicle['plate_number'] ?? 'this unit'}?',
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.black87,
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
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                final res = await http
                    .delete(Uri.parse('$backendUrl/vehicles/$rawId'))
                    .timeout(const Duration(seconds: 10));
                if (res.statusCode == 200) {
                  _showSnackBar(
                    'Fleet unit profile deleted successfully.',
                    Colors.orange,
                  );
                } else {
                  _showSnackBar(
                    'Deletion failed. Server error status: ${res.statusCode}',
                    Colors.red,
                  );
                }
              } catch (e) {
                _showSnackBar('Network connection error.', Colors.red);
              } finally {
                widget.onRefreshNeeded();
                _fetchLiveFleetData();
              }
            },
            child: const Text(
              'Delete permanently',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final double horizontalPadding = isMobile ? 12.0 : 24.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _fetchLiveFleetData,
      child: Skeletonizer(
        enabled: _isLoading,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 24.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTitleArea(isDark),
                        const SizedBox(height: 16),
                        _buildSearchAndFilterRow(isDark, isMobile),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildTitleArea(isDark),
                        const Spacer(),
                        _buildSearchAndFilterRow(isDark, isMobile),
                      ],
                    ),
              const SizedBox(height: 24),

              if (_isLoading || _allVehicles.isNotEmpty)
                _buildTopSummaryStats(isDark, isMobile),
              const SizedBox(height: 24),

              if (!_isLoading && _filteredVehicles.isEmpty)
                _buildEmptyState(isDark)
              else
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.grey.shade800
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _paginatedVehicles.length,
                        itemBuilder: (context, index) {
                          final v = _paginatedVehicles[index];
                          return _buildVehicleCard(
                            v,
                            isDark,
                            index == _paginatedVehicles.length - 1,
                          );
                        },
                      ),
                      _buildPaginationFooter(isDark),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleArea(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.subtitle,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilterRow(bool isDark, bool isMobile) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: isMobile ? double.infinity : 220,
          height: 44,
          child: TextField(
            onChanged: (value) {
              _searchQuery = value;
              _applyFiltersAndSort();
            },
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search plate/model...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF64748B),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 44,
          width: isMobile ? double.infinity : 160,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _currentSort,
              icon: const Icon(Icons.sort, size: 18, color: Color(0xFF64748B)),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
              ),
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              items: _sortOptions
                  .map(
                    (String value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _currentSort = val;
                    _applyFiltersAndSort();
                  });
                }
              },
            ),
          ),
        ),
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            border: Border.all(color: Colors.blue.shade600, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            onPressed: _isRefreshing ? null : _fetchLiveFleetData,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.blue, size: 20),
            padding: EdgeInsets.zero,
          ),
        ),
        if (_isAdmin)
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => _showVehicleModal(context),
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: const Text(
                'Add Vehicle',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopSummaryStats(bool isDark, bool isMobile) {
    final List<Map<String, dynamic>> stats = [
      {
        'label': 'Total Fleet',
        'value': _totalVehicles.toString(),
        'icon': Icons.directions_bus_outlined,
        'color': isDark ? Colors.grey.shade300 : Colors.grey.shade700,
        'filter': 'All',
      },
      {
        'label': 'Available',
        'value': _availableVehicles.toString(),
        'icon': Icons.check_circle_outline,
        'color': const Color(0xFF10B981),
        'filter': 'Available',
      },
      {
        'label': 'Needs Maint.',
        'value': _maintenanceVehicles.toString(),
        'icon': Icons.build_circle_outlined,
        'color': const Color(0xFFEF4444),
        'filter': 'Needs Maintenance',
      },
    ];

    Widget buildCard(Map<String, dynamic> stat) {
      final isSelected = _statusFilter == stat['filter'];
      return InkWell(
        onTap: () {
          setState(() {
            _statusFilter = stat['filter'];
            _applyFiltersAndSort();
          });
        },
        borderRadius: BorderRadius.circular(40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? stat['color'].withOpacity(0.1)
                : (isDark ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: isSelected
                  ? stat['color']
                  : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(stat['icon'], color: stat['color'], size: 28),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    stat['value'],
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      height: 1.1,
                    ),
                  ),
                  Text(
                    stat['label'],
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (isMobile) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: stats.map((stat) => buildCard(stat)).toList(),
      );
    } else {
      return Row(
        children: stats.map((stat) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: stat == stats.last ? 0 : 16.0),
              child: buildCard(stat),
            ),
          );
        }).toList(),
      );
    }
  }

  Widget _buildEmptyState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.directions_car_filled_outlined,
              size: 64,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No vehicle assets matched parameters.',
              style: TextStyle(
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v, bool isDark, bool isLast) {
    final String plate = v['plate_number'] ?? 'UNKNOWN';
    final String rawBusType = v['bus_type'] ?? 'Unknown Model';
    final String status = v['health_status'] ?? 'Good Condition';
    final String engine = v['engine_no'] ?? 'N/A';

    final String modelDisplay = rawBusType.contains(' - ')
        ? rawBusType.split(' - ').last
        : rawBusType;
    final String seatCapacity = rawBusType.contains(' - ')
        ? rawBusType.split(' - ').first
        : 'Configured Seats';

    final Color statusColor = _getStatusColor(status);
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);

    final int vehicleId =
        int.tryParse((v['vehicle_id'] ?? v['id'] ?? '0').toString()) ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 36,
            margin: const EdgeInsets.only(right: 16, top: 4),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => _showVehicleModal(
                        context,
                        vehicle: Map<String, dynamic>.from(v),
                      ),
                      child: Text(
                        plate,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          decoration: TextDecoration.underline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_isAdmin)
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            onPressed: () => _confirmPurgeVehicle(
                              Map<String, dynamic>.from(v),
                            ),
                            tooltip: 'Delete Vehicle',
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _cardIconText(
                      Icons.directions_bus_outlined,
                      modelDisplay,
                      isDark,
                    ),
                    _cardIconText(Icons.group_outlined, seatCapacity, isDark),
                    _cardIconText(Icons.pin_outlined, "Eng: $engine", isDark),
                  ],
                ),
                const SizedBox(height: 16),
                if (!_isAdmin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (vehicleId > 0) {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (c) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                          final logs = await _fetchVehicleLogHistory(vehicleId);
                          if (context.mounted) {
                            Navigator.pop(context);
                            _showMaintenanceManagerModal(
                              context,
                              Map<String, dynamic>.from(v),
                              logs,
                            );
                          }
                        }
                      },
                      icon: const Icon(
                        Icons.build_circle,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: const Text(
                        "Manage Maintenance",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardIconText(IconData icon, String text, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isDark ? Colors.grey.shade500 : const Color(0xFF64748B),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPaginationFooter(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: UniversalPagination(
        currentPage: _currentPage,
        totalPages: _totalPages,
        totalItems: _filteredVehicles.length,
        itemsPerPage: _itemsPerPage,
        itemName: 'vehicles',
        onNextPage: _currentPage < _totalPages - 1 ? _nextPage : null,
        onPrevPage: _currentPage > 0 ? _prevPage : null,
      ),
    );
  }

  // --- MAINTENANCE LOGIC DIALOGS ---
  void _showLogIssueDialog(Map<String, dynamic> vehicle) {
    final formKey = GlobalKey<FormState>();
    String description = '';
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
              borderRadius: BorderRadius.circular(24),
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
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange.shade600,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Logging this issue marks the vehicle as 'Maintenance Required'.",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.grey.shade300
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: chosenCategory,
                        dropdownColor:
                            isDark ? const Color(0xFF1E293B) : Colors.white,
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
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: borderColor),
                          ),
                        ),
                        items: [
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
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
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
                                  initialTime:
                                      incidentTime ?? TimeOfDay.now(),
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
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
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
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (formKey.currentState?.validate() ?? false) {
                          formKey.currentState?.save();
                          setModalState(() => isSaving = true);
                          String? currentUserId = widget.userId;
                          if (currentUserId == null || currentUserId.isEmpty) {
                            try {
                              currentUserId = Supabase
                                  .instance.client.auth.currentUser?.id;
                            } catch (_) {}
                          }
                          String? formatTime(TimeOfDay? time) {
                            if (time == null) return null;
                            return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
                          }

                          final payload = {
                            'description': description,
                            'vehicle_id': vehicle['vehicle_id'],
                            'user_id': currentUserId,
                            'category': chosenCategory,
                            'incident_date': incidentDate != null
                                ? '${incidentDate!.year}-${incidentDate!.month.toString().padLeft(2, '0')}-${incidentDate!.day.toString().padLeft(2, '0')}'
                                : null,
                            'incident_time': formatTime(incidentTime),
                            'is_resolved': false,
                          };
                          try {
                            final response = await http.post(
                              Uri.parse('$backendUrl/vehicles/maintenance'),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode(payload),
                            );
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
                                _showSnackBar(
                                  'Failed to log issue.',
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
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
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
              borderRadius: BorderRadius.circular(24),
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
                                borderRadius: BorderRadius.circular(8),
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
                                borderRadius: BorderRadius.circular(8),
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
                    borderRadius: BorderRadius.circular(8),
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
                            headers: {'Content-Type': 'application/json'},
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
                                'Failed to update log.',
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
                        child: CircularProgressIndicator(
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
    final int vehicleId = int.tryParse(vehicle['vehicle_id'].toString()) ?? 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          List<dynamic> sortedLogs = List.from(logs);

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

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      Container(
                        width: 180,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
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
                            dropdownColor:
                                isDark ? const Color(0xFF1E293B) : Colors.white,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 14,
                            ),
                            items: [
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
                  Expanded(
                    child: sortedLogs.isEmpty
                        ? Center(
                            child: Text(
                              "No maintenance records found.",
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.separated(
                            itemCount: sortedLogs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final log = sortedLogs[index];
                              final bool isResolved =
                                  log['is_resolved'] == true;
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1E293B)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isResolved
                                        ? Colors.green.withOpacity(0.5)
                                        : Colors.orange.withOpacity(0.5),
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
                                              const SizedBox(width: 12),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isResolved
                                                      ? Colors.green
                                                          .withOpacity(0.2)
                                                      : Colors.orange
                                                          .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
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
                                    if (!isResolved)
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
  late TextEditingController _modelYearController;
  late TextEditingController _engineController;
  late TextEditingController _insuranceNoController;
  late TextEditingController _insuranceExpiryController;
  late TextEditingController _franchiseNoController;
  late TextEditingController _franchiseExpiryController;
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
    _modelYearController = TextEditingController(
      text: isEdit ? (widget.vehicle!['model_year'] ?? '') : '',
    );
    _engineController = TextEditingController(
      text: isEdit ? (widget.vehicle!['engine_no'] ?? '') : '',
    );
    _insuranceNoController = TextEditingController(
      text: isEdit ? (widget.vehicle!['insurance_policy_no'] ?? '') : '',
    );
    _insuranceExpiryController = TextEditingController(
      text: isEdit ? (widget.vehicle!['insurance_expiry'] ?? '') : '',
    );
    _franchiseNoController = TextEditingController(
      text: isEdit ? (widget.vehicle!['franchise_no'] ?? '') : '',
    );
    _franchiseExpiryController = TextEditingController(
      text: isEdit ? (widget.vehicle!['franchise_expiry'] ?? '') : '',
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
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0));
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
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
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
        'model_year': cleanStr(_modelYearController, '2026'),
        'engine_no': cleanStr(_engineController, 'N/A'),
        'insurance_policy_no': cleanStr(_insuranceNoController, 'N/A'),
        'insurance_expiry': cleanStr(_insuranceExpiryController, '2027-01-01'),
        'franchise_no': cleanStr(_franchiseNoController, 'N/A'),
        'franchise_expiry': cleanStr(_franchiseExpiryController, 'N/A'),
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
          content: Text("Submission Error: $e", style: const TextStyle(color: Colors.white)),
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
    _modelYearController.dispose();
    _engineController.dispose();
    _insuranceNoController.dispose();
    _insuranceExpiryController.dispose();
    _franchiseNoController.dispose();
    _franchiseExpiryController.dispose();
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
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                        value: _selectedCapacity,
                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
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
                const SizedBox(height: 14),
                TextFormField(
                  controller: _engineController,
                  readOnly: !_isWritingUnlocked,
                  style: TextStyle(color: textColor),
                  decoration: _fieldStyle(
                    context: context,
                    label: 'Engine Serial Code',
                    icon: Icons.pin_outlined,
                  ),
                  validator: (val) => val!.isEmpty ? "Required" : null,
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
                        controller: _franchiseNoController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: textColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Franchise No.',
                          icon: Icons.assignment_outlined,
                        ),
                        validator: (val) => val!.isEmpty ? "Required" : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _franchiseExpiryController,
                        readOnly: true,
                        style: TextStyle(color: textColor),
                        onTap: () =>
                            _selectDate(context, _franchiseExpiryController),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Expiry',
                          icon: Icons.event_available_outlined,
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => setState(() => _isWritingUnlocked = true),
                    child: const Text(
                      'Edit Details',
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isLoading ? null : _submitVehicleForm,
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
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