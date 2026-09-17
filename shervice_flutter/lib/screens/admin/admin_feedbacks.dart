import 'package:flutter/material.dart';

class AdminFeedbacks extends StatelessWidget {
  const AdminFeedbacks({super.key});

  @override
  Widget build(BuildContext context) {
    // 🔴 1. Check if Dark Mode is active
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Define adaptive text colors
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Scaffold(
      // 🔴 2. Dynamic Scaffold Background
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, 
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            // Back Button to return to User Management
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, size: 20),
                label: const Text('Back to Users', style: TextStyle(fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Company & Driver Feedbacks',
              style: TextStyle(
                fontSize: 28, 
                fontWeight: FontWeight.bold, 
                color: primaryTextColor, 
                letterSpacing: -0.5
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Monitor client satisfaction and driver performance metrics.', 
              style: TextStyle(color: secondaryTextColor),
            ),
            const SizedBox(height: 32),

            // SECTION 1: Client Company Ratings
            Text(
              'CLIENT COMPANY RATINGS', 
              style: TextStyle(
                fontSize: 14, 
                fontWeight: FontWeight.bold, 
                color: isDark ? Colors.grey.shade500 : Colors.grey, 
                letterSpacing: 1.2
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildCompanyRatingCard(context, isDark, 'EPSON', '4.8', 124, Colors.blue.shade700),
                _buildCompanyRatingCard(context, isDark, 'Bandai', '4.6', 89, Colors.orange.shade700),
                _buildCompanyRatingCard(context, isDark, 'NX Logistics', '4.9', 56, Colors.green.shade700),
              ],
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),

            // SECTION 2: Individual Driver Ratings
            Text(
              'DRIVER PERFORMANCE FEEDBACKS', 
              style: TextStyle(
                fontSize: 14, 
                fontWeight: FontWeight.bold, 
                color: isDark ? Colors.grey.shade500 : Colors.grey, 
                letterSpacing: 1.2
              ),
            ),
            const SizedBox(height: 16),
            
            _buildDriverFeedbackCard(
              context: context,
              isDark: isDark,
              driverName: 'Ricardo Ramos',
              assignedCompany: 'EPSON',
              rating: '4.9',
              recentComment: '"Very punctual and drives safely. The employees appreciate the smooth ride every morning."',
              date: 'Jun 20, 2026',
            ),
            _buildDriverFeedbackCard(
              context: context,
              isDark: isDark,
              driverName: 'Miguel Santos',
              assignedCompany: 'Bandai',
              rating: '4.2',
              recentComment: '"Driver was a bit late due to traffic, but communication was good. AC in the van could be colder."',
              date: 'Jun 19, 2026',
            ),
            _buildDriverFeedbackCard(
              context: context,
              isDark: isDark,
              driverName: 'Juan Dela Cruz',
              assignedCompany: 'NX Logistics',
              rating: '4.8',
              recentComment: '"Excellent service. Always on standby exactly when the shift ends."',
              date: 'Jun 18, 2026',
            ),

            const SizedBox(height: 16),
            _buildResponsivePagination(isDark, '1 to 3 of 42 drivers'),
          ],
        ),
      ),
    );
  }

  // Card showing the average rating given by a specific company
  Widget _buildCompanyRatingCard(BuildContext context, bool isDark, String companyName, String avgRating, int totalReviews, Color brandColor) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, // 🔴 Dynamic Card Color
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor), // 🔴 Dynamic Border Color
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02), 
            blurRadius: 10, 
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business, color: brandColor),
              const SizedBox(width: 8),
              Text(
                companyName, 
                style: TextStyle(
                  fontSize: 16, 
                  fontWeight: FontWeight.bold, 
                  color: isDark ? Colors.white : const Color(0xFF0F172A)
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                avgRating, 
                style: TextStyle(
                  fontSize: 32, 
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 6.0),
                child: Icon(Icons.star, color: Colors.amber, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Based on $totalReviews trip reviews', 
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, 
              fontSize: 12
            ),
          ),
        ],
      ),
    );
  }

  // Card showing individual driver feedback
  Widget _buildDriverFeedbackCard({
    required BuildContext context,
    required bool isDark,
    required String driverName,
    required String assignedCompany,
    required String rating,
    required String recentComment,
    required String date,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, // 🔴 Dynamic Card Color
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor), // 🔴 Dynamic Border Color
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade50,
                    child: const Icon(Icons.person, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driverName, 
                        style: TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.bold, 
                          color: isDark ? Colors.white : const Color(0xFF0F172A)
                        ),
                      ),
                      Text(
                        'Assigned to: $assignedCompany', 
                        style: TextStyle(
                          fontSize: 12, 
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.amber.withValues(alpha: 0.1) : Colors.amber.shade50,
                  border: Border.all(
                    color: isDark ? Colors.amber.withValues(alpha: 0.3) : Colors.amber.shade200
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, color: Colors.amber.shade700, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '$rating Avg', 
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        color: isDark ? Colors.amber.shade400 : Colors.amber.shade900, 
                        fontSize: 13
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12), 
            child: Divider(height: 1)
          ),
          Text(
            'Recent OIC Comment ($date):', 
            style: TextStyle(
              fontSize: 12, 
              fontWeight: FontWeight.bold, 
              color: isDark ? Colors.grey.shade500 : Colors.grey
            ),
          ),
          const SizedBox(height: 8),
          Text(
            recentComment, 
            style: TextStyle(
              fontStyle: FontStyle.italic, 
              color: isDark ? Colors.grey.shade200 : const Color(0xFF0F172A)
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsivePagination(bool isDark, String text) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16, 
      runSpacing: 16,
      children: [
        Text(
          'Showing $text', 
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, 
            fontSize: 13
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () {}, 
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
              ), 
              child: Text('Prev', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
              decoration: BoxDecoration(
                color: Colors.blue.shade600, 
                borderRadius: BorderRadius.circular(8)
              ), 
              child: const Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            OutlinedButton(
              onPressed: () {}, 
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
              ), 
              child: Text('Next', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
            ),
          ],
        )
      ],
    );
  }
}