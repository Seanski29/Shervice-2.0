import 'package:flutter/material.dart';

class DriverRatings extends StatelessWidget {
  const DriverRatings({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20.0),
      children: [
        const Text(
          'My Performance',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 24),

        // Big Rating Display
        Center(
          child: Column(
            children: [
              const Text('Overall Rating', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star, color: Colors.amber.shade500, size: 48),
                  const SizedBox(width: 8),
                  const Text('4.9', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                ],
              ),
              const Text('Based on 124 trips', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Areas to Improve (Progress Bars)
        const Text('METRICS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).dividerColor)),
          child: Column(
            children: [
              _buildMetricBar('Punctuality', 0.98, Colors.green),
              const SizedBox(height: 16),
              _buildMetricBar('Safety Protocol', 0.95, Colors.green),
              const SizedBox(height: 16),
              _buildMetricBar('Vehicle Cleanliness', 0.70, Colors.orange), // Highlighted area for improvement
            ],
          ),
        ),
        
        const SizedBox(height: 24),

        // Feedback / Improvement Notes
        const Text('AREAS FOR IMPROVEMENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.orange.shade200)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.orange.shade800),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vehicle Cleanliness', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                    const SizedBox(height: 4),
                    Text(
                      'Recent dispatch notes indicate minor dust build-up in the passenger cabin. Please ensure a quick sweep before shift start.',
                      style: TextStyle(color: Colors.orange.shade900, fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildMetricBar(String label, double score, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${(score * 100).toInt()}%', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}