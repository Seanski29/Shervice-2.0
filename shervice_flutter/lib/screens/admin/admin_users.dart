import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import '../../constant.dart';
import '../../widgets/shared/universal_pagination.dart';

// ─── MAIN DASHBOARD COMPONENT ───
class AdminUsers extends StatefulWidget {
  const AdminUsers({super.key});

  @override
  State<AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsers> {
  // --- State Variables ---
  bool _isLoading = true;
  List<dynamic> _allUsers = [];
  List<dynamic> _filteredUsers = [];

  // Filtering, Searching & Sorting Configuration
  String _searchQuery = '';
  String _currentSort = 'Name (A to Z)';
  final List<String> _sortOptions = ['Name (A to Z)', 'Name (Z to A)', 'Role'];

  // Pagination Parameters
  int _currentPage = 0;
  final int _itemsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _fetchSystemUsers();
  }

  Future<void> _fetchSystemUsers() async {
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
      debugPrint("❌ Failed to fetch users: $e");
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
      _currentPage = 0;
      _isLoading = false;
    });
  }

  int get _totalPages => (_filteredUsers.length / _itemsPerPage).ceil();

  // Skeletonizer Mock Data Intercept
  List<dynamic> get _paginatedUsers {
    if (_isLoading) {
      return List.generate(
        5,
        (index) => {
          'id': index + 1,
          'name': 'Loading User Name Data',
          'status': 'Active',
          'company': 'Loading Company',
          'email': 'loading@example.com',
          'role': 'Staff',
          'permission': 'Standard',
        },
      );
    }
    if (_filteredUsers.isEmpty) return [];
    int start = _currentPage * _itemsPerPage;
    int end = min(start + _itemsPerPage, _filteredUsers.length);
    return _filteredUsers.sublist(start, end);
  }

  void _nextPage() =>
      _currentPage < _totalPages - 1 ? setState(() => _currentPage++) : null;
  void _prevPage() => _currentPage > 0 ? setState(() => _currentPage--) : null;

  void _confirmPurgeUser(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          'Confirm Deletion',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          'Are you sure you want to permanently revoke accesses and delete system account records for ${user['name']}?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                final res = await http
                    .delete(
                      Uri.parse('$backendUrl/auth/delete-user/${user['id']}'),
                    )
                    .timeout(const Duration(seconds: 10));

                if (res.statusCode == 200) {
                  _showSnackBar(
                    'User identity context completely deleted.',
                    const Color(0xFFF59E0B),
                  );
                } else {
                  _showSnackBar(
                    'Purge validation request rejected by server.',
                    const Color(0xFFEF4444),
                  );
                }
              } catch (e) {
                _showSnackBar(
                  'Network layer timing exception error.',
                  const Color(0xFFEF4444),
                );
              } finally {
                _fetchSystemUsers();
              }
            },
            child: const Text(
              'Delete permanently',
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

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 950;
    final double horizontalPadding = isMobile ? 12.0 : 24.0;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Widget actionControls = Skeleton.ignore(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: isMobile ? WrapAlignment.start : WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isMobile ? double.infinity : 280,
            ),
            child: SizedBox(
              height: 42,
              child: TextField(
                onChanged: (value) {
                  _searchQuery = value;
                  _applyFiltersAndSort();
                },
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search system accounts...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade300,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade300,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF3B82F6),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isMobile ? double.infinity : 160,
            ),
            child: SizedBox(
              height: 42,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border.all(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _currentSort,
                    dropdownColor: Theme.of(context).cardColor,
                    icon: const Icon(
                      Icons.sort,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    items: _sortOptions
                        .map(
                          (String value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        _currentSort = newValue;
                        _applyFiltersAndSort();
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 42,
            width: 42,
            child: OutlinedButton(
              onPressed: () {
                setState(() => _isLoading = true);
                _fetchSystemUsers();
              },
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: const BorderSide(color: Color(0xFF3B82F6), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Icon(
                Icons.refresh,
                color: Color(0xFF3B82F6),
                size: 20,
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              onPressed: () => _showUserModal(context),
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: const Text(
                'Register User',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );

    final Widget headerTitle = Skeleton.ignore(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'User Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage system users, roles, and access permissions.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Skeletonizer(
        enabled: _isLoading,
        child: RefreshIndicator(
          onRefresh: _fetchSystemUsers,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMobile) ...[
                  headerTitle,
                  const SizedBox(height: 16),
                  actionControls,
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: headerTitle),
                      const SizedBox(width: 16),
                      actionControls,
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Expanded(
                  child: !_isLoading && _filteredUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 64,
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No system users found.',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey.shade500
                                      : Colors.grey.shade600,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _paginatedUsers.length,
                          itemBuilder: (context, index) {
                            final user = _paginatedUsers[index];
                            final String status = user['status'] ?? 'Active';
                            final Color statusColor = (status == 'Active')
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                                boxShadow: [
                                  if (!isDark)
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.02,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _showUserModal(
                                    context,
                                    user: Map<String, dynamic>.from(user),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 4,
                                          height: 36,
                                          margin: const EdgeInsets.only(
                                            right: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      user['name'] ??
                                                          'System User',
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 1,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: statusColor
                                                          .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      status,
                                                      style: TextStyle(
                                                        color: statusColor,
                                                        fontSize: 8,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Wrap(
                                                spacing: 10,
                                                runSpacing: 2,
                                                children: [
                                                  _iconText(
                                                    Icons.business,
                                                    user['company'] ??
                                                        'Internal',
                                                    isDark,
                                                  ),
                                                  _iconText(
                                                    Icons.email_outlined,
                                                    user['email'] ?? 'No Email',
                                                    isDark,
                                                  ),
                                                  _iconText(
                                                    Icons
                                                        .admin_panel_settings_outlined,
                                                    user['role'] ?? 'Staff',
                                                    isDark,
                                                  ),
                                                  _iconText(
                                                    Icons
                                                        .verified_user_outlined,
                                                    user['permission'] ??
                                                        'Standard',
                                                    isDark,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 14,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (!_isLoading && _filteredUsers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: UniversalPagination(
                      currentPage: _currentPage,
                      totalPages: _totalPages,
                      totalItems: _filteredUsers.length,
                      itemsPerPage: _itemsPerPage,
                      itemName: 'users',
                      onNextPage: _currentPage < _totalPages - 1
                          ? _nextPage
                          : null,
                      onPrevPage: _currentPage > 0 ? _prevPage : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconText(IconData icon, String text, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// REGISTER USER DIALOG (NOW FULLY DYNAMIC COMPANIES)
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
      _selectedRole = widget.user!['role'];
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
            // Ensure selected company matches one of the options
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
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
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
              Uri.parse('$backendUrl/auth/register-staff-oic'),
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
          borderRadius: BorderRadius.circular(24),
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
                        initialValue: _selectedRole,
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
                        items: ['Dispatch Staff', 'Officer-in-Charge']
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      // ─── DYNAMIC COMPANY DROPDOWN ───
                      DropdownButtonFormField<String>(
                        value: _selectedCompany,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                        ),
                        decoration: _fieldStyle(
                          context,
                          label: 'Assign Company Account',
                          icon: Icons.business,
                        ),
                        onChanged: !_isWritingUnlocked
                            ? null
                            : (value) =>
                                  setState(() => _selectedCompany = value),
                        dropdownColor: Theme.of(context).cardColor,
                        items: _companyOptions
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
                            borderRadius: BorderRadius.circular(10),
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
                            borderRadius: BorderRadius.circular(10),
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
                                child: CircularProgressIndicator(
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
