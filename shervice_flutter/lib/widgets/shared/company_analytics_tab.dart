import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class CompanyAnalyticsTab extends StatefulWidget {
  final List<dynamic> trips;
  final List<dynamic> drivers;

  const CompanyAnalyticsTab({
    super.key,
    required this.trips,
    required this.drivers,
  });

  @override
  State<CompanyAnalyticsTab> createState() => _CompanyAnalyticsTabState();
}

class _CompanyAnalyticsTabState extends State<CompanyAnalyticsTab> {
  int? _selectedYear;
  int _currentPage = 0;

  static const int _companiesPerPage = 3;
  static const List<String> _statusOptions = [
    'All states',
    'Completed',
    'Scheduled',
    'Ongoing',
    'Rejected',
    'Expired',
  ];

  String _companyName(dynamic trip) {
    final rawCompany = trip['client_company'] ?? trip['oic_profile'];
    if (rawCompany is Map) {
      return (rawCompany['company_name'] ?? 'Unassigned Company').toString();
    }
    if (rawCompany != null && rawCompany.toString().trim().isNotEmpty) {
      return rawCompany.toString();
    }
    return (trip['company_name'] ?? 'Unassigned Company').toString();
  }

  int _passengers(dynamic trip) =>
      int.tryParse((trip['passenger_count'] ?? 0).toString()) ?? 0;

  String _driverId(dynamic trip) =>
      (trip['user_id'] ?? trip['driver_id'] ?? '').toString();

  String _date(dynamic trip) =>
      (trip['schedule_date'] ?? '').toString().split(' ').first;

