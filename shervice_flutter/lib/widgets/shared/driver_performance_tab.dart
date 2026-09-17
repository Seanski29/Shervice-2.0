import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../widgets/driver/driver_evaluation_view.dart';

class DriverPerformanceTab extends StatefulWidget {
  final List<dynamic> drivers;
  final String backendUrl;
  final VoidCallback onSyncAction; 

  const DriverPerformanceTab({
    super.key,
    required this.drivers,
    required this.backendUrl,
    required this.onSyncAction, 
  });

  @override
  State<DriverPerformanceTab> createState() => _DriverPerformanceTabState();
}

class _DriverPerformanceTabState extends State<DriverPerformanceTab> {
  String _searchQuery = '';
  String _currentSort = 'Rating (High-Low)';
  int _currentPage = 0;
  final int _itemsPerPage = 6;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  
  List<dynamic> _leaderboard = [];
  bool _isFetching = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }

  Future<void> _fetchLeaderboard() async {
    if (!mounted) return;
    setState(() {
      _isFetching = true;
      _errorMessage = null;
    });

    try {
      final Map<String, String> queryParameters = {};
      if (_selectedYear == 0) {
        queryParameters['period'] = 'all';
        queryParameters['year'] = 'all';
        queryParameters['month'] = 'all';
      } else if (_selectedMonth == 0) {
        queryParameters['period'] = 'year';
        queryParameters['year'] = _selectedYear.toString();
        queryParameters['month'] = 'all';
      } else {
        queryParameters['period'] = 'month';
        queryParameters['year'] = _selectedYear.toString();
        queryParameters['month'] = _selectedMonth.toString();
      }
      
      // EXPLICITLY REQUEST ALL RECORDS SO THE LIST IS NOT TRUNCATED TO 10
      queryParameters['limit'] = 'all';

      final uri = Uri.parse('${widget.backendUrl}/dashboard/driver-leaderboard')
          .replace(queryParameters: queryParameters);

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && mounted) {
        final decoded = json.decode(response.body);
        if (decoded['success'] == true) {
          setState(() {
             _leaderboard = decoded['top_drivers'] ?? [];
          });
        } else {
          setState(() => _errorMessage = "Backend Error: ${decoded['error'] ?? 'Unknown'}");
        }
      } else {
        setState(() => _errorMessage = "Server crashed (Status ${response.statusCode}). Check Python console.");
      }
    } catch (e) {
      setState(() => _errorMessage = "Network Error: Cannot connect to backend.\n$e");
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month - 1];
  }

  List<dynamic> get _processedDrivers {
    List<dynamic> tempD = _leaderboard.where((d) {
      return (d['full_name'] ?? '').toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    tempD.sort((a, b) {
      final int countA = (a['review_count'] as num?)?.toInt() ?? (a['eval_count'] as num?)?.toInt() ?? 0;
      final int countB = (b['review_count'] as num?)?.toInt() ?? (b['eval_count'] as num?)?.toInt() ?? 0;
      final bool aUnrated = countA == 0;
      final bool bUnrated = countB == 0;

      // Force unrated drivers to the bottom
      if (aUnrated && !bUnrated) return 1;
      if (!aUnrated && bUnrated) return -1;

      final double ratingA = (a['rating'] as num?)?.toDouble() ?? 0.0;
      final double ratingB = (b['rating'] as num?)?.toDouble() ?? 0.0;
      int cmp = 0;

      if (_currentSort == 'Rating (High-Low)') {
        cmp = ratingB.toStringAsFixed(1).compareTo(ratingA.toStringAsFixed(1));
      } else if (_currentSort == 'Rating (Low-High)') {
        cmp = ratingA.toStringAsFixed(1).compareTo(ratingB.toStringAsFixed(1));
      } else if (_currentSort == 'Z to A') {
        cmp = (b['full_name'] ?? '').toString().toLowerCase().compareTo((a['full_name'] ?? '').toString().toLowerCase());
      } else {
        cmp = (a['full_name'] ?? '').toString().toLowerCase().compareTo((b['full_name'] ?? '').toString().toLowerCase());
      }

      if (cmp == 0) cmp = countB.compareTo(countA); 
      if (cmp == 0) {
        final nameA = (a['full_name'] ?? '').toString().toLowerCase();
        final nameB = (b['full_name'] ?? '').toString().toLowerCase();
        cmp = nameA.compareTo(nameB);
      }

      return cmp;
    });
    return tempD;
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;

    final drivers = _processedDrivers;
    final int totalPages = max(1, (drivers.length / _itemsPerPage).ceil());
    
    // Ensure current page doesn't go out of bounds after filtering/refreshing
    if (_currentPage >= totalPages) {
      _currentPage = max(0, totalPages - 1);
    }

    final List<dynamic> paginatedDrivers = drivers.isEmpty
        ? []
        : drivers.sublist(
            _currentPage * _itemsPerPage,
            min((_currentPage + 1) * _itemsPerPage, drivers.length),
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
                      icon: Icon(Icons.sort, size: 18, color: Colors.grey.shade500),
                      style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500),
                      items: ['A to Z', 'Z to A', 'Rating (High-Low)', 'Rating (Low-High)']
                          .map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _currentSort = value;
                            _currentPage = 0;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            DropdownButton<int>(
              value: _selectedMonth,
              items: [
                const DropdownMenuItem(value: 0, child: Text('All months')),
                ...List.generate(12, (index) => DropdownMenuItem(value: index + 1, child: Text(_monthName(index + 1)))),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedMonth = value;
                    _currentPage = 0;
                  });
                  _fetchLeaderboard();
                }
              },
            ),
            DropdownButton<int>(
              value: _selectedYear,
              items: [
                const DropdownMenuItem(value: 0, child: Text('All time')),
                ...List.generate(7, (index) => DropdownMenuItem(value: DateTime.now().year - 3 + index, child: Text('${DateTime.now().year - 3 + index}'))),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedYear = value;
                    if (value == 0) _selectedMonth = 0;
                    _currentPage = 0;
                  });
                  _fetchLeaderboard();
                }
              },
            ),
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
                    hintText: 'Search drivers...',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade500),
                    filled: true,
                    fillColor: cardBg,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
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
                tooltip: 'Sync Classifications',
                onPressed: () {
                  widget.onSyncAction();
                  Future.delayed(const Duration(seconds: 3), () => _fetchLeaderboard());
                },
                icon: const Icon(Icons.sync, color: Color(0xFF3B82F6), size: 20),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _isFetching 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
              : _errorMessage != null 
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Data Sync Failed',
                          style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.redAccent.shade200, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchLeaderboard,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        )
                      ],
                    ),
                  ),
                )
              : drivers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group_off, size: 48, color: Colors.grey.shade500),
                      const SizedBox(height: 12),
                      Text('No records found.', style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: paginatedDrivers.length,
                  itemBuilder: (context, index) {
                    final driver = paginatedDrivers[index];
                    final String driverId = (driver['user_id'] ?? driver['driver_id'] ?? '').toString();
                    
                    final double rating = (driver['rating'] as num?)?.toDouble() ?? 0.0;
                    final int evaluationCount = (driver['review_count'] as num?)?.toInt() ?? (driver['eval_count'] as num?)?.toInt() ?? 0;
                    final String status = driver['employment_status'] ?? 'Active';
                    final String mlClass = driver['ml_classification']?.toString() ?? 'Pending Sweep';
                    
                    Color statusColor = status.toLowerCase() == 'active' 
                        ? const Color(0xFF10B981) 
                        : status.toLowerCase() == 'on leave' 
                        ? const Color(0xFF64748B) 
                        : const Color(0xFFF59E0B);

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
                            builder: (ctx) => Dialog(
                              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              child: Container(
                                width: isMobile ? double.infinity : 720,
                                height: isMobile ? MediaQuery.of(context).size.height * 0.85 : 680,
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.close, color: isDark ? Colors.grey.shade400 : Colors.black87),
                                      onPressed: () => Navigator.pop(ctx),
                                    ),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: DriverEvaluationView(
                                          driverUuid: driverId,
                                          backendUrl: widget.backendUrl,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                                  color: isDark ? Colors.blue.withOpacity(0.15) : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.person, color: Colors.blue),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      driver['full_name'] ?? 'Unknown',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              evaluationCount == 0 ? Icons.star_border : Icons.star,
                                              size: 14,
                                              color: Colors.amber.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              evaluationCount == 0 ? 'New' : rating.toStringAsFixed(1),
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
                                            ),
                                            if (evaluationCount > 0)
                                              Text(
                                                ' • $evaluationCount evaluations',
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                              ),
                                          ],
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.badge,
                                              size: 14,
                                              color: Colors.grey.shade500,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              driver['license_no'] ?? 'N/A',
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  Color mlColor = const Color(0xFF64748B);
                                  if (mlClass == 'Consistent Performer') {
                                    mlColor = const Color(0xFF10B981);
                                  } else if (mlClass == 'Aggressive Driving Risk' || mlClass == 'Needs Review') {
                                    mlColor = const Color(0xFFEF4444);
                                  } else if (mlClass == 'Tardiness Risk' || mlClass == 'Unprofessional Conduct') {
                                    mlColor = const Color(0xFFF97316);
                                  }

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: mlColor.withOpacity(0.1),
                                      border: Border.all(color: mlColor.withOpacity(0.4)),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      mlClass.toUpperCase(),
                                      style: TextStyle(color: mlColor, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  );
                                },
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, color: Colors.grey),
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
                    'Showing ${drivers.isEmpty ? 0 : (_currentPage * _itemsPerPage) + 1} - ${min((_currentPage + 1) * _itemsPerPage, drivers.length)} of ${drivers.length} records',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                  const SizedBox(width: 24),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.chevron_left, color: textColor),
                        onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_currentPage + 1} / $totalPages',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B82F6), fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.chevron_right, color: textColor),
                        onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
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