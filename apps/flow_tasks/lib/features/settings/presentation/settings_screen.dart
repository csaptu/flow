import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/subscription/presentation/subscription_screen.dart';
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: isNarrow
          ? AppBar(
              backgroundColor: colors.surface,
              title: Text('Profile', style: TextStyle(color: colors.textPrimary)),
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              elevation: 0,
            )
          : null,
      body: isNarrow
          ? _buildNarrowLayout(colors)
          : _buildWideLayout(colors),
    );
  }

  Widget _buildWideLayout(FlowColorScheme colors) {
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
                      'Profile',
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
              _SidebarItem(
                icon: Icons.auto_fix_high_outlined,
                label: 'AI & Agentic',
                isSelected: _selectedSection == 'ai',
                onTap: () => setState(() => _selectedSection = 'ai'),
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

  Widget _buildNarrowLayout(FlowColorScheme colors) {
    // For narrow screens, show a simple list
    return ListView(
      children: [
        const SizedBox(height: 24),
        _AccountCard(),
        const SizedBox(height: 24),
        _buildMenuSection(colors),
      ],
    );
  }

  Widget _buildMenuSection(FlowColorScheme colors) {
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
        _MenuTile(
          icon: Icons.auto_fix_high_outlined,
          label: 'AI & Agentic Actions',
          subtitle: 'Configure AI features',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _AISettingsPage()),
          ),
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
      case 'ai':
        return _AISettingsContent();
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
        // Name with edit button
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user?.name ?? 'User',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 18, color: colors.textTertiary),
              onPressed: () => _showEditNameDialog(context, ref, user?.name ?? ''),
              tooltip: 'Edit name',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
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
      ],
    );
  }

  void _showEditNameDialog(BuildContext context, WidgetRef ref, String currentName) {
    final colors = context.flowColors;
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Edit Name', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter your name',
            hintStyle: TextStyle(color: colors.textTertiary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          style: TextStyle(color: colors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;

              Navigator.of(context).pop();

              try {
                await ref.read(authStateProvider.notifier).updateProfile(name: newName);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name updated')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update: $e')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: colors.primary),
            child: const Text('Save'),
          ),
        ],
      ),
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
    final userTimezone = ref.watch(userTimezoneProvider);

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
              const SizedBox(height: 32),
              // Timezone section
              Text(
                'Timezone',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Due dates and times will be displayed in your selected timezone.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: 16),
              _TimezoneSelector(
                currentTimezone: userTimezone,
                onTimezoneChanged: (newTimezone, refreshDates) async {
                  final changed = await ref.read(userTimezoneProvider.notifier).setTimezone(newTimezone);
                  if (changed && refreshDates && context.mounted) {
                    // Show snackbar confirming the change
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          refreshDates
                              ? 'Timezone updated. Due dates will be refreshed.'
                              : 'Timezone updated. Due dates kept as-is.',
                        ),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Timezone selector with change confirmation dialog
class _TimezoneSelector extends ConsumerStatefulWidget {
  final String? currentTimezone;
  final void Function(String? timezone, bool refreshDates) onTimezoneChanged;

  const _TimezoneSelector({
    required this.currentTimezone,
    required this.onTimezoneChanged,
  });

  @override
  ConsumerState<_TimezoneSelector> createState() => _TimezoneSelectorState();
}

class _TimezoneSelectorState extends ConsumerState<_TimezoneSelector> {
  String _getTimezoneLabel(String? timezone) {
    if (timezone == null) {
      final deviceTz = DateTime.now().timeZoneName;
      final offset = DateTime.now().timeZoneOffset;
      final offsetStr = '${offset.isNegative ? '-' : '+'}${offset.inHours.abs().toString().padLeft(2, '0')}:${(offset.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
      return 'Device Default ($deviceTz, $offsetStr)';
    }

    final option = commonTimezones.where((t) => t.id == timezone).firstOrNull;
    if (option != null) {
      return '${option.label} (${option.offset})';
    }
    return timezone;
  }

  Future<void> _showTimezonePicker() async {
    final colors = context.flowColors;
    final result = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Timezone',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: commonTimezones.length,
                itemBuilder: (context, index) {
                  final tz = commonTimezones[index];
                  final isSelected = (tz.id == 'device' && widget.currentTimezone == null) ||
                      (tz.id == widget.currentTimezone);

                  return ListTile(
                    leading: Icon(
                      Icons.access_time,
                      color: isSelected ? colors.primary : colors.textSecondary,
                    ),
                    title: Text(
                      tz.label,
                      style: TextStyle(
                        color: isSelected ? colors.primary : colors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      tz.offset,
                      style: TextStyle(color: colors.textTertiary),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check, color: colors.primary)
                        : null,
                    onTap: () {
                      final newValue = tz.id == 'device' ? null : tz.id;
                      Navigator.of(context).pop(newValue);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    // If user selected a new timezone (result is not the current value)
    if (result != widget.currentTimezone && mounted) {
      // Show confirmation dialog
      await _showTimezoneChangeDialog(result);
    }
  }

  Future<void> _showTimezoneChangeDialog(String? newTimezone) async {
    final colors = context.flowColors;
    final oldLabel = _getTimezoneLabel(widget.currentTimezone);
    final newLabel = _getTimezoneLabel(newTimezone);

    final result = await showDialog<bool?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Timezone Changed',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are changing your timezone from:',
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              oldLabel,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'To:',
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              newLabel,
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Would you like to adjust your existing due dates to the new timezone?',
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '(If you choose "No", your due dates will stay at the same clock time)',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null), // Cancel
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Keep dates
            child: Text('No, Keep Dates', style: TextStyle(color: colors.textPrimary)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true), // Refresh dates
            style: FilledButton.styleFrom(
              backgroundColor: colors.primary,
            ),
            child: const Text('Yes, Adjust Dates'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      widget.onTimezoneChanged(newTimezone, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return InkWell(
      onTap: _showTimezonePicker,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.public,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTimezoneLabel(widget.currentTimezone),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colors.textTertiary,
            ),
          ],
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

// =====================================================
// AI & Agentic Actions Settings
// =====================================================

/// AI Settings content for wide layout
class _AISettingsContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final aiPrefs = ref.watch(aiPreferencesProvider);
    final userTier = ref.watch(userTierProvider);
    final aiUsage = ref.watch(aiUsageProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI & Agentic Actions',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Configure how AI features behave. Auto runs automatically, Manual requires user action, Off disables.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // Free tier features
              _AIFeatureSection(
                title: 'Free Features',
                subtitle: 'Available to all users',
                features: [
                  AIFeature.cleanTitle,
                  AIFeature.cleanDescription,
                ],
                aiPrefs: aiPrefs,
                userTier: userTier,
              ),
              const SizedBox(height: 24),

              // Light tier features
              _AIFeatureSection(
                title: 'Light Plan Features',
                subtitle: 'Requires Light subscription',
                features: [
                  AIFeature.decompose,
                  AIFeature.entityExtraction,
                  AIFeature.duplicateCheck,
                  AIFeature.recurringDetection,
                ],
                aiPrefs: aiPrefs,
                userTier: userTier,
              ),

              const SizedBox(height: 32),

              // Usage stats
              aiUsage.when(
                data: (stats) => stats != null
                    ? _AIUsageSection(stats: stats)
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

/// AI Settings page for narrow layout
class _AISettingsPage extends ConsumerWidget {
  const _AISettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('AI & Agentic Actions', style: TextStyle(color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
      ),
      body: _AISettingsContent(),
    );
  }
}

/// Feature section with header
class _AIFeatureSection extends ConsumerWidget {
  final String title;
  final String subtitle;
  final List<AIFeature> features;
  final AIPreferences aiPrefs;
  final UserTier userTier;

  const _AIFeatureSection({
    required this.title,
    required this.subtitle,
    required this.features,
    required this.aiPrefs,
    required this.userTier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: features.asMap().entries.map((entry) {
              final index = entry.key;
              final feature = entry.value;
              final isLast = index == features.length - 1;
              return _AIFeatureRow(
                feature: feature,
                currentSetting: aiPrefs.getSetting(feature),
                isEnabled: _canAccessFeature(feature, userTier),
                isLast: isLast,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  bool _canAccessFeature(AIFeature feature, UserTier tier) {
    switch (feature.requiredTier) {
      case UserTier.free:
        return true;
      case UserTier.light:
        return tier == UserTier.light || tier == UserTier.premium;
      case UserTier.premium:
        return tier == UserTier.premium;
    }
  }
}

/// Individual feature row with dropdown
class _AIFeatureRow extends ConsumerWidget {
  final AIFeature feature;
  final AISetting currentSetting;
  final bool isEnabled;
  final bool isLast;

  const _AIFeatureRow({
    required this.feature,
    required this.currentSetting,
    required this.isEnabled,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      feature.displayName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isEnabled ? colors.textPrimary : colors.textTertiary,
                      ),
                    ),
                    if (!isEnabled) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: colors.textTertiary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  feature.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Dropdown for setting
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isEnabled ? colors.surfaceVariant : colors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AISetting>(
                value: currentSetting,
                isDense: true,
                style: TextStyle(
                  fontSize: 13,
                  color: isEnabled ? colors.textPrimary : colors.textTertiary,
                ),
                dropdownColor: colors.surface,
                items: AISetting.values.map((setting) {
                  return DropdownMenuItem<AISetting>(
                    value: setting,
                    child: Text(setting.label),
                  );
                }).toList(),
                onChanged: isEnabled
                    ? (newSetting) {
                        if (newSetting != null) {
                          ref
                              .read(aiPreferencesProvider.notifier)
                              .setSetting(feature, newSetting);
                        }
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI usage stats section
class _AIUsageSection extends StatelessWidget {
  final AIUsageStats stats;

  const _AIUsageSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today\'s Usage',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: stats.usage.entries.map((entry) {
              final featureKey = entry.key;
              final used = entry.value;
              final limit = stats.limits[featureKey] ?? 0;
              final isUnlimited = limit == -1;
              final feature = AIFeature.values.firstWhere(
                (f) => f.key == featureKey,
                orElse: () => AIFeature.cleanTitle,
              );

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.auto_fix_high, size: 16, color: colors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        feature.displayName,
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      isUnlimited ? '$used used' : '$used / $limit',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isUnlimited || used < limit
                            ? colors.textTertiary
                            : colors.error,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
