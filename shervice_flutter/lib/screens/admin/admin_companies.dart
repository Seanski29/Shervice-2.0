import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../constant.dart';

class AdminCompanies extends StatefulWidget {
  const AdminCompanies({super.key});

  @override
  State<AdminCompanies> createState() => _AdminCompaniesState();
}

class _AdminCompaniesState extends State<AdminCompanies> {
  static const int _itemsPerPage = 10;
  bool _isLoading = true;
  List<dynamic> _companies = [];
  String _searchQuery = '';
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _fetchCompanies();
  }

  Future<void> _fetchCompanies() async {
    setState(() => _isLoading = true);
    try {
      final res = await http
          .get(Uri.parse('$backendUrl/companies'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() {
            _companies = data['data'] ?? [];
            _currentPage = 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch companies error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addCompanyDialog() async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add Client Company',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            labelText: 'Company Name',
            hintText: 'e.g. Bandai, EPSON, Denso',
            prefixIcon: const Icon(Icons.business),
            filled: true,
            fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              _submitAddCompany(name);
            },
            child: const Text(
              'Add Company',
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

  Future<void> _submitAddCompany(String name) async {
    setState(() => _isLoading = true);
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/companies'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'company_name': name}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (res.statusCode == 201 && data['success'] == true) {
        _showSnackBar("Company added successfully!", const Color(0xFF10B981));
      } else {
        _showSnackBar(
          data['message'] ?? "Failed to add company.",
          const Color(0xFFEF4444),
        );
      }
    } catch (e) {
      _showSnackBar("Network error: $e", const Color(0xFFEF4444));
    } finally {
      _fetchCompanies();
    }
  }

  Future<void> _confirmDeleteCompany(Map<String, dynamic> company) async {
    final companyName = company['company_name'] ?? '';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text(
              'Confirm Deletion',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "$companyName"?\n\nNote: Companies with active assigned accounts cannot be deleted until those users are reassigned.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteCompany(company);
            },
            child: const Text(
              'Delete',
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

  Future<void> _deleteCompany(Map<String, dynamic> company) async {
    setState(() => _isLoading = true);
    final id = company['company_id'];

    try {
      final res = await http
          .delete(Uri.parse('$backendUrl/companies/$id'))
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success'] == true) {
        _showSnackBar(
          data['message'] ?? "Company deleted successfully.",
          const Color(0xFF10B981),
        );
      } else {
        if (data['has_assigned_users'] == true) {
          _showActionBlockedDialog(
            company['company_name'] ?? 'Company',
            data['assigned_count'] ?? 1,
          );
        } else {
          _showSnackBar(
            data['message'] ?? "Cannot delete company.",
            const Color(0xFFEF4444),
          );
        }
      }
    } catch (e) {
      _showSnackBar("Network error: $e", const Color(0xFFEF4444));
    } finally {
      _fetchCompanies();
    }
  }

  void _showActionBlockedDialog(String companyName, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text(
              'Deletion Locked',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Cannot delete "$companyName" because $count active user account${count > 1 ? 's are' : ' is'} currently assigned to it.\n\nTo delete this company, go to "User Management" and reassign or delete the associated user accounts first.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Understood',
              style: TextStyle(color: Colors.white),
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

  Widget _buildTitle(Color textColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Company Management',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Manage partner client accounts and dispatch destinations.',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildAddCompanyButton() {
    return ElevatedButton.icon(
      onPressed: _addCompanyDialog,
      icon: const Icon(Icons.add, color: Colors.white, size: 18),
      label: const Text(
        'Add Company',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF3B82F6),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<dynamic> _pageItems(List<dynamic> filtered) {
    final start = _currentPage * _itemsPerPage;
    if (start >= filtered.length) return const [];
    final end = (start + _itemsPerPage).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  Widget _buildPaginationFooter(int totalItems, bool isDark) {
    final totalPages = max(1, (totalItems / _itemsPerPage).ceil());

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous page',
          onPressed: _currentPage == 0
              ? null
              : () => setState(() => _currentPage--),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '${_currentPage + 1} / $totalPages',
          style: TextStyle(
            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
        IconButton(
          tooltip: 'Next page',
          onPressed: _currentPage >= totalPages - 1
              ? null
              : () => setState(() => _currentPage++),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 950;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    final filtered = _companies.where((c) {
      final name = (c['company_name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTitle(textColor, isDark),
                      const SizedBox(height: 12),
                      _buildAddCompanyButton(),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTitle(textColor, isDark),
                      _buildAddCompanyButton(),
                    ],
                  ),
            const SizedBox(height: 20),

            // Search Bar
            SizedBox(
              height: 42,
              child: TextField(
                onChanged: (v) => setState(() {
                  _searchQuery = v;
                  _currentPage = 0;
                }),
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search companies...',
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade300,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Company List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? Center(
                      child: Text(
                        "No companies found.",
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _pageItems(filtered).length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index == _pageItems(filtered).length) {
                          return _buildPaginationFooter(
                            filtered.length,
                            isDark,
                          );
                        }
                        final comp = _pageItems(filtered)[index];
                        final name = comp['company_name'] ?? 'Unnamed Company';
                        final int userCount = comp['user_count'] ?? 0;
                        final bool isInternal = name
                            .toString()
                            .toUpperCase()
                            .contains('INTERNAL');

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF3B82F6,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.business,
                                  color: Color(0xFF3B82F6),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isInternal
                                          ? "System Primary Company"
                                          : "Partner Enterprise Client",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isInternal)
                                IconButton(
                                  icon: Icon(
                                    userCount > 0
                                        ? Icons.lock_outline
                                        : Icons.delete_outline,
                                    color: userCount > 0
                                        ? Colors.grey.shade400
                                        : const Color(0xFFEF4444),
                                  ),
                                  tooltip: userCount > 0
                                      ? 'Locked: $userCount user(s) assigned'
                                      : 'Delete Company',
                                  onPressed: userCount > 0
                                      ? () => _showActionBlockedDialog(
                                          name,
                                          userCount,
                                        )
                                      : () => _confirmDeleteCompany(comp),
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
  }
}