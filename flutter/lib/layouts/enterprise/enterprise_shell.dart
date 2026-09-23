import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'enterprise_theme.dart';
import '../../interface/theme_manager.dart';
import '../../utilities/network_status_monitor.dart';

class EnterpriseNavigationItem {
  const EnterpriseNavigationItem({
    required this.label,
    required this.icon,
    required this.section,
    required this.screen,
    this.keywords = const [],
  });

  final String label;
  final IconData icon;
  final String section;
  final Widget screen;
  final List<String> keywords;
}

class EnterpriseShell extends StatefulWidget {
  const EnterpriseShell({
    super.key,
    required this.role,
    required this.userName,
    required this.navigationItems,
    required this.notification,
    required this.profile,
    required this.onLogout,
  });

  final String role;
  final String userName;
  final List<EnterpriseNavigationItem> navigationItems;
  final Widget notification;
  final Widget profile;
  final Future<void> Function() onLogout;

  @override
  State<EnterpriseShell> createState() => _EnterpriseShellState();
}

class _EnterpriseShellState extends State<EnterpriseShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;
  late final Map<String, bool> _sectionExpanded;

  EnterpriseNavigationItem get _selected =>
      widget.navigationItems[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _sectionExpanded = {
      for (final item in widget.navigationItems) item.section: true,
    };
    NetworkStatusMonitor.start();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _showCommandPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _showCommandPalette,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 960;
            return Scaffold(
              key: _scaffoldKey,
              drawer: compact
                  ? Drawer(
                      width: 280,
                      shape: const RoundedRectangleBorder(),
                      child: _buildSidebar(forceExpanded: true),
                    )
                  : null,
              endDrawer: _buildContextDrawer(),
              body: SafeArea(
                child: Row(
                  children: [
                    if (!compact) _buildSidebar(),
                    Expanded(
                      child: Column(
                        children: [
                          _buildTopBar(compact: compact),
                          const _NetworkStatusBanner(),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // DELETED the Align block that held the Page Title. 
                                // Titles are now managed directly by individual screens to save vertical space.
                                Expanded(
                                  child: KeyedSubtree(
                                    key: ValueKey(_selected.label),
                                    child: _selected.screen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── BRANDING HEADER INSIDE THE SIDEBAR ───
  Widget _buildSidebarHeader(bool expanded) {
    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: expanded
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: 260, // Anchored width prevents CLS jumping
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    // 1. Hamburger Toggle
                    IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onPressed: () =>
                          setState(() => _sidebarExpanded = !_sidebarExpanded),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    // 2. Circular Truck Logo
                    Container(
                      width: 41,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/logo.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.directions_car,
                          color: Colors.blue,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 3. Shervice Text Logo
                    Expanded(
                      child: Image.asset(
                        'assets/shervice - white.jpg',
                        height: 50,
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Text(
                          'SHERVICE',
                          style: GoogleFonts.montserrat(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. Hamburger Toggle ONLY (Collapsed)
                IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () =>
                      setState(() => _sidebarExpanded = !_sidebarExpanded),
                ),
              ],
            ),
    );
  }

  Widget _buildSidebar({bool forceExpanded = false}) {
    final expanded = forceExpanded || _sidebarExpanded;
    const sidebarBackground = EnterpriseColors.sidebar;
    final width = expanded ? 260.0 : 76.0;
    final sections = <String>[];
    
    for (final item in widget.navigationItems) {
      if (!sections.contains(item.section)) sections.add(item.section);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: width,
      color: sidebarBackground,
      child: Column(
        children: [
          _buildSidebarHeader(expanded),
          Expanded(
            child: ListView(
              physics: const ClampingScrollPhysics(), 
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              children: [
                for (final section in sections)
                  if (section != 'Hidden') 
                    _buildNavigationSection(section, expanded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationSection(String section, bool expanded) {
    final items = widget.navigationItems
        .asMap()
        .entries
        .where((entry) => entry.value.section == section)
        .toList();
    final sectionOpen = _sectionExpanded[section] ?? true;

    if (!expanded) {
      return Column(
        children: [
          for (final entry in items) _buildNavigationItem(entry.key, false),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (section != 'Workspace')
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text(
              switch (section) {
                'Operations' => 'OPERATIONS',
                'Organization' => 'BUSINESS',
                'Workforce' => 'DRIVERS',
                _ => section.toUpperCase(),
              },
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        if (sectionOpen)
          for (final entry in items) _buildNavigationItem(entry.key, true),
      ],
    );
  }

  Widget _buildNavigationItem(int index, bool expanded) {
    final item = widget.navigationItems[index];
    final active = _selectedIndex == index;
    return Tooltip(
      message: expanded ? '' : item.label,
      child: InkWell(
        onTap: () {
          setState(() => _selectedIndex = index);
          _scaffoldKey.currentState?.closeDrawer();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 16 : 12,
            vertical: 10, 
          ),
          decoration: BoxDecoration(
            color: active ? Colors.blue.shade600 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: 18,
                color: active ? Colors.white : const Color(0xFFD0D5DD),
              ),
              if (expanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? Colors.white : const Color(0xFFD0D5DD),
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── TOP NAVIGATION CLEARED OF LOGOS ───
  Widget _buildTopBar({required bool compact}) {
    final theme = Theme.of(context);
    final topBarColor = theme.brightness == Brightness.dark
        ? EnterpriseColors.darkSurface
        : EnterpriseColors.topNavigation;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: topBarColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          if (compact) ...[
            IconButton(
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Open navigation',
              icon: const Icon(Icons.menu),
            ),
            const SizedBox(width: 16),
          ],
          const Spacer(),
          IconButton(
            onPressed: _showCommandPalette,
            tooltip: 'Search views and actions',
            icon: Icon(
              Icons.search,
              size: 23,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          widget.notification,
          const SizedBox(width: 6),
          _buildProfileMenu(),
        ],
      ),
    );
  }

  Widget _buildProfileMenu() {
    final displayName = widget.userName.trim().isEmpty
        ? widget.role
        : widget.userName.trim();
    final initial = displayName.substring(0, 1).toUpperCase();
    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      menuChildren: [
        SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: EnterpriseColors.main,
                  foregroundColor: Colors.white,
                  child: Text(initial),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, overflow: TextOverflow.ellipsis),
                      Text(
                        widget.role,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.dark_mode_outlined),
          trailingIcon: ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeManager.themeNotifier,
            builder: (context, mode, _) => Switch(
              value: mode == ThemeMode.dark,
              onChanged: ThemeManager.setDarkMode,
            ),
          ),
          onPressed: ThemeManager.toggleTheme,
          child: const Text('Dark mode'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined),
          onPressed: _openSettings,
          child: const Text('Settings'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout_outlined),
          onPressed: _confirmLogout,
          child: const Text('Log out'),
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: 'Open profile menu',
        child: IconButton(
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: CircleAvatar(
            radius: 16,
            backgroundColor: EnterpriseColors.main,
            foregroundColor: Colors.white,
            child: Text(initial),
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    final settingsIndex = widget.navigationItems.indexWhere(
      (item) => item.label.toLowerCase() == 'settings',
    );

    if (settingsIndex >= 0) {
      setState(() => _selectedIndex = settingsIndex);
      _scaffoldKey.currentState?.closeDrawer();
    } else {
      debugPrint('Settings route not found in navigationItems');
    }
  }

  Widget _buildContextDrawer() {
    final theme = Theme.of(context);
    return Drawer(
      width: 340,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'View details',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close details',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ContextRow(label: 'Current view', value: _selected.label),
                  _ContextRow(label: 'Section', value: _selected.section),
                  _ContextRow(label: 'Owner', value: widget.userName),
                  _ContextRow(label: 'Access level', value: widget.role),
                  const SizedBox(height: 16),
                  Text(
                    'Keyboard shortcuts',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const _ContextRow(
                    label: 'Command palette',
                    value: 'Ctrl + K',
                  ),
                  const _ContextRow(label: 'Next control', value: 'Tab'),
                  const _ContextRow(
                    label: 'Previous control',
                    value: 'Shift + Tab',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCommandPalette() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => _CommandPalette(
        items: widget.navigationItems,
        currentIndex: _selectedIndex,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedIndex = selected);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out of Shervice?'),
        content: const Text(
          'Your saved account preferences will remain available on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onLogout();
  }
}

class _NetworkStatusBanner extends StatelessWidget {
  const _NetworkStatusBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NetworkQuality>(
      valueListenable: NetworkStatusMonitor.status,
      builder: (context, status, child) {
        if (status == NetworkQuality.online) return const SizedBox.shrink();
        final offline = status == NetworkQuality.offline;
        final color = offline
            ? EnterpriseColors.danger
            : EnterpriseColors.warning;
        return Semantics(
          liveRegion: true,
          child: Container(
            width: double.infinity,
            color: color,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Row(
              children: [
                Icon(
                  offline ? Icons.cloud_off_outlined : Icons.network_check,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    offline
                        ? 'No connection - changes cannot be synchronized.'
                        : 'Weak connection - updates may take longer than expected.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.items, required this.currentIndex});

  final List<EnterpriseNavigationItem> items;
  final int currentIndex;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = widget.items.asMap().entries.where((entry) {
      final haystack = <String>[
        entry.value.label,
        entry.value.section,
        ...entry.value.keywords,
      ].join(' ').toLowerCase();
      return haystack.contains(_query.toLowerCase());
    }).toList();

    return Dialog(
      alignment: const Alignment(0, -0.45),
      child: SizedBox(
        width: 620,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search views and actions',
                  helperText: 'Press Enter to open the first result',
                ),
                onSubmitted: (_) {
                  if (matches.isNotEmpty) {
                    Navigator.pop(context, matches.first.key);
                  }
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _PaletteHeader(
                    label: _query.isEmpty ? 'Recent routes' : 'Results',
                  ),
                  for (final entry in matches)
                    ListTile(
                      dense: true,
                      selected: entry.key == widget.currentIndex,
                      leading: Icon(entry.value.icon, size: 19),
                      title: Text(entry.value.label),
                      subtitle: Text(entry.value.section),
                      trailing: const Icon(Icons.keyboard_return, size: 16),
                      onTap: () => Navigator.pop(context, entry.key),
                    ),
                  const _PaletteHeader(label: 'Actions'),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.refresh, size: 19),
                    title: const Text('Refresh current view'),
                    subtitle: const Text('Reload visible operational data'),
                    onTap: () => Navigator.pop(context, widget.currentIndex),
                  ),
                  const _PaletteHeader(label: 'Settings'),
                  for (final entry in widget.items.asMap().entries.where(
                    (entry) => entry.value.label == 'Settings',
                  ))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.settings_outlined, size: 19),
                      title: const Text('Open Settings'),
                      onTap: () => Navigator.pop(context, entry.key),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: const Row(
                children: [
                  Text('Arrow keys Navigate', style: TextStyle(fontSize: 11)),
                  SizedBox(width: 16),
                  Text('Enter Open', style: TextStyle(fontSize: 11)),
                  Spacer(),
                  Text('Esc Close', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteHeader extends StatelessWidget {
  const _PaletteHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}