import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/subscription/presentation/subscription_screen.dart';
import 'package:flow_tasks/features/admin/presentation/admin_screen.dart';
import 'package:intl/intl.dart';

/// Settings screen with TickTick-style layout
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _selectedSection = 'account';

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final isAdmin = ref.watch(isAdminProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: isNarrow
          ? AppBar(
              backgroundColor: colors.surface,
              title: Text('Settings', style: TextStyle(color: colors.textPrimary)),
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              elevation: 0,
            )
          : null,
      body: isNarrow
          ? _buildNarrowLayout(colors, isAdmin)
          : _buildWideLayout(colors, isAdmin),
    );
  }

  Widget _buildWideLayout(FlowColorScheme colors, AsyncValue<bool> isAdmin) {
    return Row(
      children: [
        // Sidebar
        Container(
          width: 240,
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(right: BorderSide(color: colors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Menu items
              _SidebarItem(
                icon: Icons.person_outline,
                label: 'Account',
                isSelected: _selectedSection == 'account',
                onTap: () => setState(() => _selectedSection = 'account'),
              ),
              _SidebarItem(
                icon: Icons.workspace_premium_outlined,
                label: 'Premium',
                isSelected: _selectedSection == 'premium',
                onTap: () => setState(() => _selectedSection = 'premium'),
              ),
              _SidebarItem(
                icon: Icons.palette_outlined,
                label: 'Appearance',
                isSelected: _selectedSection == 'appearance',
                onTap: () => setState(() => _selectedSection = 'appearance'),
              ),
              // Admin section
              isAdmin.when(
                data: (admin) => admin
                    ? _SidebarItem(
                        icon: Icons.admin_panel_settings_outlined,
                        label: 'Admin',
                        isSelected: _selectedSection == 'admin',
                        onTap: () => setState(() => _selectedSection = 'admin'),
                      )
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const Spacer(),
              _SidebarItem(
                icon: Icons.info_outline,
                label: 'About',
                isSelected: _selectedSection == 'about',
                onTap: () => setState(() => _selectedSection = 'about'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
        // Content area
        Expanded(
          child: _buildContent(colors),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(FlowColorScheme colors, AsyncValue<bool> isAdmin) {
    // For narrow screens, show a simple list
    return ListView(
      children: [
        const SizedBox(height: 24),
        _AccountCard(),
        const SizedBox(height: 24),
        _buildMenuSection(colors, isAdmin),
      ],
    );
  }

  Widget _buildMenuSection(FlowColorScheme colors, AsyncValue<bool> isAdmin) {
    final themeMode = ref.watch(themeModeProvider);

    return Column(
      children: [
        _MenuTile(
          icon: Icons.workspace_premium_outlined,
          label: 'Premium',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
          ),
        ),
        _MenuTile(
          icon: Icons.palette_outlined,
          label: 'Appearance',
          subtitle: _getThemeLabel(themeMode),
          onTap: () => _showThemePicker(context, ref),
        ),
        isAdmin.when(
          data: (admin) => admin
              ? _MenuTile(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Admin Dashboard',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminScreen()),
                  ),
                )
              : const SizedBox.shrink(),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        _MenuTile(
          icon: Icons.info_outline,
          label: 'About',
          subtitle: 'Version 1.0.0',
          onTap: null,
        ),
      ],
    );
  }

  Widget _buildContent(FlowColorScheme colors) {
    switch (_selectedSection) {
      case 'account':
        return _AccountContent();
      case 'premium':
        return const SubscriptionScreen();
      case 'appearance':
        return _AppearanceContent();
      case 'admin':
        return const AdminScreen();
      case 'about':
        return _AboutContent();
      default:
        return _AccountContent();
    }
  }

  String _getThemeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  void _showThemePicker(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.brightness_auto),
              title: const Text('System'),
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.light_mode),
              title: const Text('Light'),
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode),
              title: const Text('Dark'),
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? colors.primary : colors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  const _MenuTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return ListTile(
      leading: Icon(icon, color: colors.textSecondary),
      title: Text(label, style: TextStyle(color: colors.textPrimary)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: colors.textTertiary))
          : null,
      trailing: onTap != null
          ? Icon(Icons.chevron_right, color: colors.textTertiary)
          : null,
      onTap: onTap,
    );
  }
}

class _AccountCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final authState = ref.watch(authStateProvider);
    final subscription = ref.watch(userSubscriptionProvider);
    final user = authState.user;

    return Column(
      children: [
        // Avatar with crown badge
        Stack(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: const Color(0xFFE91E63),
              child: Text(
                (user?.name ?? user?.email ?? 'U').substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            // Crown badge for premium users
            subscription.when(
              data: (sub) => sub.isPremium
                  ? Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300),
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.background, width: 2),
                        ),
                        child: const Icon(
                          Icons.workspace_premium,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Name
        Text(
          user?.name ?? 'User',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        // Email
        Text(
          user?.email ?? '',
          style: TextStyle(
            fontSize: 16,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        // Subscription status
        subscription.when(
          data: (sub) => Text(
            _getSubscriptionText(sub),
            style: TextStyle(
              fontSize: 14,
              color: colors.textTertiary,
            ),
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 32),
        // Sign out button
        SizedBox(
          width: 160,
          child: OutlinedButton(
            onPressed: () => _confirmLogout(context, ref),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              'Sign Out',
              style: TextStyle(color: colors.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Delete account link
        TextButton(
          onPressed: () => _showDeleteAccountDialog(context, ref),
          child: const Text(
            'Delete Account',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  String _getSubscriptionText(UserSubscription sub) {
    if (sub.isPremium) {
      final expiresText = sub.expiresAt != null
          ? 'Expires on ${DateFormat('d MMM yyyy').format(sub.expiresAt!)}'
          : '';
      return 'You are already a Premium user. $expiresText';
    } else if (sub.isLight) {
      final expiresText = sub.expiresAt != null
          ? 'Expires on ${DateFormat('d MMM yyyy').format(sub.expiresAt!)}'
          : '';
      return 'You are a Light user. $expiresText';
    }
    return 'Free plan';
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) async {
    final colors = context.flowColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Sign out', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authStateProvider.notifier).logout();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Delete Account', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement account deletion
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Account deletion is not yet available')),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _AccountContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final aiUsage = ref.watch(aiUsageProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            children: [
              _AccountCard(),
              const SizedBox(height: 40),
              // Today's usage - only Clean Title
              aiUsage.when(
                data: (stats) => stats != null
                    ? _UsageCard(stats: stats)
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  final AIUsageStats stats;

  const _UsageCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    // Only show Clean Title
    if (!stats.limits.containsKey(AIFeature.cleanTitle.key)) {
      return const SizedBox.shrink();
    }

    final limit = stats.limits[AIFeature.cleanTitle.key] ?? 0;
    final used = stats.usage[AIFeature.cleanTitle.key] ?? 0;
    final isUnlimited = limit == -1;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s Usage',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.auto_fix_high, size: 20, color: colors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Clean Title',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                isUnlimited ? '$used used' : '$used / $limit',
                style: TextStyle(
                  color: isUnlimited || used < limit
                      ? colors.textTertiary
                      : colors.error,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppearanceContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final themeMode = ref.watch(themeModeProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Appearance',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Theme',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _ThemeOption(
                icon: Icons.brightness_auto,
                label: 'System',
                isSelected: themeMode == ThemeMode.system,
                onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system),
              ),
              _ThemeOption(
                icon: Icons.light_mode,
                label: 'Light',
                isSelected: themeMode == ThemeMode.light,
                onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light),
              ),
              _ThemeOption(
                icon: Icons.dark_mode,
                label: 'Dark',
                isSelected: themeMode == ThemeMode.dark,
                onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: colors.primary) : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? colors.primary : colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check, color: colors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AboutContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Icon(
                Icons.task_alt,
                size: 64,
                color: colors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Flow Tasks',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Version 1.0.0',
                style: TextStyle(
                  fontSize: 16,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'A smart task manager with AI-powered features to boost your productivity.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
