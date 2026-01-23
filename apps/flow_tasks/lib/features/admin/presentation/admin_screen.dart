import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_api/flow_api.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/admin/presentation/widgets/user_ai_profile_dialog.dart';
import 'package:intl/intl.dart';

/// Admin section type
enum AdminSection { users, orders, aiServices }

/// Admin dashboard screen - Bear-style with collapsible sections
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  String _tierFilter = 'all';
  bool _usersExpanded = true;
  bool _ordersExpanded = true;
  bool _aiServicesExpanded = true;
  int _usersPage = 1;
  int _ordersPage = 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(
          'Admin',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Tier filter bar (shared for both users and orders)
          _TierFilterBar(
            selectedTier: _tierFilter,
            onTierChanged: (tier) => setState(() {
              _tierFilter = tier;
              _usersPage = 1;
              _ordersPage = 1;
            }),
          ),

          // Content
          Expanded(
            child: isNarrow
                ? _buildNarrowLayout(colors)
                : _buildWideLayout(colors),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(FlowColorScheme colors) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Users and Orders side by side
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Users section
                Expanded(
                  child: _buildSection(
                    colors: colors,
                    title: 'Users',
                    icon: Icons.people_outline,
                    isExpanded: _usersExpanded,
                    onToggle: () => setState(() => _usersExpanded = !_usersExpanded),
                    content: _UsersContent(
                      tierFilter: _tierFilter,
                      page: _usersPage,
                      onPageChanged: (page) => setState(() => _usersPage = page),
                      onEditUser: (user) => _showEditUserDialog(context, ref, user),
                      onShowAIProfile: (user) => _showAIProfileDialog(context, user),
                    ),
                  ),
                ),
                // Divider
                Container(
                  width: 1,
                  color: colors.divider,
                ),
                // Orders section
                Expanded(
                  child: _buildSection(
                    colors: colors,
                    title: 'Orders',
                    icon: Icons.receipt_long_outlined,
                    isExpanded: _ordersExpanded,
                    onToggle: () => setState(() => _ordersExpanded = !_ordersExpanded),
                    content: _OrdersContent(
                      tierFilter: _tierFilter,
                      page: _ordersPage,
                      onPageChanged: (page) => setState(() => _ordersPage = page),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // AI Services section (full width below)
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
            ),
            child: _buildSection(
              colors: colors,
              title: 'AI Services',
              icon: Icons.psychology_outlined,
              isExpanded: _aiServicesExpanded,
              onToggle: () => setState(() => _aiServicesExpanded = !_aiServicesExpanded),
              content: _AIServicesContent(
                onEditConfig: (config) => _showEditAIConfigDialog(context, ref, config),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(FlowColorScheme colors) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Users section
          _buildSection(
            colors: colors,
            title: 'Users',
            icon: Icons.people_outline,
            isExpanded: _usersExpanded,
            onToggle: () => setState(() => _usersExpanded = !_usersExpanded),
            content: _UsersContent(
              tierFilter: _tierFilter,
              page: _usersPage,
              onPageChanged: (page) => setState(() => _usersPage = page),
              onEditUser: (user) => _showEditUserDialog(context, ref, user),
              onShowAIProfile: (user) => _showAIProfileDialog(context, user),
            ),
          ),
          // Orders section
          _buildSection(
            colors: colors,
            title: 'Orders',
            icon: Icons.receipt_long_outlined,
            isExpanded: _ordersExpanded,
            onToggle: () => setState(() => _ordersExpanded = !_ordersExpanded),
            content: _OrdersContent(
              tierFilter: _tierFilter,
              page: _ordersPage,
              onPageChanged: (page) => setState(() => _ordersPage = page),
            ),
          ),
          // AI Services section
          _buildSection(
            colors: colors,
            title: 'AI Services',
            icon: Icons.psychology_outlined,
            isExpanded: _aiServicesExpanded,
            onToggle: () => setState(() => _aiServicesExpanded = !_aiServicesExpanded),
            content: _AIServicesContent(
              onEditConfig: (config) => _showEditAIConfigDialog(context, ref, config),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required FlowColorScheme colors,
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget content,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header (like Bear list headers)
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                bottom: BorderSide(color: colors.divider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 20,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 18, color: colors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Section content
        if (isExpanded)
          content,
      ],
    );
  }

  void _showEditUserDialog(BuildContext context, WidgetRef ref, AdminUser user) {
    showDialog(
      context: context,
      builder: (context) => _EditUserDialog(user: user),
    ).then((updated) {
      if (updated == true) {
        ref.invalidate(adminUsersProvider);
      }
    });
  }

  void _showEditAIConfigDialog(BuildContext context, WidgetRef ref, AIPromptConfig config) {
    showDialog(
      context: context,
      builder: (context) => _EditAIConfigDialog(config: config),
    ).then((updated) {
      if (updated == true) {
        ref.invalidate(aiConfigsProvider);
      }
    });
  }

  void _showAIProfileDialog(BuildContext context, AdminUser user) {
    showDialog(
      context: context,
      builder: (context) => UserAIProfileDialog(
        userId: user.id,
        userName: user.name ?? '',
        userEmail: user.email,
      ),
    );
  }
}

/// Tier filter bar (shared for both users and orders)
class _TierFilterBar extends StatelessWidget {
  final String selectedTier;
  final ValueChanged<String> onTierChanged;

  const _TierFilterBar({
    required this.selectedTier,
    required this.onTierChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            'Filter:',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          _FilterChip(
            label: 'All',
            isSelected: selectedTier == 'all',
            onTap: () => onTierChanged('all'),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Free',
            isSelected: selectedTier == 'free',
            onTap: () => onTierChanged('free'),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Light',
            isSelected: selectedTier == 'light',
            onTap: () => onTierChanged('light'),
            color: Colors.blue,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Premium',
            isSelected: selectedTier == 'premium',
            onTap: () => onTierChanged('premium'),
            color: Colors.purple,
          ),
        ],
      ),
    );
  }
}

/// Users content section
class _UsersContent extends ConsumerWidget {
  final String tierFilter;
  final int page;
  final ValueChanged<int> onPageChanged;
  final Function(AdminUser) onEditUser;
  final Function(AdminUser) onShowAIProfile;

  const _UsersContent({
    required this.tierFilter,
    required this.page,
    required this.onPageChanged,
    required this.onEditUser,
    required this.onShowAIProfile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final usersAsync = ref.watch(adminUsersProvider((
      tier: tierFilter == 'all' ? null : tierFilter,
      page: page,
    )));

    return usersAsync.when(
      data: (response) => _buildUsersList(context, colors, response),
      loading: () => Container(
        height: 200,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      ),
      error: (err, _) => _buildErrorState(colors, 'users', err.toString()),
    );
  }

  Widget _buildUsersList(
    BuildContext context,
    FlowColorScheme colors,
    PaginatedResponse<AdminUser> response,
  ) {
    if (response.items.isEmpty) {
      return _buildEmptyState(colors, 'No users found');
    }

    final totalPages = response.meta?.totalPages ?? 1;

    return Column(
      children: [
        // User items (Bear-style list)
        ...response.items.map((user) => _UserItem(
          user: user,
          onTap: () => onEditUser(user),
          onShowAIProfile: () => onShowAIProfile(user),
        )),

        // Pagination
        if (totalPages > 1)
          _Pagination(
            page: page,
            totalPages: totalPages,
            onPageChanged: onPageChanged,
          ),
      ],
    );
  }

  Widget _buildEmptyState(FlowColorScheme colors, String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 48, color: colors.textTertiary),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: colors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildErrorState(FlowColorScheme colors, String type, String error) {
    // Show empty state for common "no data" errors
    if (error.contains('null') || error.contains('empty') || error.contains('404')) {
      return _buildEmptyState(colors, 'No $type yet');
    }
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 40, color: colors.error),
          const SizedBox(height: 12),
          Text(
            'Failed to load $type',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// User item (Bear-style)
class _UserItem extends StatelessWidget {
  final AdminUser user;
  final VoidCallback onTap;
  final VoidCallback onShowAIProfile;

  const _UserItem({
    required this.user,
    required this.onTap,
    required this.onShowAIProfile,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.divider.withValues(alpha: 0.5), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 16,
              backgroundColor: _getTierColor(user.tier).withValues(alpha: 0.2),
              child: Text(
                (user.name ?? user.email).substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  color: _getTierColor(user.tier),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.name ?? 'No name',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _TierBadge(tier: user.tier),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // AI Profile button
            IconButton(
              onPressed: onShowAIProfile,
              icon: Icon(Icons.psychology_outlined, size: 18, color: colors.primary),
              tooltip: 'AI Profile',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),

            // Task count
            Text(
              '${user.taskCount}',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
            const SizedBox(width: 4),
            Icon(Icons.task_alt, size: 14, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }

  Color _getTierColor(String tier) {
    switch (tier) {
      case 'premium':
        return Colors.purple;
      case 'light':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

/// Orders content section
class _OrdersContent extends ConsumerWidget {
  final String tierFilter;
  final int page;
  final ValueChanged<int> onPageChanged;

  const _OrdersContent({
    required this.tierFilter,
    required this.page,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final ordersAsync = ref.watch(adminOrdersProvider((
      status: null,
      provider: null,
      tier: tierFilter == 'all' ? null : tierFilter,
      page: page,
    )));

    return ordersAsync.when(
      data: (response) => _buildOrdersList(context, colors, response),
      loading: () => Container(
        height: 200,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      ),
      error: (err, _) => _buildErrorState(colors, 'orders', err.toString()),
    );
  }

  Widget _buildOrdersList(
    BuildContext context,
    FlowColorScheme colors,
    PaginatedResponse<Order> response,
  ) {
    if (response.items.isEmpty) {
      return _buildEmptyState(colors, 'No orders found');
    }

    final totalPages = response.meta?.totalPages ?? 1;

    return Column(
      children: [
        // Order items (Bear-style list)
        ...response.items.map((order) => _OrderItem(order: order)),

        // Pagination
        if (totalPages > 1)
          _Pagination(
            page: page,
            totalPages: totalPages,
            onPageChanged: onPageChanged,
          ),
      ],
    );
  }

  Widget _buildEmptyState(FlowColorScheme colors, String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: colors.textTertiary),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: colors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildErrorState(FlowColorScheme colors, String type, String error) {
    // Show empty state for common "no data" errors
    if (error.contains('null') || error.contains('empty') || error.contains('404')) {
      return _buildEmptyState(colors, 'No $type yet');
    }
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 40, color: colors.error),
          const SizedBox(height: 12),
          Text(
            'Failed to load $type',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Order item (Bear-style)
class _OrderItem extends StatelessWidget {
  final Order order;

  const _OrderItem({required this.order});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final dateFormat = DateFormat('MMM d, HH:mm');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.divider.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Status icon
          _StatusIcon(status: order.status),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.userEmail ?? order.userId.substring(0, 8),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '\$${order.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.planName ?? order.planId,
                        style: TextStyle(color: colors.textTertiary, fontSize: 12),
                      ),
                    ),
                    Text(
                      dateFormat.format(order.createdAt),
                      style: TextStyle(color: colors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Status icon for orders
class _StatusIcon extends StatelessWidget {
  final String status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (status) {
      case 'completed':
        color = Colors.green;
        icon = Icons.check_circle_outline;
        break;
      case 'pending':
        color = Colors.orange;
        icon = Icons.schedule;
        break;
      case 'failed':
        color = Colors.red;
        icon = Icons.error_outline;
        break;
      case 'refunded':
        color = Colors.blue;
        icon = Icons.replay;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
    }

    return Icon(icon, size: 20, color: color);
  }
}

/// Pagination controls
class _Pagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
            icon: Icon(Icons.chevron_left, color: colors.textSecondary),
            iconSize: 20,
          ),
          Text(
            '$page / $totalPages',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          IconButton(
            onPressed: page < totalPages ? () => onPageChanged(page + 1) : null,
            icon: Icon(Icons.chevron_right, color: colors.textSecondary),
            iconSize: 20,
          ),
        ],
      ),
    );
  }
}

/// Filter chip
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final chipColor = color ?? colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withValues(alpha: 0.15) : colors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? chipColor : colors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? chipColor : colors.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Tier badge
class _TierBadge extends StatelessWidget {
  final String tier;

  const _TierBadge({required this.tier});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (tier) {
      case 'premium':
        color = Colors.purple;
        label = 'Pro';
        break;
      case 'light':
        color = Colors.blue;
        label = 'Light';
        break;
      default:
        color = Colors.grey;
        label = 'Free';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Edit user dialog
class _EditUserDialog extends ConsumerStatefulWidget {
  final AdminUser user;

  const _EditUserDialog({required this.user});

  @override
  ConsumerState<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<_EditUserDialog> {
  late String _selectedTier;
  String? _selectedPlanId;
  DateTime? _startsAt;
  DateTime? _expiresAt;
  bool _isLoading = false;
  String? _error;
  String _billingPeriod = 'monthly'; // 'monthly' or 'yearly'

  @override
  void initState() {
    super.initState();
    _selectedTier = widget.user.tier;
    _selectedPlanId = widget.user.planId;
    _startsAt = widget.user.subscribedAt ?? DateTime.now();
    _expiresAt = widget.user.expiresAt;

    // Infer billing period from existing dates
    if (_startsAt != null && _expiresAt != null) {
      final diff = _expiresAt!.difference(_startsAt!).inDays;
      _billingPeriod = diff > 60 ? 'yearly' : 'monthly';
    }
  }

  void _updateExpiryFromStart() {
    if (_startsAt == null || _selectedPlanId == null) return;
    setState(() {
      if (_billingPeriod == 'yearly') {
        _expiresAt = DateTime(_startsAt!.year + 1, _startsAt!.month, _startsAt!.day);
      } else {
        _expiresAt = DateTime(_startsAt!.year, _startsAt!.month + 1, _startsAt!.day);
      }
    });
  }

  void _updateStartFromExpiry() {
    if (_expiresAt == null || _selectedPlanId == null) return;
    setState(() {
      if (_billingPeriod == 'yearly') {
        _startsAt = DateTime(_expiresAt!.year - 1, _expiresAt!.month, _expiresAt!.day);
      } else {
        _startsAt = DateTime(_expiresAt!.year, _expiresAt!.month - 1, _expiresAt!.day);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final plans = ref.watch(subscriptionPlansProvider);

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Edit Subscription',
        style: TextStyle(color: colors.textPrimary, fontSize: 18),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  child: Text(
                    (widget.user.name ?? widget.user.email).substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.name ?? 'No name',
                        style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        widget.user.email,
                        style: TextStyle(color: colors.textTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Error message
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
              ),
              const SizedBox(height: 12),
            ],

            // Plan selection
            Text(
              'Plan',
              style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            plans.when(
              data: (planList) => Container(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedPlanId,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    hint: const Text('Select plan'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Free (no plan)'),
                      ),
                      ...planList.where((p) => !p.isFree).map((plan) => DropdownMenuItem(
                        value: plan.id,
                        child: Text('${plan.name} - ${plan.formattedPrice}'),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedPlanId = value;
                        if (value == null) {
                          _selectedTier = 'free';
                          _startsAt = null;
                          _expiresAt = null;
                        } else {
                          final plan = planList.firstWhere((p) => p.id == value);
                          _selectedTier = plan.tier;
                          // Auto-set dates when plan is selected
                          _startsAt ??= DateTime.now();
                          _updateExpiryFromStart();
                        }
                      });
                    },
                  ),
                ),
              ),
              loading: () => const SizedBox(height: 48, child: Center(child: CircularProgressIndicator())),
              error: (_, __) => Text('Failed to load plans', style: TextStyle(color: colors.error)),
            ),

            // Billing period selector
            if (_selectedPlanId != null) ...[
              const SizedBox(height: 16),
              Text(
                'Billing Period',
                style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() => _billingPeriod = 'monthly');
                        _updateExpiryFromStart();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _billingPeriod == 'monthly'
                              ? colors.primary.withValues(alpha: 0.1)
                              : colors.background,
                          border: Border.all(
                            color: _billingPeriod == 'monthly' ? colors.primary : colors.border,
                          ),
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                        ),
                        child: Center(
                          child: Text(
                            'Monthly',
                            style: TextStyle(
                              color: _billingPeriod == 'monthly' ? colors.primary : colors.textSecondary,
                              fontWeight: _billingPeriod == 'monthly' ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() => _billingPeriod = 'yearly');
                        _updateExpiryFromStart();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _billingPeriod == 'yearly'
                              ? colors.primary.withValues(alpha: 0.1)
                              : colors.background,
                          border: Border.all(
                            color: _billingPeriod == 'yearly' ? colors.primary : colors.border,
                          ),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                        ),
                        child: Center(
                          child: Text(
                            'Yearly',
                            style: TextStyle(
                              color: _billingPeriod == 'yearly' ? colors.primary : colors.textSecondary,
                              fontWeight: _billingPeriod == 'yearly' ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Start date
              const SizedBox(height: 16),
              Text(
                'Starts',
                style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _selectStartDate,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.play_arrow, size: 16, color: colors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _startsAt != null
                              ? DateFormat('MMM d, yyyy').format(_startsAt!)
                              : 'Today',
                          style: TextStyle(color: colors.textPrimary, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Expiration date
              const SizedBox(height: 16),
              Text(
                'Expires',
                style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _selectExpirationDate,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: colors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _expiresAt != null
                              ? DateFormat('MMM d, yyyy').format(_expiresAt!)
                              : 'No expiration',
                          style: TextStyle(color: colors.textPrimary, fontSize: 14),
                        ),
                      ),
                      if (_expiresAt != null)
                        GestureDetector(
                          onTap: () => setState(() => _expiresAt = null),
                          child: Icon(Icons.clear, size: 16, color: colors.textTertiary),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _saveChanges,
          style: FilledButton.styleFrom(backgroundColor: colors.primary),
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _selectStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _startsAt = date);
      _updateExpiryFromStart(); // Auto-update expiry
    }
  }

  Future<void> _selectExpirationDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date != null) {
      setState(() => _expiresAt = date);
      _updateStartFromExpiry(); // Auto-update start
    }
  }

  Future<void> _saveChanges() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tasksService = ref.read(tasksServiceProvider);
      await tasksService.updateUserSubscription(
        widget.user.id,
        tier: _selectedTier,
        planId: _selectedPlanId,
        startsAt: _startsAt,
        expiresAt: _expiresAt,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

// =====================================================
// AI Services Section
// =====================================================

/// Service definition with its configs and implementation status
class _AIService {
  final String name;
  final String description;
  final IconData icon;
  final bool isImplemented;
  final List<String> configKeys;

  const _AIService({
    required this.name,
    required this.description,
    required this.icon,
    required this.isImplemented,
    required this.configKeys,
  });
}

/// All AI services with their configs
const List<_AIService> _aiServices = [
  _AIService(
    name: 'Context Building',
    description: 'System prompt and safety guardrails for all AI',
    icon: Icons.psychology_outlined,
    isImplemented: true,
    configKeys: ['system_first_context'],
  ),
  _AIService(
    name: 'Decompose',
    description: 'Break down tasks into subtasks',
    icon: Icons.account_tree_outlined,
    isImplemented: true,
    configKeys: ['decompose_rules', 'decompose_step_count'],
  ),
  _AIService(
    name: 'Clean',
    description: 'Clean up task titles and descriptions',
    icon: Icons.auto_fix_high_outlined,
    isImplemented: true,
    configKeys: ['clean_title_instruction', 'summary_instruction'],
  ),
  _AIService(
    name: 'Rate',
    description: 'Rate task complexity (1-10)',
    icon: Icons.speed_outlined,
    isImplemented: true,
    configKeys: ['complexity_instruction'],
  ),
  _AIService(
    name: 'Extract',
    description: 'Extract entities (people, places, etc.)',
    icon: Icons.person_search_outlined,
    isImplemented: true,
    configKeys: ['entities_instruction'],
  ),
  _AIService(
    name: 'Duplicates',
    description: 'Detect similar or duplicate tasks',
    icon: Icons.content_copy_outlined,
    isImplemented: true,
    configKeys: ['duplicate_check_instruction'],
  ),
  _AIService(
    name: 'Remind',
    description: 'Suggest reminder times',
    icon: Icons.notifications_outlined,
    isImplemented: true,
    configKeys: ['reminder_instruction'],
  ),
  _AIService(
    name: 'Email',
    description: 'Draft emails from task content',
    icon: Icons.email_outlined,
    isImplemented: true,
    configKeys: [], // No configurable prompts yet
  ),
  _AIService(
    name: 'Invite',
    description: 'Draft calendar invites from task content',
    icon: Icons.event_outlined,
    isImplemented: true,
    configKeys: [], // No configurable prompts yet
  ),
  _AIService(
    name: 'Task Parsing',
    description: 'Parse due dates, recurrence, and categories',
    icon: Icons.text_fields_outlined,
    isImplemented: false,
    configKeys: ['due_date_instruction', 'recurrence_instruction', 'suggested_group_instruction'],
  ),
];

/// AI Services content section
class _AIServicesContent extends ConsumerStatefulWidget {
  final Function(AIPromptConfig) onEditConfig;

  const _AIServicesContent({
    required this.onEditConfig,
  });

  @override
  ConsumerState<_AIServicesContent> createState() => _AIServicesContentState();
}

class _AIServicesContentState extends ConsumerState<_AIServicesContent> {
  bool _showHelp = false;
  final Set<String> _expandedServices = {'Context Building', 'Decompose', 'Clean'}; // Default expanded

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final configsAsync = ref.watch(aiConfigsProvider);

    return configsAsync.when(
      data: (configs) => _buildConfigsList(context, colors, configs),
      loading: () => Container(
        height: 200,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      ),
      error: (err, _) => _buildErrorState(colors, 'AI configs', err.toString()),
    );
  }

  Widget _buildConfigsList(
    BuildContext context,
    FlowColorScheme colors,
    List<AIPromptConfig> configs,
  ) {
    if (configs.isEmpty) {
      return _buildEmptyState(colors, 'No AI configurations found');
    }

    // Create a map for quick config lookup
    final configMap = {for (var c in configs) c.key: c};

    return Column(
      children: [
        // Help toggle button
        _buildHelpToggle(colors),
        // Collapsible help section
        if (_showHelp) _buildHelpSection(colors),
        // Services grouped with their configs
        ..._aiServices.map((service) => _buildServiceGroup(colors, service, configMap)),
      ],
    );
  }

  Widget _buildServiceGroup(
    FlowColorScheme colors,
    _AIService service,
    Map<String, AIPromptConfig> configMap,
  ) {
    final isExpanded = _expandedServices.contains(service.name);
    final serviceConfigs = service.configKeys
        .map((key) => configMap[key])
        .where((c) => c != null)
        .cast<AIPromptConfig>()
        .toList();
    final hasConfigs = serviceConfigs.isNotEmpty;

    return Column(
      children: [
        // Service header
        InkWell(
          onTap: hasConfigs ? () {
            setState(() {
              if (isExpanded) {
                _expandedServices.remove(service.name);
              } else {
                _expandedServices.add(service.name);
              }
            });
          } : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceVariant.withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(color: colors.divider.withValues(alpha: 0.5), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                if (hasConfigs)
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: colors.textSecondary,
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Icon(service.icon, size: 18, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            service.name,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusBadge(isImplemented: service.isImplemented),
                        ],
                      ),
                      Text(
                        service.description,
                        style: TextStyle(color: colors.textTertiary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (hasConfigs)
                  Text(
                    '${serviceConfigs.length}',
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                  )
                else
                  Text(
                    'No config',
                    style: TextStyle(color: colors.textTertiary.withValues(alpha: 0.6), fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
        // Config items (when expanded)
        if (isExpanded && hasConfigs)
          ...serviceConfigs.map((config) => _AIConfigItem(
            config: config,
            onTap: () => widget.onEditConfig(config),
            indent: true,
          )),
      ],
    );
  }

  Widget _buildHelpToggle(FlowColorScheme colors) {
    return InkWell(
      onTap: () => setState(() => _showHelp = !_showHelp),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.05),
          border: Border(
            bottom: BorderSide(color: colors.divider.withValues(alpha: 0.5), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _showHelp ? Icons.help : Icons.help_outline,
              size: 16,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Formatting Guidelines',
              style: TextStyle(
                color: colors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(
              _showHelp ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: colors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpSection(FlowColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          bottom: BorderSide(color: colors.divider.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Safe to use
          Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
              const SizedBox(width: 6),
              Text(
                'Safe to use:',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              "• Plain text and numbers\n"
              "• Single quotes: 'example'\n"
              "• Parentheses: (like this)\n"
              "• Symbols: 1-10, max 20 words, etc.",
              style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          // Avoid if possible
          Row(
            children: [
              Icon(Icons.warning_amber, size: 14, color: Colors.orange.shade700),
              const SizedBox(width: 6),
              Text(
                'Avoid if possible (auto-escaped but may confuse AI):',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              '• Double quotes: "\n'
              '• Curly braces: { }\n'
              '• Square brackets: [ ]',
              style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          // Note
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Special characters are auto-escaped to protect JSON structure. '
                    'Worst case is a confusing prompt, not a broken one. '
                    'Use "Reset" to restore defaults.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 11, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(FlowColorScheme colors, String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.psychology_outlined, size: 48, color: colors.textTertiary),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: colors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildErrorState(FlowColorScheme colors, String type, String error) {
    if (error.contains('null') || error.contains('empty') || error.contains('404')) {
      return _buildEmptyState(colors, 'No $type yet');
    }
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 40, color: colors.error),
          const SizedBox(height: 12),
          Text(
            'Failed to load $type',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Status badge for implementation status
class _StatusBadge extends StatelessWidget {
  final bool isImplemented;

  const _StatusBadge({required this.isImplemented});

  @override
  Widget build(BuildContext context) {
    final color = isImplemented ? Colors.green : Colors.orange;
    final label = isImplemented ? 'Active' : 'Planned';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isImplemented ? Colors.green.shade700 : Colors.orange.shade700,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// AI Config item (Bear-style)
class _AIConfigItem extends StatelessWidget {
  final AIPromptConfig config;
  final VoidCallback onTap;
  final bool indent;

  const _AIConfigItem({
    required this.config,
    required this.onTap,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
          left: indent ? 48 : 16,
          right: 16,
          top: 10,
          bottom: 10,
        ),
        decoration: BoxDecoration(
          color: indent ? colors.background : null,
          border: Border(
            bottom: BorderSide(color: colors.divider.withValues(alpha: 0.3), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.tune, size: 14, color: Colors.purple),
            ),
            const SizedBox(width: 10),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.displayName,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    config.value.length > 50
                        ? '${config.value.substring(0, 50)}...'
                        : config.value,
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Edit indicator
            Icon(Icons.chevron_right, size: 18, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Edit AI config dialog
class _EditAIConfigDialog extends ConsumerStatefulWidget {
  final AIPromptConfig config;

  const _EditAIConfigDialog({required this.config});

  @override
  ConsumerState<_EditAIConfigDialog> createState() => _EditAIConfigDialogState();
}

class _EditAIConfigDialogState extends ConsumerState<_EditAIConfigDialog> {
  late TextEditingController _valueController;
  bool _isLoading = false;
  String? _error;
  bool _hasWarning = false;

  // Default values for reset functionality
  static const Map<String, String> _defaults = {
    'system_first_context': '''You are Flow AI, an assistant for Flow Tasks - a personal task management app.

PRINCIPLES:
- Be concise and actionable
- Respect user privacy
- Focus on productivity

RESTRICTIONS (Universal):
- No violence, weapons, harm instructions
- No self-harm or suicide content
- No pornographic/explicit content
- No illegal activities assistance
- No medical/legal/financial advice (suggest professionals)

RESTRICTIONS (Regional):
- Vietnam/China: No political commentary, no criticism of government/leaders
- Monarchies (Thailand, Saudi Arabia, UAE, etc.): No disrespect to royal family

OUTPUT: Always respond in valid JSON when requested.''',
    'clean_title_instruction': 'Concise, action-oriented title (max 10 words). IMPORTANT: Preserve all entities - dates, times, people names, places, organizations must NOT be removed or changed.',
    'summary_instruction': 'Brief summary if description is long (max 20 words). IMPORTANT: Preserve all entities - dates, times, people names, places, organizations must NOT be removed or changed.',
    'complexity_instruction': "1-10 scale (1=trivial like 'buy milk', 10=complex multi-step project)",
    'due_date_instruction': "ISO 8601 date if mentioned (e.g., 'tomorrow' = next day, 'next week' = next Monday)",
    'reminder_instruction': "ISO 8601 datetime if 'remind me' or similar phrase found",
    'entities_instruction': 'person|place|organization',
    'duplicate_check_instruction': 'Compare task semantically to find similar tasks covering the same goal',
    'recurrence_instruction': "RRULE string if recurring pattern detected (e.g., 'every Monday')",
    'suggested_group_instruction': "Category suggestion based on content (e.g., 'Work', 'Shopping', 'Health')",
    'decompose_step_count': '2-5',
    'decompose_rules': 'Each step should be a single, concrete action\nSteps should be in logical order\nUse action verbs (Call, Send, Research, Write, etc.)\nKeep each step under 10 words',
  };

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: widget.config.value);
    _valueController.addListener(_checkForWarnings);
  }

  @override
  void dispose() {
    _valueController.removeListener(_checkForWarnings);
    _valueController.dispose();
    super.dispose();
  }

  void _checkForWarnings() {
    final value = _valueController.text;
    // Warn if value contains characters that might cause issues
    final hasProblematicChars = value.contains('"') ||
                                 value.contains('{') ||
                                 value.contains('}') ||
                                 value.contains('[') ||
                                 value.contains(']');
    if (hasProblematicChars != _hasWarning) {
      setState(() => _hasWarning = hasProblematicChars);
    }
  }

  void _resetToDefault() {
    final defaultValue = _defaults[widget.config.key];
    if (defaultValue != null) {
      _valueController.text = defaultValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.psychology, size: 20, color: Colors.purple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.config.displayName,
              style: TextStyle(color: colors.textPrimary, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Description
            if (widget.config.description != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: colors.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.config.description!,
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Error message
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
              ),
              const SizedBox(height: 12),
            ],

            // Warning about special characters
            if (_hasWarning) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Special characters (" { } [ ]) are auto-escaped, but may affect prompt clarity.',
                        style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Value input with reset button
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Value',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                if (_defaults.containsKey(widget.config.key))
                  TextButton.icon(
                    onPressed: _resetToDefault,
                    icon: Icon(Icons.restore, size: 14, color: colors.primary),
                    label: Text('Reset', style: TextStyle(fontSize: 12, color: colors.primary)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _valueController,
              maxLines: widget.config.key.contains('rules') || widget.config.key.contains('first_context') ? 12 : 3,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Enter value...',
                hintStyle: TextStyle(color: colors.textTertiary),
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.primary),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),

            const SizedBox(height: 12),

            // Last updated info
            if (widget.config.updatedBy != null)
              Text(
                'Last updated by ${widget.config.updatedBy} on ${DateFormat('MMM d, yyyy').format(widget.config.updatedAt)}',
                style: TextStyle(color: colors.textTertiary, fontSize: 11),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _saveChanges,
          style: FilledButton.styleFrom(backgroundColor: colors.primary),
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _saveChanges() async {
    final value = _valueController.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Value cannot be empty');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final aiConfigActions = ref.read(aiConfigActionsProvider);
      await aiConfigActions.update(widget.config.key, value);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
