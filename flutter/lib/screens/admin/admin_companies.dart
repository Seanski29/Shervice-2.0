import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../widgets/shared/enterprise_data_grid.dart';
import '../../widgets/shared/enterprise_states.dart';
import 'package:http/http.dart' as http;
import '../../constant.dart';
import '../../utils/file_download.dart';
import '../../theme/enterprise_theme.dart';

class AdminCompanies extends StatefulWidget {
  const AdminCompanies({super.key});

  @override
  State<AdminCompanies> createState() => _AdminCompaniesState();
}

class _CompanyMetadata extends StatelessWidget {
  const _CompanyMetadata({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
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

  void _showActionBlockedDialog(String companyName, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
          'Cannot delete "$companyName" because $count active user account${count > 1 ? 's are' : ' is'} currently assigned to it.\n\nOpen Users and reassign or delete the associated accounts first.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
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

  Widget _buildTitle(Color textColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${_companies.length} company records  |  Owner: Admin',
        style: Theme.of(context).textTheme.bodySmall,
      ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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

  bool _isInternalCompany(Map<String, dynamic> company) =>
      (company['company_name'] ?? '').toString().toUpperCase().contains(
        'INTERNAL',
      );

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

  @override
  Widget build(BuildContext context) {
    final companies = _companies
        .where((company) {
          final name = (company['company_name'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery.toLowerCase());
        })
        .map((company) => Map<String, dynamic>.from(company as Map))
        .toList();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _CompanyMetadata(label: '${_companies.length} company records'),
              const _CompanyMetadata(label: 'Owner: Admin'),
              FilledButton.icon(
                onPressed: _addCompanyDialog,
                icon: const Icon(Icons.add_business_outlined, size: 17),
                label: const Text('Add company'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: EnterpriseDataGrid<Map<String, dynamic>>(
              loading: _isLoading,
              rows: companies,
              rowKey: (company) => company['company_id'] ?? company.hashCode,
              height: double.infinity,
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
                          ? EnterpriseColors.information
                          : EnterpriseColors.success,
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
                      : TextButton.icon(
                          onPressed: () => _editCompanyDialog(company),
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: const Text('Edit'),
                        ),
                ),
              ],
              filterFields: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Filter company name',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _fetchCompanies,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('Refresh'),
                ),
              ],
              emptyTitle: _companies.isEmpty
                  ? 'Add the first partner company'
                  : 'Adjust the company filter',
              emptyMessage: _companies.isEmpty
                  ? 'Company records connect users, destinations, trips, and client reporting.'
                  : 'No company records match the current search query.',
              emptyActionLabel: _companies.isEmpty
                  ? 'Add first company'
                  : 'Clear filter',
              onEmptyAction: () {
                if (_companies.isEmpty) {
                  _addCompanyDialog();
                } else {
                  setState(() => _searchQuery = '');
                }
              },
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
    );
  }

  Widget _buildLegacyCompanyDirectory(BuildContext context) {
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
                    borderRadius: BorderRadius.circular(4),
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
                  ? const Center(child: EnterpriseLoadingIndicator())
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
                            borderRadius: BorderRadius.circular(4),
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
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
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
                                    if ((comp['address'] ?? '')
                                        .toString()
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        comp['address'].toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
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
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: Color(0xFF2563EB),
                                  ),
                                  tooltip: 'Edit Company',
                                  onPressed: () => _editCompanyDialog(
                                    Map<String, dynamic>.from(comp),
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
