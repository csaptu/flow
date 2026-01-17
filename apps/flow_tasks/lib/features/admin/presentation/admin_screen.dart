import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_api/flow_api.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:intl/intl.dart';

/// Admin section type
enum AdminSection { users, orders }

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
    return Row(
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

  const _UsersContent({
    required this.tierFilter,
    required this.page,
    required this.onPageChanged,
    required this.onEditUser,
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

  const _UserItem({required this.user, required this.onTap});

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
  DateTime? _expiresAt;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedTier = widget.user.tier;
    _selectedPlanId = widget.user.planId;
    _expiresAt = widget.user.expiresAt;
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
                        } else {
                          final plan = planList.firstWhere((p) => p.id == value);
                          _selectedTier = plan.tier;
                        }
                      });
                    },
                  ),
                ),
              ),
              loading: () => const SizedBox(height: 48, child: Center(child: CircularProgressIndicator())),
              error: (_, __) => Text('Failed to load plans', style: TextStyle(color: colors.error)),
            ),

            // Expiration date
            if (_selectedPlanId != null) ...[
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

  Future<void> _selectExpirationDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date != null) {
      setState(() => _expiresAt = date);
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
