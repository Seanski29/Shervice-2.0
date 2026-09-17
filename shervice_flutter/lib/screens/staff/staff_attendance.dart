import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

// ============================================================================
// STAFF ATTENDANCE WIDGET
// ============================================================================
class StaffAttendance extends StatefulWidget {
  const StaffAttendance({super.key});

  @override
  State<StaffAttendance> createState() => _StaffAttendanceState();
}

class _StaffAttendanceState extends State<StaffAttendance> {
  String _filterQuery = '';
  
  bool _isLoading = true;

  final List<Map<String, dynamic>> _attendanceLogs = [
    { "id": 1, "name": "Juan Dela Cruz", "initials": "JD", "time": "05:48 AM", "rest": "8.5 hrs", "status": "Cleared", "route": "EPSON - Shift A" },
    { "id": 2, "name": "Ricardo Ramos", "initials": "RR", "time": "06:02 AM", "rest": "4.0 hrs", "status": "Fatigue Risk", "route": "Bandai - Shift A" },
    { "id": 3, "name": "Miguel Santos", "initials": "MS", "time": "05:55 AM", "rest": "7.2 hrs", "status": "Cleared", "route": "NX Logistics" },
    { "id": 4, "name": "Antonio Luna", "initials": "AL", "time": "05:30 AM", "rest": "5.5 hrs", "status": "Monitor", "route": "EPSON - Shift B" },
  ];

  @override
  void initState() {
    super.initState();
    _fetchAttendanceData();
  }

  Future<void> _fetchAttendanceData() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Cleared': return Colors.green;
      case 'Monitor': return Colors.amber.shade700;
      case 'Fatigue Risk': return Colors.red.shade600;
      default: return Colors.grey;
    }
  }

  List<Map<String, dynamic>> get _displayLogs {
    if (_isLoading) {
      return List.generate(4, (index) => {
        "id": index, 
        "name": "Loading Driver Name", 
        "initials": "XX", 
        "time": "00:00 AM", 
        "rest": "0.0 hrs", 
        "status": "Cleared", 
        "route": "Loading Route Location"
      });
    }
    return _attendanceLogs
        .where((log) => log['name'].toString().toLowerCase().contains(_filterQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filteredLogs = _displayLogs;

    return Skeletonizer(
      enabled: _isLoading,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance and Well Being', 
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      )
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.health_and_safety, size: 16, color: isDark ? Colors.grey.shade400 : Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Text(
                          'Tracking driver attendance and capability', 
                          style: TextStyle(
                            fontSize: 14, 
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600
                          )
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildQuickStatCard('Cleared for Duty', _isLoading ? '0' : '42', '/59', Colors.green.shade600, isDark),
                    const SizedBox(width: 16),
                    _buildQuickStatCard('High Fatigue', _isLoading ? '0' : '3', ' Drivers', Colors.red.shade600, isDark),
                  ],
                )
              ],
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: theme.cardColor, 
                borderRadius: BorderRadius.circular(12), 
                border: Border.all(color: theme.dividerColor)
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? theme.scaffoldBackgroundColor : Colors.grey.shade50, 
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)), 
                      border: Border(bottom: BorderSide(color: theme.dividerColor))
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Shift Check-in & Rest Logs', 
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.bold, 
                            color: isDark ? Colors.white : const Color(0xFF1E293B)
                          )
                        ),
                        Skeleton.ignore(
                          child: SizedBox(
                            width: 280, height: 40,
                            child: TextField(
                              onChanged: (val) => setState(() => _filterQuery = val),
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              decoration: InputDecoration(
                                hintText: 'Filter by driver name...', 
                                hintStyle: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                                prefixIcon: Icon(Icons.search, size: 18, color: theme.iconTheme.color), 
                                filled: true, 
                                fillColor: isDark ? theme.cardColor : theme.inputDecorationTheme.fillColor, 
                                contentPadding: EdgeInsets.zero, 
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.dividerColor)), 
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.dividerColor))
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                  !_isLoading && filteredLogs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              'No attendance records match your filter.', 
                              style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey)
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true, 
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredLogs.length,
                          separatorBuilder: (context, index) => Divider(height: 1, color: theme.dividerColor),
                          itemBuilder: (context, index) {
                            final log = filteredLogs[index];
                            final Color statusColor = _getStatusColor(log['status']);
                            
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22, 
                                        backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100, 
                                        child: Text(
                                          log['initials'], 
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold, 
                                            color: isDark ? Colors.white70 : Colors.grey.shade700, 
                                            fontSize: 14
                                          )
                                        )
                                      ),
                                      const SizedBox(width: 16),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start, 
                                        children: [
                                          Text(
                                            log['name'], 
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold, 
                                              fontSize: 15,
                                              color: isDark ? Colors.white : Colors.black87
                                            )
                                          ), 
                                          const SizedBox(height: 2), 
                                          Text(
                                            log['route'], 
                                            style: TextStyle(
                                              fontSize: 12, 
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade500, 
                                              fontWeight: FontWeight.w500
                                            )
                                          )
                                        ]
                                      )
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Prior Rest', 
                                            style: TextStyle(
                                              fontSize: 10, 
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade500, 
                                              fontWeight: FontWeight.bold
                                            )
                                          ),
                                          Text(
                                            log['rest'], 
                                            style: TextStyle(
                                              fontSize: 13, 
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : Colors.black87
                                            )
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 24),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.08), 
                                          border: Border.all(color: statusColor.withValues(alpha: 0.3)), 
                                          borderRadius: BorderRadius.circular(6)
                                        ), 
                                        child: Text(
                                          log['status'], 
                                          style: TextStyle(
                                            fontSize: 11, 
                                            fontWeight: FontWeight.bold, 
                                            color: isDark ? statusColor.withValues(alpha: 0.9) : statusColor
                                          )
                                        )
                                      ),
                                      const SizedBox(width: 16),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.grey.shade800 : Colors.grey.shade100, 
                                          border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade200), 
                                          borderRadius: BorderRadius.circular(6)
                                        ), 
                                        child: Text(
                                          log['time'], 
                                          style: TextStyle(
                                            fontSize: 13, 
                                            fontWeight: FontWeight.bold, 
                                            color: isDark ? Colors.grey.shade300 : const Color(0xFF334155)
                                          )
                                        )
                                      )
                                    ],
                                  )
                                ],
                              ),
                            );
                          },
                        )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatCard(String title, String mainValue, String subValue, Color valueColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: Theme.of(context).dividerColor), 
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.02), 
            blurRadius: 4
          )
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(), 
            style: TextStyle(
              fontSize: 11, 
              fontWeight: FontWeight.bold, 
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade500, 
              letterSpacing: 0.5
            )
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              text: mainValue, 
              style: TextStyle(
                fontSize: 22, 
                fontWeight: FontWeight.bold, 
                color: valueColor
              ), 
              children: [
                if (subValue.isNotEmpty) 
                  TextSpan(
                    text: subValue, 
                    style: TextStyle(
                      fontSize: 13, 
                      fontWeight: FontWeight.w500, 
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade400
                    )
                  )
              ]
            )
          )
        ],
      ),
    );
  }
}