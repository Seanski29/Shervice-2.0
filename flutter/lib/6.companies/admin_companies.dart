import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../layouts/enterprise/enterprise_data_grid.dart';
import '../layouts/enterprise/enterprise_states.dart';
import 'package:http/http.dart' as http;
import '../constant.dart';
import '../utilities/file_download.dart';

class AdminCompanies extends StatefulWidget {
  const AdminCompanies({super.key});

  @override
  State<AdminCompanies> createState() => _AdminCompaniesState();
}

class _AdminCompaniesState extends State<AdminCompanies> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  List<dynamic> _companies = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchCompanies();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch companies error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isInternalCompany(Map<String, dynamic> company) =>
      (company['company_name'] ?? '').toString().toUpperCase().contains('INTERNAL');

  Future<void> _addCompanyDialog() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text(
          'Add Client Company',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: 'Company Name',
                hintText: 'e.g. Bandai, EPSON, Denso',
                prefixIcon: const Icon(Icons.business),
                filled: true,
                fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: 'Address',
                hintText: 'Company street, city, and province',
                prefixIcon: const Icon(Icons.location_on_outlined),
                filled: true,
                fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
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
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: () async {
              final name = nameController.text.trim();
              final address = addressController.text.trim();
              if (name.isEmpty || address.isEmpty) return;
              Navigator.pop(ctx);
              _submitAddCompany(name, address);
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
    nameController.dispose();
    addressController.dispose();
  }

  Future<void> _submitAddCompany(String name, String address) async {
    setState(() => _isLoading = true);
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/companies'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'company_name': name, 'address': address}),
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
    final confirmed = await showEnterpriseDestructiveConfirmation(
      context,
      title: 'Delete company record?',
      message:
          'This permanently removes "$companyName". Companies with assigned users remain protected until those accounts are reassigned.',
    );
    if (confirmed) await _deleteCompany(company);
  }

  Future<void> _editCompanyDialog(Map<String, dynamic> company) async {
    final nameController = TextEditingController(
      text: (company['company_name'] ?? '').toString(),
    );
    final addressController = TextEditingController(
      text: (company['address'] ?? '').toString(),
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Company Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Company Name'),
            ),
            TextField(
              controller: addressController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final address = addressController.text.trim();
              if (name.isEmpty || address.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final response = await http.put(
                  Uri.parse('$backendUrl/companies/${company['company_id']}'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'company_name': name, 'address': address}),
                );
                final result = jsonDecode(response.body);
                if (response.statusCode == 200 && result['success'] == true) {
                  _showSnackBar(
                    'Company details updated.',
                    const Color(0xFF10B981),
                  );
                  await _fetchCompanies();
                } else {
                  _showSnackBar(
                    result['message'] ?? 'Company update failed.',
                    const Color(0xFFEF4444),
                  );
                }
              } catch (error) {
                _showSnackBar(
                  'Company update failed: $error',
                  const Color(0xFFEF4444),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    addressController.dispose();
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

  Future<void> _deleteCompanyDirect(Map<String, dynamic> company) async {
    if (_isInternalCompany(company)) return;
    final response = await http
        .delete(Uri.parse('$backendUrl/companies/${company['company_id']}'))
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      if (data['has_assigned_users'] == true) {
        if (mounted) {
          _showActionBlockedDialog(
            company['company_name'] ?? 'Company',
            data['assigned_count'] ?? 1,
          );
        }
        throw Exception(
          'Company retained because active users are still assigned.',
        );
      }
      throw Exception(data['message'] ?? 'Unable to delete company.');
    }
    await _fetchCompanies();
  }

  Future<void> _deleteCompanies(List<Map<String, dynamic>> companies) async {
    final eligible = companies.where((company) => !_isInternalCompany(company));
    for (final company in eligible) {
      await _deleteCompanyDirect(company);
    }
  }

  Future<void> _exportCompanies(List<Map<String, dynamic>> companies) async {
    final buffer = StringBuffer('Company ID,Company,Address,Assigned Users\n');
    for (final company in companies) {
      String csv(dynamic value) =>
          (value ?? '').toString().replaceAll('"', '""');
      buffer.writeln(
        '"${csv(company['company_id'])}",'
        '"${csv(company['company_name'])}",'
        '"${csv(company['address'])}",'
        '"${csv(company['user_count'])}"',
      );
    }
    await downloadFileBytes(
      fileName: 'shervice-companies.csv',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
    );
    if (mounted) {
      EnterpriseToasts.success(
        context,
        '${companies.length} companies exported.',
      );
    }
  }

  void _showActionBlockedDialog(String companyName, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Row(
          children: const [
            Icon(Icons.lock_outline, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text(
              'Deletion Locked',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Cannot delete "$companyName" because $count active user account${count > 1 ? 's are' : ' is'} currently assigned to it.\n\nOpen Users and reassign or delete the associated accounts first.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final companies = _companies
        .where((company) {
          final name = (company['company_name'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery.toLowerCase());
        })
        .map((company) => Map<String, dynamic>.from(company as Map))
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. TOP ROW: Title on Left, Actions on Right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Companies',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 280,
                      height: 42,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _searchQuery = value),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search company name',
                          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                          filled: true,
                          fillColor: Theme.of(context).cardColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Theme.of(context).dividerColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _addCompanyDialog,
                      icon: const Icon(Icons.add_business_outlined, size: 17),
                      label: const Text('Add company'),
                      style: FilledButton.styleFrom(
                       
                        minimumSize: const Size(0, 42),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _fetchCompanies,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Refresh'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // 4. MAIN WORKSPACE TABLE
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top-Left Anchored Table Counter
                  const SizedBox(height: 12),
                  Expanded(
                    child: EnterpriseDataGrid<Map<String, dynamic>>(
                      loading: _isLoading,
                      rows: companies,
                      rowKey: (company) => company['company_id'] ?? company.hashCode,
                      height: double.infinity,
                      showDateRange: false, // Disables Date Range control
                      columns: [
                        EnterpriseGridColumn(
                          label: 'Company ID',
                          width: 130,
                          value: (company) => (company['company_id'] ?? '').toString(),
                        ),
                        EnterpriseGridColumn(
                          label: 'Company',
                          width: 280,
                          value: (company) =>
                              (company['company_name'] ?? 'Unnamed company').toString(),
                        ),
                        EnterpriseGridColumn(
                          label: 'Address',
                          width: 420,
                          value: (company) =>
                              (company['address'] ?? 'Not provided').toString(),
                        ),
                        EnterpriseGridColumn(
                          label: 'Assigned users',
                          width: 160,
                          value: (company) => '${company['user_count'] ?? 0}',
                          compare: (first, second) =>
                              ((first['user_count'] ?? 0) as num).compareTo(
                                (second['user_count'] ?? 0) as num,
                              ),
                        ),
                        EnterpriseGridColumn(
                          label: 'Type',
                          width: 190,
                          value: (company) => _isInternalCompany(company)
                              ? 'Primary company'
                              : 'Partner client',
                          cellBuilder: (context, company) => Text(
                            _isInternalCompany(company)
                                ? 'Primary company'
                                : 'Partner client',
                            style: TextStyle(
                              color: _isInternalCompany(company)
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF3B82F6),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        EnterpriseGridColumn(
                          label: 'Record actions',
                          width: 160,
                          value: (_) => '',
                          cellBuilder: (context, company) => _isInternalCompany(company)
                              ? const Text('Protected')
                              : OutlinedButton(
                                  onPressed: () => _editCompanyDialog(company),
                                  child: const Text('Update'),
                                ),
                        ),
                      ],
                      filterFields: const [], // Cleared to prevent duplicate search inputs
                      emptyTitle: _companies.isEmpty
                          ? 'Add the first partner company'
                          : 'Nothing matches the current search',
                      emptyMessage: _companies.isEmpty
                          ? 'Company records connect users, destinations, trips, and client reporting.'
                          : 'No company records match the current search query.',
                      emptyActionLabel: _companies.isEmpty ? 'Add first company' : null,
                      onEmptyAction: _companies.isEmpty ? _addCompanyDialog : null,
                      onDelete: _deleteCompanyDirect,
                      canDelete: (company) =>
                          !_isInternalCompany(company) &&
                          ((company['user_count'] ?? 0) as num) == 0,
                      onBulkDelete: _deleteCompanies,
                      onExportSelection: _exportCompanies,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}