  String _monthLabel(int month) {
    const labels = [
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
    return labels[month - 1];
  }

  int? _year(dynamic trip) {
    final date = DateTime.tryParse(_date(trip));
    return date?.year;
  }

  String _status(dynamic trip) =>
      (trip['trip_status'] ?? trip['status'] ?? 'Scheduled')
          .toString()
          .toLowerCase();

  bool _isCompleted(dynamic trip) => _status(trip).contains('completed');

  String _statusLabel(dynamic trip) {
    final status = _status(trip);
    if (status.contains('completed')) return 'Completed';
    if (status.contains('ongoing') || status.contains('progress')) {
      return 'Ongoing';
    }
    if (status.contains('reject') || status.contains('cancel')) {
      return 'Rejected';
    }
    if (status.contains('expired')) return 'Expired';
    return 'Scheduled';
  }

  Map<String, List<dynamic>> _groupTrips() {
    final groups = <String, List<dynamic>>{};
    for (final trip in _filteredTrips) {
      groups.putIfAbsent(_companyName(trip), () => []).add(trip);
    }
    return groups;
  }

  List<dynamic> get _filteredTrips {
    return widget.trips.where((trip) {
      final matchesYear = _selectedYear == null || _year(trip) == _selectedYear;
      return matchesYear;
    }).toList();
  }

  List<int> get _availableYears {
    final years = widget.trips.map(_year).whereType<int>().toSet().toList();
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  Map<String, dynamic> _summary(String company, List<dynamic> companyTrips) {
    final passengers = companyTrips.fold<int>(
      0,
      (sum, trip) => sum + _passengers(trip),
    );
    final driverIds = companyTrips
        .map(_driverId)
        .where((id) => id.isNotEmpty)
        .toSet();
    return {
      'name': company,
      'trips': companyTrips.length,
      'passengers': passengers,
      'average': companyTrips.isEmpty ? 0.0 : passengers / companyTrips.length,
      'personnel': driverIds.length,
      'completed': companyTrips.where(_isCompleted).length,
      'dates': companyTrips
          .map(_date)
          .where((date) => date.isNotEmpty)
          .toSet()
          .length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final mutedColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final groups = _groupTrips();
    final summaries = groups.entries
        .map((entry) => _summary(entry.key, entry.value))
        .toList();

    summaries.sort((a, b) => (b['trips'] as int).compareTo(a['trips'] as int));

    final totalPages = summaries.isEmpty
        ? 1
        : (summaries.length / _companiesPerPage).ceil();
    final page = _currentPage.clamp(0, totalPages - 1);
    final pageSummaries = summaries
        .skip(page * _companiesPerPage)
        .take(_companiesPerPage)
        .toList();

    final filteredTrips = _filteredTrips;
    final totalPassengers = filteredTrips.fold<int>(
      0,
      (sum, trip) => sum + _passengers(trip),
    );
    final average = filteredTrips.isEmpty
        ? 0.0
        : totalPassengers / filteredTrips.length;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Company Analytics',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _yearControl(textColor, cardColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Compare company activity, personnel movement, and scheduled service dates.',
                  style: TextStyle(color: mutedColor, fontSize: 13),
                ),
                const SizedBox(height: 14),
                _buildKpis(
                  context,
                  summaries.length,
                  filteredTrips.length,
                  totalPassengers,
                  average,
                  cardColor,
                  textColor,
                  mutedColor,
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, chartConstraints) {
                    final tripsChart = _chartCard(
                      'Trips by company',
                      _companyBarChart(summaries, isDark),
                      cardColor,
                      textColor,
                      onTap: () => _showTripsModal(
                        context,
                        'All filtered trips',
                        filteredTrips,
                      ),
                    );
                    final scheduleChart = _chartCard(
                      'Scheduled trips over time',
                      _scheduleLineChart(isDark),
                      cardColor,
                      textColor,
                      onTap: () => _showTripsModal(
                        context,
                        'Scheduled trips and current states',
                        filteredTrips,
                      ),
                    );
                    if (chartConstraints.maxWidth < 760) {
                      return Column(
                        children: [
                          tripsChart,
                          const SizedBox(height: 12),
                          scheduleChart,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: tripsChart),
                        const SizedBox(width: 12),
                        Expanded(child: scheduleChart),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                if (summaries.isEmpty)
                  _emptyState(cardColor, textColor, mutedColor)
                else
                  ...pageSummaries.map(
                    (summary) => _companySection(
                      context,
                      summary,
                      groups[summary['name']] ?? [],
                      isDark,
                      cardColor,
                      textColor,
                      mutedColor,
                    ),
                  ),
                if (summaries.isNotEmpty)
                  _pagination(page, totalPages, textColor, mutedColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _yearControl(Color textColor, Color cardColor) {
    return _dropdown<int?>(
      'Year',
      _selectedYear,
      [
        const DropdownMenuItem(value: null, child: Text('All time')),
        ..._availableYears.map(
          (year) => DropdownMenuItem(value: year, child: Text('$year')),
        ),
      ],
      (value) => setState(() {
        _selectedYear = value;
        _currentPage = 0;
      }),
      textColor,
      cardColor,
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged,
    Color textColor,
    Color cardColor,
  ) {
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          style: TextStyle(color: textColor, fontSize: 12),
          hint: Text(label),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _pagination(
    int page,
    int totalPages,
    Color textColor,
    Color mutedColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous companies',
            onPressed: page > 0
                ? () => setState(() => _currentPage = page - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            'Page ${page + 1} of $totalPages',
            style: TextStyle(color: mutedColor, fontSize: 12),
          ),
          IconButton(
            tooltip: 'Next companies',
            onPressed: page < totalPages - 1
                ? () => setState(() => _currentPage = page + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildKpis(
    BuildContext context,
    int companies,
    int trips,
    int passengers,
    double average,
    Color cardColor,
    Color textColor,
    Color mutedColor,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth < 650
            ? constraints.maxWidth
            : (constraints.maxWidth - 36) / 4;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpi(
              'Companies',
              companies.toString(),
              Icons.business_outlined,
              const Color(0xFF3B82F6),
              itemWidth,
              cardColor,
              textColor,
              mutedColor,
            ),
            _kpi(
              'Total trips',
              trips.toString(),
              Icons.route_outlined,
              const Color(0xFF8B5CF6),
              itemWidth,
              cardColor,
              textColor,
              mutedColor,
            ),
            _kpi(
              'People moved',
              passengers.toString(),
              Icons.people_outline,
              const Color(0xFF10B981),
              itemWidth,
              cardColor,
              textColor,
              mutedColor,
            ),
            _kpi(
              'Average / trip',
              average.toStringAsFixed(1),
              Icons.groups_outlined,
              const Color(0xFFF59E0B),
              itemWidth,
              cardColor,
              textColor,
              mutedColor,
            ),
          ],
        );
      },
    );
  }

  Widget _kpi(
    String label,
    String value,
    IconData icon,
    Color color,
    double width,
    Color cardColor,
    Color textColor,
    Color mutedColor,
  ) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: mutedColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(label, style: TextStyle(color: mutedColor, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _companyMetric(
    String label,
    String value,
    Color textColor,
    Color mutedColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: TextStyle(color: mutedColor, fontSize: 12)),
      ],
    );
  }

  Widget _companySection(
    BuildContext context,
    Map<String, dynamic> summary,
    List<dynamic> companyTrips,
    bool isDark,
    Color cardColor,
    Color textColor,
    Color mutedColor,
  ) {
    final totalTrips = summary['trips'] as int;
    final completedTrips = summary['completed'] as int;
    const isExpanded = true;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: mutedColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _showCompanyTripsModal(
              context,
              summary['name'].toString(),
              companyTrips,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    summary['name'].toString(),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '$totalTrips trips',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.open_in_new, color: mutedColor),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _companyMetric(
                'Total trips',
                totalTrips.toString(),
                textColor,
                mutedColor,
              ),
              _companyMetric(
                'Completed',
                completedTrips.toString(),
                textColor,
                mutedColor,
              ),
              _companyMetric(
                'People served',
                summary['passengers'].toString(),
                textColor,
                mutedColor,
              ),
              _companyMetric(
                'Average passengers / trip',
                (summary['average'] as double).toStringAsFixed(1),
                textColor,
                mutedColor,
              ),
              _companyMetric(
                'Assigned drivers',
                summary['personnel'].toString(),
                textColor,
                mutedColor,
              ),
            ],
          ),
          if (isExpanded) ...[
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final passengerChart = _chartCard(
                  'Passenger volume by month',
                  _passengerVolumeChart(companyTrips, isDark),
                  cardColor,
                  textColor,
                  onTap: () => _showCompanyTripsModal(
                    context,
                    '${summary['name']} passenger volume',
                    companyTrips,
                  ),
                );
                final tripsChart = _chartCard(
                  'Trips by month',
                  _tripsByMonthChart(companyTrips, isDark),
                  cardColor,
                  textColor,
                  onTap: () => _showCompanyTripsModal(
                    context,
                    '${summary['name']} trips by month',
                    companyTrips,
                  ),
                );
                if (constraints.maxWidth < 760) {
                  return Column(
                    children: [
                      passengerChart,
                      const SizedBox(height: 12),
                      tripsChart,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: passengerChart),
                    const SizedBox(width: 12),
                    Expanded(child: tripsChart),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _passengerVolumeChart(List<dynamic> trips, bool isDark) {
    final labels = List<String>.generate(12, (index) => _monthLabel(index + 1));
    final counts = List<int>.filled(12, 0);
    for (final trip in trips) {
      final date = DateTime.tryParse(_date(trip));
      if (date != null) counts[date.month - 1] += _passengers(trip);
    }
    final maxValue = counts.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    return BarChart(
      BarChartData(
        maxY: (maxValue == 0 ? 1 : maxValue + 1).toDouble(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 25,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    labels[index].substring(0, 3),
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        barGroups: labels.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: counts[entry.key].toDouble(),
                color: const Color(0xFF10B981),
                width: 16,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _tripsByMonthChart(List<dynamic> trips, bool isDark) {
    final labels = List<String>.generate(12, (index) => _monthLabel(index + 1));
    final counts = List<int>.filled(12, 0);
    for (final trip in trips) {
      final date = DateTime.tryParse(_date(trip));
      if (date != null) counts[date.month - 1]++;
    }
    final spots = labels
        .asMap()
        .entries
        .map(
          (entry) => FlSpot(entry.key.toDouble(), counts[entry.key].toDouble()),
        )
        .toList();
    return LineChart(
      LineChartData(
        minY: 0,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 25,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    labels[index].substring(0, 3),
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF8B5CF6),
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard(
    String title,
    Widget chart,
    Color cardColor,
    Color textColor, {
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 270,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: textColor.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  size: 15,
                  color: textColor.withValues(alpha: 0.55),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: chart),
          ],
        ),
      ),
    );
  }

  Future<void> _showCompanyTripsModal(
    BuildContext context,
    String companyName,
    List<dynamic> companyTrips,
  ) async {
    String selectedStatus = 'All states';
    String sortBy = 'Date';
    bool ascending = false;
    String searchQuery = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final trips = companyTrips.where((trip) {
            final driver =
                (trip['user_account']?['full_name'] ??
                        trip['driver_name'] ??
                        'Unassigned')
                    .toString();
            final searchableText = [
              'TRIP-${trip['trip_id'] ?? ''}',
              trip['trip_id']?.toString() ?? '',
              trip['route_name']?.toString() ?? '',
              _date(trip),
              driver,
            ].join(' ').toLowerCase();
            final matchesSearch =
                searchQuery.trim().isEmpty ||
                searchableText.contains(searchQuery.trim().toLowerCase());
            final matchesStatus =
                selectedStatus == 'All states' ||
                _statusLabel(trip) == selectedStatus;
            return matchesSearch && matchesStatus;
          }).toList();
          trips.sort((a, b) {
            int result;
            if (sortBy == 'Status') {
              result = _statusLabel(a).compareTo(_statusLabel(b));
            } else if (sortBy == 'Trip ID') {
              result = (a['trip_id'] ?? '').toString().compareTo(
                (b['trip_id'] ?? '').toString(),
              );
            } else {
              result = _date(a).compareTo(_date(b));
            }
            return ascending ? result : -result;
          });

          return AlertDialog(
            title: Text('$companyName trips'),
            content: SizedBox(
              width: 820,
              height: 560,
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 250,
                        height: 36,
                        child: TextField(
                          autofocus: false,
                          onChanged: (value) =>
                              setModalState(() => searchQuery = value),
                          decoration: InputDecoration(
                            hintText: 'Search trip, route, date or driver',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                      ),
                      _modalDropdown<String>(
                        'State',
                        selectedStatus,
                        _statusOptions,
                        (value) => setModalState(
                          () => selectedStatus = value ?? 'All states',
                        ),
                      ),
                      _modalDropdown<String>(
                        'Sort',
                        sortBy,
                        const ['Date', 'Status', 'Trip ID'],
                        (value) =>
                            setModalState(() => sortBy = value ?? 'Date'),
                      ),
                      IconButton(
                        tooltip: ascending ? 'Ascending' : 'Descending',
                        onPressed: () =>
                            setModalState(() => ascending = !ascending),
                        icon: Icon(
                          ascending ? Icons.arrow_upward : Icons.arrow_downward,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: trips.isEmpty
                        ? const Center(
                            child: Text('No trips match this state.'),
                          )
                        : ListView.separated(
                            itemCount: trips.length,
                            separatorBuilder: (_, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) => _modalTripRow(
                              trips[index],
                              Theme.of(context).brightness == Brightness.dark,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _modalDropdown<T>(
    String label,
    T value,
    List<T> values,
    ValueChanged<T?> onChanged,
  ) {
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          hint: Text(label),
          items: values
              .map(
                (item) =>
                    DropdownMenuItem(value: item, child: Text(item.toString())),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _modalTripRow(dynamic trip, bool isDark) {
    final status = _statusLabel(trip);
    final statusColor = status == 'Completed'
        ? const Color(0xFF10B981)
        : status == 'Rejected' || status == 'Expired'
        ? const Color(0xFFEF4444)
        : status == 'Ongoing'
        ? const Color(0xFFF59E0B)
        : const Color(0xFF3B82F6);
    final mutedColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'TRIP-${trip['trip_id'] ?? 'N/A'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text((trip['route_name'] ?? 'Unassigned route').toString()),
                Text(
                  'Date: ${_date(trip).isEmpty ? 'N/A' : _date(trip)}',
                  style: TextStyle(color: mutedColor, fontSize: 12),
                ),
                Text(
                  'Passengers: ${_passengers(trip)}',
                  style: TextStyle(color: mutedColor, fontSize: 12),
                ),
                Text(
                  'Driver: ${(trip['user_account']?['full_name'] ?? trip['driver_name'] ?? 'Unassigned').toString()}',
                  style: TextStyle(color: mutedColor, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTripsModal(
    BuildContext context,
    String title,
    List<dynamic> trips,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final mutedColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 760,
          height: 520,
          child: trips.isEmpty
              ? Center(
                  child: Text(
                    'No trips found for this selection.',
                    style: TextStyle(color: mutedColor),
                  ),
                )
              : ListView.separated(
                  itemCount: trips.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final trip = trips[index];
                    final status = _statusLabel(trip);
                    final statusColor = status == 'Completed'
                        ? const Color(0xFF10B981)
                        : status == 'Rejected' || status == 'Expired'
                        ? const Color(0xFFEF4444)
                        : status == 'Ongoing'
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF3B82F6);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'TRIP-${trip['trip_id'] ?? 'N/A'}',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            (trip['route_name'] ?? 'Unassigned route')
                                .toString(),
                            style: TextStyle(color: textColor),
                          ),
                          Text(
                            'Date: ${_date(trip).isEmpty ? 'N/A' : _date(trip)}',
                            style: TextStyle(color: mutedColor, fontSize: 12),
                          ),
                          Text(
                            'Passengers: ${_passengers(trip)}',
                            style: TextStyle(color: mutedColor, fontSize: 12),
                          ),
                          Text(
                            'Driver: ${(trip['user_account']?['full_name'] ?? trip['driver_name'] ?? 'Unassigned').toString()}',
                            style: TextStyle(color: mutedColor, fontSize: 12),
                          ),
                          Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _companyBarChart(List<Map<String, dynamic>> summaries, bool isDark) {
    final visible = summaries.take(8).toList();
    final maxValue = visible.isEmpty
        ? 1.0
        : visible
              .map((item) => item['trips'] as int)
              .reduce((a, b) => a > b ? a : b)
              .toDouble();
    return BarChart(
      BarChartData(
        maxY: maxValue == 0 ? 1 : maxValue + 1,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= visible.length) {
                  return const SizedBox.shrink();
                }
                final name = visible[index]['name'].toString();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    name.length > 8 ? '${name.substring(0, 8)}...' : name,
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        barGroups: visible.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: (entry.value['trips'] as int).toDouble(),
                color: const Color(0xFF3B82F6),
                width: 22,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _scheduleLineChart(bool isDark) {
    final counts = <String, int>{};
    for (final trip in widget.trips) {
      final date = _date(trip);
      if (date.isNotEmpty) counts[date] = (counts[date] ?? 0) + 1;
    }
    final dates = counts.keys.toList()..sort();
    final visible = dates.length > 12
        ? dates.sublist(dates.length - 12)
        : dates;
    final spots = visible
        .asMap()
        .entries
        .map(
          (entry) =>
              FlSpot(entry.key.toDouble(), counts[entry.value]!.toDouble()),
        )
        .toList();
    return LineChart(
      LineChartData(
        minY: 0,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= visible.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    visible[index].length >= 10
                        ? visible[index].substring(5)
                        : visible[index],
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF10B981),
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _companyTable(
    List<Map<String, dynamic>> summaries,
    Color cardColor,
    Color textColor,
    Color mutedColor,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: mutedColor.withValues(alpha: 0.2)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            mutedColor.withValues(alpha: 0.08),
          ),
          columns: const [
            DataColumn(label: Text('Company')),
            DataColumn(label: Text('Trips')),
            DataColumn(label: Text('Personnel')),
            DataColumn(label: Text('People moved')),
            DataColumn(label: Text('Avg / trip')),
            DataColumn(label: Text('Scheduled dates')),
          ],
          rows: summaries.map((item) {
            return DataRow(
              cells: [
                DataCell(Text(item['name'].toString())),
                DataCell(Text(item['trips'].toString())),
                DataCell(Text(item['personnel'].toString())),
                DataCell(Text(item['passengers'].toString())),
                DataCell(Text((item['average'] as double).toStringAsFixed(1))),
                DataCell(Text(item['dates'].toString())),
              ],
            );
          }).toList(),
          dataTextStyle: TextStyle(color: textColor, fontSize: 12),
          headingTextStyle: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _emptyState(Color cardColor, Color textColor, Color mutedColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: mutedColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(Icons.business_outlined, color: mutedColor, size: 40),
          const SizedBox(height: 10),
          Text(
            'No company trip data available',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
