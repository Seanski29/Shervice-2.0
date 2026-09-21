import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../layouts/enterprise/enterprise_states.dart';
import '../../layouts/enterprise/enterprise_data_grid.dart';
import 'package:http/http.dart' as http;
import '../../constant.dart';
import '../../utils/file_download.dart';
import '../../layouts/enterprise/enterprise_theme.dart';

// --- MAIN DASHBOARD COMPONENT ---
class AdminUsers extends StatefulWidget {
  const AdminUsers({super.key});

  @override
  State<AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsers> {
  // --- State Variables ---
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  List<dynamic> _allUsers = [];
  List<dynamic> _filteredUsers = [];

  // Filtering, Searching & Sorting Configuration
  String _searchQuery = '';
  String _currentSort = 'Name (A to Z)';
  final List<String> _sortOptions = ['Name (A to Z)', 'Name (Z to A)', 'Role'];

  @override
  void initState() {
    super.initState();
    _fetchSystemUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSystemUsers() async {
    setState(() => _isLoading = true);
    try {
      final response = await http
          .get(Uri.parse('$backendUrl/auth/system-users'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _allUsers = data['data'] ?? [];
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch users: $e");
      _allUsers = [];
    } finally {
      if (mounted) {
        _applyFiltersAndSort();
      }
    }
  }

  void _applyFiltersAndSort() {
    List<dynamic> temp = _allUsers.where((user) {
      final name = (user['name'] ?? '').toString().toLowerCase();
      final email = (user['email'] ?? '').toString().toLowerCase();
      final company = (user['company'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) ||
          email.contains(_searchQuery.toLowerCase()) ||
          company.contains(_searchQuery.toLowerCase());
    }).toList();

    temp.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      final roleA = (a['role'] ?? '').toString().toLowerCase();
      final roleB = (b['role'] ?? '').toString().toLowerCase();

      switch (_currentSort) {
        case 'Name (Z to A)':
          return nameB.compareTo(nameA);
        case 'Role':
          return roleA.compareTo(roleB);
        case 'Name (A to Z)':
        default:
          return nameA.compareTo(nameB);
      }
    });

    setState(() {
      _filteredUsers = temp;
      _isLoading = false;
    });
  }

  Future<void> _confirmPurgeUser(Map<String, dynamic> user) async {
    final confirmed = await showEnterpriseDestructiveConfirmation(
      context,
      title: 'Delete user account?',
      message:
          'This permanently revokes access and deletes the account record for ${user['name']}.',
    );
    if (!confirmed) return;
    try {
      await _deleteUserDirect(user);
      if (mounted) EnterpriseToasts.success(context, 'User account deleted.');
    } catch (error) {
      if (mounted) {
        EnterpriseToasts.error(context, 'Unable to delete user: $error');
      }
    }
  }

  void _showUserModal(BuildContext context, {Map<String, dynamic>? user}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return RegisterUserDialog(
          user: user,
          onDelete: user == null ? null : () => _confirmPurgeUser(user),
        );
      },
    ).then((_) {
      if (mounted) {
        setState(() => _isLoading = true);
        _fetchSystemUsers();
      }
    });
  }

  Future<void> _deleteUserDirect(Map<String, dynamic> user) async {
    final response = await http
        .delete(Uri.parse('$backendUrl/auth/delete-user/${user['id']}'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Unable to delete the selected user account.');
    }
    await _fetchSystemUsers();
  }

  Future<void> _deleteUsers(List<Map<String, dynamic>> users) async {
    for (final user in users) {
      await _deleteUserDirect(user);
    }
  }

  Future<void> _exportUsers(List<Map<String, dynamic>> users) async {
    final buffer = StringBuffer(
      'Staff ID,Name,Email,Company,Role,Permission,Status\n',
    );
    for (final user in users) {
      String csv(dynamic value) =>
          (value ?? '').toString().replaceAll('"', '""');
      buffer.writeln(
        '"${csv(user['id'])}","${csv(user['name'])}",'
        '"${csv(user['email'])}","${csv(user['company'])}",'
        '"${csv(user['role'])}","${csv(user['permission'])}",'
        '"${csv(user['status'])}"',
      );
    }
    await downloadFileBytes(
      fileName: 'shervice-users.csv',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
    );
    if (mounted) {
      EnterpriseToasts.success(context, '${users.length} users exported.');
    }
  }

  Widget _buildSummaryCards(bool isDark) {
    final int total = _allUsers.length;
    final int active = _allUsers
        .where((u) => (u['status'] ?? '').toString().toLowerCase() == 'active')
        .length;
    final int inactive = total - active;
    final cards = [
      (
        'Total Staff',
        '$total',
        Icons.people_alt_outlined,
        const Color(0xFF3B82F6),
      ),
      (
        'Active Staff',
        '$active',
        Icons.check_circle_outline,
        const Color(0xFF10B981),
      ),
      (
        'Inactive Staff',
        '$inactive',
        Icons.person_off_outlined,
        const Color(0xFFF59E0B),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;
        final cardWidgets = cards.map((card) {
          final Color baseColor = card.$4;
          return Container(
            constraints: const BoxConstraints(minHeight: 112),
            width: isNarrow ? double.infinity : null,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: 0.08),
              border: Border.all(color: baseColor.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min, // Prevents vertical overflow
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(card.$3, color: baseColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        card.$1,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: baseColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  card.$2,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    height: 1.0, // Trims internal font padding
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          );
        }).toList();

        if (isNarrow) {
          return Column(
            children: cardWidgets
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: c,
                  ),
                )
                .toList(),
          );
        }
        return Row(
          children: [
            for (var index = 0; index < cardWidgets.length; index++) ...[
              if (index > 0) const SizedBox(width: 16),
              Expanded(child: cardWidgets[index]),
            ],
          ],
        );
      },
    );
  }

  Widget _sortDropdown(bool isDark) {
    return Container(
      height: 34,
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _currentSort,
          isExpanded: true,
          isDense: true,
          icon: const Padding(
            padding: EdgeInsets.only(left: 8.0),
            child: Icon(Icons.sort, size: 16),
          ),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          dropdownColor: Theme.of(context).cardColor,
          selectedItemBuilder: (BuildContext context) {
            return _sortOptions.map((String value) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Text('Sort: $value', overflow: TextOverflow.ellipsis),
              );
            }).toList();
          },
          items: _sortOptions
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final users = _filteredUsers
        .map((user) => Map<String, dynamic>.from(user as Map))
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
                      'Users',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage system access and account roles.',
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade400
                            : const Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _showUserModal(context),
                      icon: const Icon(Icons.person_add_alt_1, size: 17),
                      label: const Text('Register user'),
                      style: FilledButton.styleFrom(
                        backgroundColor: EnterpriseColors.generativeAction,
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _fetchSystemUsers,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 2. CARDS BEFORE FILTERS
            if (_isLoading)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 900;
                  if (isNarrow) {
                    return Column(
                      children: List.generate(
                        4,
                        (_) => const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: SizedBox(
                            height: 112,
                            width: double.infinity,
                            child: EnterpriseSummaryCardSkeleton(),
                          ),
                        ),
                      ),
                    );
                  }
                  return Row(
                    children: const [
                      Expanded(
                        child: SizedBox(
                          height: 112,
                          child: EnterpriseSummaryCardSkeleton(),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 112,
                          child: EnterpriseSummaryCardSkeleton(),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 112,
                          child: EnterpriseSummaryCardSkeleton(),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 112,
                          child: EnterpriseSummaryCardSkeleton(),
                        ),
                      ),
                    ],
                  );
                },
              )
            else
              _buildSummaryCards(isDark),

            const SizedBox(height: 32),

            // 3. MAIN WORKSPACE TABLE (WITH FILTERS ANCHORED LEFT)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: EnterpriseDataGrid<Map<String, dynamic>>(
                      loading: _isLoading,
                      rows: users,
                      rowKey: (user) => user['id'] ?? user.hashCode,
                      height: double.infinity,
                      showDateRange: false, // Disables Date Range control
                      filterFields: [
                        SizedBox(
                          width: 320,
                          height: 34,
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                                _applyFiltersAndSort();
                              });
                            },
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search user name, email, or company',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                              filled: true,
                              fillColor: Theme.of(context).cardColor,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _sortDropdown(isDark),
                      ],
                      columns: [
                        EnterpriseGridColumn(
                          label: 'Staff ID',
                          width: 130,
                          value: (user) => (user['staff_id'] ?? '').toString(),
                        ),
                        EnterpriseGridColumn(
                          label: 'Name',
                          width: 230,
                          value: (user) =>
                              (user['name'] ?? 'System User').toString(),
                        ),
                        EnterpriseGridColumn(
                          label: 'Email',
                          width: 260,
                          value: (user) =>
                              (user['email'] ?? 'Not provided').toString(),
                        ),
                        EnterpriseGridColumn(
                          label: 'Company',
                          width: 220,
                          value: (user) =>
                              (user['company'] ?? 'Internal').toString(),
                        ),
                        EnterpriseGridColumn(
                          label: 'Role',
                          width: 130,
                          value: (user) => (user['role'] ?? 'Staff').toString(),
                        ),
                        EnterpriseGridColumn(
                          label: 'Permission',
                          width: 150,
                          value: (user) =>
                              (user['permission'] ?? 'Standard').toString(),
                        ),
                        EnterpriseGridColumn(
                          label: 'Status',
                          width: 130,
                          value: (user) =>
                              (user['status'] ?? 'Active').toString(),
                          cellBuilder: (context, user) {
                            final status = (user['status'] ?? 'Active')
                                .toString();
                            final active = status.toLowerCase() == 'active';
                            return Text(
                              status,
                              style: TextStyle(
                                color: active
                                    ? EnterpriseColors.success
                                    : EnterpriseColors.warning,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                        EnterpriseGridColumn(
                          label: 'Record actions',
                          width: 170,
                          value: (_) => '',
                          cellBuilder: (context, user) => OutlinedButton(
                            onPressed: () =>
                                _showUserModal(context, user: user),
                            child: const Text('Update'),
                          ),
                        ),
                      ],
                      emptyTitle: _allUsers.isEmpty
                          ? 'Register the first user'
                          : 'Nothing matches the current search or filters',
                      emptyMessage: _allUsers.isEmpty
                          ? 'Create an account to establish role-based access to Shervice.'
                          : 'No user accounts match the current search and sort criteria.',
                      emptyActionLabel: _allUsers.isEmpty
                          ? 'Register first user'
                          : null,
                      onEmptyAction: _allUsers.isEmpty
                          ? () => _showUserModal(context)
                          : null,
                      onDelete: _deleteUserDirect,
                      onBulkDelete: _deleteUsers,
                      onExportSelection: _exportUsers,
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

// ============================================================================
// REGISTER USER DIALOG
// ============================================================================
class RegisterUserDialog extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback? onDelete;

  const RegisterUserDialog({super.key, this.user, this.onDelete});

  @override
  State<RegisterUserDialog> createState() => _RegisterUserDialogState();
}

class _RegisterUserDialogState extends State<RegisterUserDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isWritingUnlocked = false;

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;

  String? _selectedRole;
  String? _selectedCompany;
  List<String> _companyOptions = ['GT LANTIN INTERNAL'];

  @override
  void initState() {
    super.initState();
    final bool isEdit = widget.user != null;
    _isWritingUnlocked = !isEdit;

    _nameController = TextEditingController(
      text: isEdit ? widget.user!['name'] : '',
    );
    _emailController = TextEditingController(
      text: isEdit ? widget.user!['email'] : '',
    );
    _passwordController = TextEditingController();

    if (isEdit) {
      _selectedRole = 'Dispatch Staff';
      _selectedCompany = widget.user!['company'] == 'Internal'
          ? 'GT LANTIN INTERNAL'
          : widget.user!['company'];
    }

    if (_selectedCompany != null &&
        !_companyOptions.contains(_selectedCompany)) {
      _companyOptions.add(_selectedCompany!);
    }

    _fetchCompanyDropdown();
  }

  Future<void> _fetchCompanyDropdown() async {
    try {
      final res = await http
          .get(Uri.parse('$backendUrl/companies'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          final fetched = (data['data'] as List)
              .map((e) => e['company_name'].toString())
              .toList();

          setState(() {
            if (fetched.isNotEmpty) {
              _companyOptions = fetched;
            }
            if (_selectedCompany != null &&
                !_companyOptions.contains(_selectedCompany)) {
              _companyOptions.add(_selectedCompany!);
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Dropdown company fetch failed: $e");
    }
  }

  InputDecoration _fieldStyle(
    BuildContext context, {
    required String label,
    required IconData icon,
    bool forceDisable = false,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool active = _isWritingUnlocked && !forceDisable;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        color: isDark ? Colors.grey.shade400 : const Color(0xFF475569),
        size: 20,
      ),
      filled: true,
      fillColor: active
          ? (isDark ? Colors.grey.shade800 : const Color(0xFFF8FAFC))
          : (isDark ? Colors.grey.shade900 : const Color(0xFFF1F5F9)),
      labelStyle: TextStyle(
        color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
    );
  }

  Future<void> _submitUserForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final bool isEditMode = widget.user != null;

    try {
      final http.Response response;
      if (isEditMode) {
        response = await http
            .put(
              Uri.parse('$backendUrl/auth/update-user/${widget.user!['id']}'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'full_name': _nameController.text.trim(),
                'email': _emailController.text.trim(),
                'role': _selectedRole,
                'company_name': _selectedCompany ?? 'GT LANTIN INTERNAL',
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (_passwordController.text.isNotEmpty) {
          final passResponse = await http
              .post(
                Uri.parse('$backendUrl/auth/update-password'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'user_id': widget.user!['id'],
                  'new_password': _passwordController.text,
                }),
              )
              .timeout(const Duration(seconds: 10));

          final passData = jsonDecode(passResponse.body);
          if (passResponse.statusCode != 200 || passData['success'] != true) {
            throw Exception(
              passData['message'] ?? "Failed to override password.",
            );
          }
        }
      } else {
        response = await http
            .post(
              Uri.parse('$backendUrl/auth/register-staff'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'email': _emailController.text.trim(),
                'password': _passwordController.text,
                'role': _selectedRole,
                'company_name': _selectedCompany ?? 'GT LANTIN INTERNAL',
                'full_name': _nameController.text.trim(),
              }),
            )
            .timeout(const Duration(seconds: 15));
      }

      final responseData = jsonDecode(response.body);

      if ((response.statusCode == 201 || response.statusCode == 200) &&
          responseData['success'] == true) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditMode
                  ? "Account profile synchronized!"
                  : "User registered successfully!",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        throw Exception(
          responseData['message'] ?? "Request operation rejected.",
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditMode = widget.user != null;
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: isMobile ? double.infinity : 520,
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEditMode ? 'System User Profile' : 'Register System User',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: isDark
                        ? Colors.grey.shade400
                        : const Color(0xFF64748B),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        validator: (val) =>
                            val == null || val.isEmpty ? "Required" : null,
                        decoration: _fieldStyle(
                          context,
                          label: 'Full Name',
                          icon: Icons.person,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        validator: (val) => val == null || !val.contains('@')
                            ? "Enter a valid email"
                            : null,
                        decoration: _fieldStyle(
                          context,
                          label: 'Email Address',
                          icon: Icons.email,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        decoration: _fieldStyle(
                          context,
                          label: isEditMode
                              ? 'Reset Password (Leave empty to keep current)'
                              : 'Secure Password',
                          icon: Icons.lock_reset,
                        ),
                        validator: (val) {
                          if (!isEditMode && (val == null || val.length < 6)) {
                            return "Minimum 6 characters required";
                          }
                          if (isEditMode &&
                              val != null &&
                              val.isNotEmpty &&
                              val.length < 6) {
                            return "Minimum 6 characters required";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        validator: (val) =>
                            val == null ? "Select a role" : null,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                        ),
                        decoration: _fieldStyle(
                          context,
                          label: 'Assign Role',
                          icon: Icons.admin_panel_settings,
                        ),
                        onChanged: !_isWritingUnlocked
                            ? null
                            : (value) => setState(() => _selectedRole = value),
                        dropdownColor: Theme.of(context).cardColor,
                        items: const ['Dispatch Staff']
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isEditMode)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                    ),
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
                      style: TextButton.styleFrom(
                        foregroundColor: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade700,
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    if (isEditMode && !_isWritingUnlocked)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF64748B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () =>
                            setState(() => _isWritingUnlocked = true),
                        child: const Text(
                          'Edit Details',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onPressed: _isLoading ? null : _submitUserForm,
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: EnterpriseLoadingIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isEditMode ? 'Save Changes' : 'Register User',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
