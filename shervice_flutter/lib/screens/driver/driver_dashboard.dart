import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../constant.dart';
import '../../widgets/driver/driver_rating_badge.dart';

class DriverDashboard extends StatefulWidget {
  final String driverName;
  final String driverId;

  const DriverDashboard({
    super.key,
    required this.driverName,
    required this.driverId,
  });

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  // --- STATE ---
  bool _isLoading = true;
  bool _isUpdatingTrip = false;
  Map<String, dynamic>? _activeTrip;
  double _tripActionProgress = 0;

  @override
  void initState() {
    super.initState();
    _fetchAssignedTripData();
  }

  // --- DATA FETCHING ---
  Future<void> _fetchAssignedTripData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final res = await http.get(
        Uri.parse(
          '$backendUrl/driver/active-trip/${Uri.encodeComponent(widget.driverName)}',
        ),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _activeTrip = data['active_trip'];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Driver Dashboard Sync Failure: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _slideTripStatus() async {
    if (_activeTrip == null || _isUpdatingTrip) return;
    final tripId = _activeTrip!['trip_id'];
    if (tripId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This trip has no valid trip ID.')),
      );
      return;
    }
    final status = (_activeTrip!['status'] ?? _activeTrip!['trip_status'])
        ?.toString()
        .toUpperCase();
    final nextStatus = status == 'ONGOING' ? 'Completed' : 'Ongoing';
    setState(() => _isUpdatingTrip = true);
    late http.Response response;
    try {
      response = await http.post(
        Uri.parse('$backendUrl/schedules/update-status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'trip_id': tripId, 'status': nextStatus}),
      );
    } catch (error) {
      debugPrint('Trip status update failed: $error');
      if (mounted) {
        setState(() {
          _isUpdatingTrip = false;
          _tripActionProgress = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to update trip status.')),
        );
      }
      return;
    }
    if (!mounted) return;
    if (response.statusCode == 200) {
      setState(() {
        _tripActionProgress = 0;
        _isUpdatingTrip = false;
      });
      await _fetchAssignedTripData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextStatus == 'Completed'
                ? 'Trip finished successfully.'
                : 'Trip started. Drive safely.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else {
      setState(() {
        _tripActionProgress = 0;
        _isUpdatingTrip = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trip status could not be updated.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _hasAssignedTripData() {
    if (_activeTrip == null) return false;
    if (_activeTrip!.isEmpty) return false;

    final routeName = _activeTrip!['route_name'];
    final departureTime = _activeTrip!['departure_time'];
    final estimatedArrival = _activeTrip!['estimated_arrival_time'];
    final status = _activeTrip!['status'];
    final plateNumber = _activeTrip!['plate_number'];

    final hasRouteInfo =
        routeName != null && routeName.toString().trim().isNotEmpty;
    final hasScheduleInfo =
        departureTime != null && departureTime.toString().trim().isNotEmpty;
    final hasEtaInfo =
        estimatedArrival != null &&
        estimatedArrival.toString().trim().isNotEmpty;
    final hasStatusInfo = status != null && status.toString().trim().isNotEmpty;
    final hasVehicleInfo =
        plateNumber != null &&
        plateNumber.toString().trim().isNotEmpty &&
        plateNumber.toString().trim() != 'No Plate Assigned';

    return hasRouteInfo ||
        hasScheduleInfo ||
        hasEtaInfo ||
        hasStatusInfo ||
        hasVehicleInfo;
  }

  // --- MODALS ---
  void _showPassengerQR(String tripId, bool isDark) {
    final String baseUrl = backendUrl.replaceAll('/api', '');
    final String evalUrl = '$baseUrl/evaluate?trip_id=$tripId';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.transparent,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Passenger Evaluation',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask passengers to scan this code as they exit to submit a review.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? Colors.grey.shade400
                      : const Color(0xFF64748B),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              // QR Must ALWAYS be on a white background for scanner reliability
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                ),
                child: QrImageView(
                  data: evalUrl,
                  version: QrVersions.auto,
                  backgroundColor: Colors.white,
                  size: 200,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.grey.shade800
                        : Colors.grey.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- UTILS ---
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _formatDepartureEta(String? departureTime, String? etaTime) {
    final departure = departureTime?.trim();
    final eta = etaTime?.trim();

    final formattedDeparture = departure != null && departure.isNotEmpty
        ? (departure.length >= 5 ? departure.substring(0, 5) : departure)
        : '--:--';
    final formattedEta = eta != null && eta.isNotEmpty
        ? (eta.length >= 5 ? eta.substring(0, 5) : eta)
        : '--:--';

    return '$formattedDeparture - $formattedEta';
  }

  // --- BUILD ---
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final double horizontalPadding = isMobile ? 16.0 : 32.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Skeletonizer(
          enabled: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Bone.text(words: 3),
                const SizedBox(height: 8),
                const Bone.text(words: 2),
                const SizedBox(height: 28),
                Bone(
                  width: double.infinity,
                  height: 420,
                  borderRadius: BorderRadius.circular(16),
                ),
                const SizedBox(height: 18),
                const Bone.text(words: 3),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _fetchAssignedTripData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----- HEADER -----
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_getGreeting()}, ${widget.driverName}',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentTimeLabel(),
                          style: TextStyle(
                            color: isDark
                                ? Colors.blue.shade200
                                : const Color(0xFF2563EB),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Rating Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.amber.withValues(alpha: 0.15)
                          : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: isDark
                            ? Colors.amber.withValues(alpha: 0.3)
                            : Colors.amber.shade200,
                      ),
                    ),
                    child: DriverRatingBadge(
                      key: UniqueKey(),
                      driverUuid: widget.driverId,
                      backendUrl: backendUrl,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ----- NEXT DISPATCH -----
              if (_hasAssignedTripData())
                _buildActiveTripCard(isDark)
              else
                _buildEmptyTripPlaceholder(isDark),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _showIncidentDialog,
                  icon: const Icon(Icons.report_problem_outlined, size: 18),
                  label: const Text('Report Incident / Delay'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.orange.shade200
                        : const Color(0xFFB45309),
                    side: BorderSide(
                      color: isDark
                          ? Colors.orange.shade700
                          : const Color(0xFFF59E0B),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _currentTimeLabel() {
    final now = DateTime.now();
    final hour = now.hour == 0
        ? 12
        : (now.hour > 12 ? now.hour - 12 : now.hour);
    final minute = now.minute.toString().padLeft(2, '0');
    final suffix = now.hour >= 12 ? 'PM' : 'AM';
    return '${now.month}/${now.day}/${now.year}  $hour:$minute $suffix';
  }

  void _showIncidentDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report Incident / Delay'),
        content: const Text(
          'Please contact your dispatcher to report an incident or delay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // --- TRIP CARD (Maintains the vibrant gradient for primary focus) ---
  Widget _buildActiveTripCard(bool isDark) {
    final status =
        (_activeTrip!['status'] ?? _activeTrip!['trip_status'] ?? 'SCHEDULED')
            .toString()
            .toUpperCase();
    final isOngoing = status == 'ONGOING';
    final departureTime = _activeTrip!['departure_time']?.toString();
    final estimatedArrival = _activeTrip!['estimated_arrival_time']?.toString();

    final details = [
      {
        'icon': Icons.people_alt_outlined,
        'label': 'Passengers',
        'value': '${_activeTrip!['passenger_count'] ?? 0}',
      },
      {
        'icon': Icons.straighten,
        'label': 'Distance',
        'value': '${_activeTrip!['route_distance'] ?? 0} km',
      },
      {
        'icon': Icons.access_time,
        'label': 'Schedule',
        'value': _formatDepartureEta(departureTime, estimatedArrival),
      },
      {
        'icon': Icons.pin_drop_outlined,
        'label': 'Status',
        'value': isOngoing ? 'In Transit' : 'Pending',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E3A8A), const Color(0xFF172554)]
              : [Colors.blue.shade700, Colors.blue.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'TRP-${_activeTrip!['trip_id'] ?? 'TBD'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isOngoing
                      ? Colors.green.shade400
                      : Colors.orange.shade400,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.toString().toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildRouteAndVehicleRow(
            _activeTrip!['route_name']?.toString() ?? 'Pending Assignment',
            _activeTrip!['plate_number']?.toString() ?? 'Unassigned',
            _formatDepartureEta(departureTime, estimatedArrival),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildRouteDetail(details[0])),
                    const SizedBox(width: 12),
                    Expanded(child: _buildRouteDetail(details[1])),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildRouteDetail(details[2])),
                    const SizedBox(width: 12),
                    Expanded(child: _buildRouteDetail(details[3])),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () =>
                  _showPassengerQR(_activeTrip!['trip_id'].toString(), isDark),
              icon: const Icon(
                Icons.qr_code,
                color: Color(0xFF1E3A8A),
                size: 20,
              ),
              label: const Text(
                'SHOW BOARDING QR CODE',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
          if (!isOngoing) ...[
            const SizedBox(height: 14),
            _buildTripSlider(
              label: 'Swipe to start trip',
              icon: Icons.play_arrow_rounded,
            ),
          ] else ...[
            const SizedBox(height: 14),
            _buildTripSlider(
              label: 'Swipe to finish trip',
              icon: Icons.flag_rounded,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTripSlider({required String label, required IconData icon}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final thumbSize = 58.0;
        final travelWidth = trackWidth - thumbSize - 12;
        final left = travelWidth * _tripActionProgress;
        
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _isUpdatingTrip
              ? null
              : (details) {
                  setState(() {
                    _tripActionProgress =
                        (_tripActionProgress +
                                details.primaryDelta! / travelWidth)
                            .clamp(0.0, 1.0);
                  });
                },
          onHorizontalDragEnd: _isUpdatingTrip
              ? null
              : (_) {
                  if (_tripActionProgress > .82) {
                    _slideTripStatus();
                  } else {
                    setState(() => _tripActionProgress = 0);
                  }
                },
          child: Container(
            width: double.infinity, // THIS FIXES THE SHRINK-WRAPPING BUG
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white24),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
                Positioned(
                  left: 6 + left,
                  child: Container(
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: _isUpdatingTrip
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : Icon(icon, color: const Color(0xFF2563EB)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRouteDetail(Map<String, dynamic> detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(detail['icon'], color: Colors.white70, size: 14),
            const SizedBox(width: 6),
            Text(
              detail['label'],
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          detail['value'],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildRouteAndVehicleRow(String route, String vehicle, String time) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.route, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _routeValue('ROUTE', route, time)),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: _routeValue('VEHICLE', vehicle, '')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _routeValue(String label, String value, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: .6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyTripPlaceholder(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.directions_bus_outlined,
              size: 48,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'No active assignment',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey.shade800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pull down to refresh when dispatch assigns a trip.',
              style: TextStyle(
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
