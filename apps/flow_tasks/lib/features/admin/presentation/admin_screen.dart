import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_api/flow_api.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:intl/intl.dart';

/// Admin dashboard screen
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _userTierFilter = 'all';
  String _orderStatusFilter = 'all';
  int _usersPage = 1;
  int _ordersPage = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(
          'Admin Dashboard',
          style: TextStyle(color: colors.textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: colors.primary,
          unselectedLabelColor: colors.textSecondary,
          indicatorColor: colors.primary,
          tabs: const [
            Tab(text: 'Users', icon: Icon(Icons.people)),
            Tab(text: 'Orders', icon: Icon(Icons.receipt_long)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _UsersTab(
            tierFilter: _userTierFilter,
            page: _usersPage,
            onTierFilterChanged: (tier) => setState(() {
              _userTierFilter = tier;
              _usersPage = 1;
            }),
            onPageChanged: (page) => setState(() => _usersPage = page),
          ),
          _OrdersTab(
            statusFilter: _orderStatusFilter,
            page: _ordersPage,
            onStatusFilterChanged: (status) => setState(() {
              _orderStatusFilter = status;
              _ordersPage = 1;
            }),
            onPageChanged: (page) => setState(() => _ordersPage = page),
          ),
        ],
      ),
    );
  }
}

class _UsersTab extends ConsumerWidget {
  final String tierFilter;
  final int page;
  final ValueChanged<String> onTierFilterChanged;
  final ValueChanged<int> onPageChanged;

  const _UsersTab({
    required this.tierFilter,
    required this.page,
    required this.onTierFilterChanged,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final usersAsync = ref.watch(adminUsersProvider((
      tier: tierFilter == 'all' ? null : tierFilter,
      page: page,
    )));

    return Column(
      children: [
        // Filter bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Text('Filter by tier:', style: TextStyle(color: colors.textSecondary)),
              const SizedBox(width: 12),
              _FilterChip(
                label: 'All',
                isSelected: tierFilter == 'all',
                onTap: () => onTierFilterChanged('all'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Free',
                isSelected: tierFilter == 'free',
                onTap: () => onTierFilterChanged('free'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Light',
                isSelected: tierFilter == 'light',
                onTap: () => onTierFilterChanged('light'),
                color: Colors.blue,
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Premium',
                isSelected: tierFilter == 'premium',
                onTap: () => onTierFilterChanged('premium'),
                color: Colors.purple,
              ),
            ],
          ),
        ),

        // Users list
        Expanded(
          child: usersAsync.when(
            data: (response) => _buildUsersList(context, ref, response, colors),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colors.error),
                  const SizedBox(height: 16),
                  Text('Failed to load users', style: TextStyle(color: colors.textPrimary)),
                  const SizedBox(height: 8),
                  Text(err.toString(), style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsersList(
    BuildContext context,
    WidgetRef ref,
    PaginatedResponse<AdminUser> response,
    FlowColorScheme colors,
  ) {
    final totalPages = response.meta?.totalPages ?? 1;

    if (response.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text('No users found', style: TextStyle(color: colors.textSecondary)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: response.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = response.items[index];
              return _UserCard(
                user: user,
                onEdit: () => _showEditUserDialog(context, ref, user),
              );
            },
          ),
        ),

        // Pagination
        if (totalPages > 1)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
                  icon: Icon(Icons.chevron_left, color: colors.textSecondary),
                ),
                Text(
                  'Page $page of $totalPages',
                  style: TextStyle(color: colors.textSecondary),
                ),
                IconButton(
                  onPressed: page < totalPages ? () => onPageChanged(page + 1) : null,
                  icon: Icon(Icons.chevron_right, color: colors.textSecondary),
                ),
              ],
            ),
          ),
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

class _UserCard extends StatelessWidget {
  final AdminUser user;
  final VoidCallback onEdit;

  const _UserCard({required this.user, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final dateFormat = DateFormat('MMM d, yyyy');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            backgroundColor: _getTierColor(user.tier).withValues(alpha: 0.2),
            child: Text(
              (user.name ?? user.email).substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: _getTierColor(user.tier),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // User info
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
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _TierBadge(tier: user.tier),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.task_alt, size: 14, color: colors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      '${user.taskCount} tasks',
                      style: TextStyle(color: colors.textTertiary, fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.calendar_today, size: 14, color: colors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      'Joined ${dateFormat.format(user.createdAt)}',
                      style: TextStyle(color: colors.textTertiary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Edit button
          IconButton(
            onPressed: onEdit,
            icon: Icon(Icons.edit, color: colors.textSecondary),
            tooltip: 'Edit subscription',
          ),
        ],
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
        'Edit User Subscription',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info
            Text(
              widget.user.email,
              style: TextStyle(color: colors.textSecondary),
            ),
            if (widget.user.name != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.user.name!,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Error message
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: colors.error)),
              ),
              const SizedBox(height: 16),
            ],

            // Tier selection
            Text(
              'Subscription Tier',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            plans.when(
              data: (planList) => DropdownButtonFormField<String>(
                value: _selectedPlanId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
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
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => Text(
                'Failed to load plans',
                style: TextStyle(color: colors.error),
              ),
            ),

            const SizedBox(height: 16),

            // Expiration date
            if (_selectedPlanId != null) ...[
              Text(
                'Expires At',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
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
                      Icon(Icons.calendar_today, size: 18, color: colors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        _expiresAt != null
                            ? DateFormat('MMM d, yyyy').format(_expiresAt!)
                            : 'No expiration',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                      const Spacer(),
                      if (_expiresAt != null)
                        IconButton(
                          onPressed: () => setState(() => _expiresAt = null),
                          icon: Icon(Icons.clear, size: 18, color: colors.textTertiary),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
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
        ElevatedButton(
          onPressed: _isLoading ? null : _saveChanges,
          style: ElevatedButton.styleFrom(backgroundColor: colors.primary),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
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

class _OrdersTab extends ConsumerWidget {
  final String statusFilter;
  final int page;
  final ValueChanged<String> onStatusFilterChanged;
  final ValueChanged<int> onPageChanged;

  const _OrdersTab({
    required this.statusFilter,
    required this.page,
    required this.onStatusFilterChanged,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final ordersAsync = ref.watch(adminOrdersProvider((
      status: statusFilter == 'all' ? null : statusFilter,
      provider: null,
      tier: null,
      page: page,
    )));

    return Column(
      children: [
        // Filter bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Text('Filter by status:', style: TextStyle(color: colors.textSecondary)),
              const SizedBox(width: 12),
              _FilterChip(
                label: 'All',
                isSelected: statusFilter == 'all',
                onTap: () => onStatusFilterChanged('all'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Pending',
                isSelected: statusFilter == 'pending',
                onTap: () => onStatusFilterChanged('pending'),
                color: Colors.orange,
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Completed',
                isSelected: statusFilter == 'completed',
                onTap: () => onStatusFilterChanged('completed'),
                color: Colors.green,
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Failed',
                isSelected: statusFilter == 'failed',
                onTap: () => onStatusFilterChanged('failed'),
                color: Colors.red,
              ),
            ],
          ),
        ),

        // Orders list
        Expanded(
          child: ordersAsync.when(
            data: (response) => _buildOrdersList(context, response, colors),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colors.error),
                  const SizedBox(height: 16),
                  Text('Failed to load orders', style: TextStyle(color: colors.textPrimary)),
                  const SizedBox(height: 8),
                  Text(err.toString(), style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrdersList(
    BuildContext context,
    PaginatedResponse<Order> response,
    FlowColorScheme colors,
  ) {
    final totalPages = response.meta?.totalPages ?? 1;

    if (response.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text('No orders found', style: TextStyle(color: colors.textSecondary)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: response.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final order = response.items[index];
              return _OrderCard(order: order);
            },
          ),
        ),

        // Pagination
        if (totalPages > 1)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
                  icon: Icon(Icons.chevron_left, color: colors.textSecondary),
                ),
                Text(
                  'Page $page of $totalPages',
                  style: TextStyle(color: colors.textSecondary),
                ),
                IconButton(
                  onPressed: page < totalPages ? () => onPageChanged(page + 1) : null,
                  icon: Icon(Icons.chevron_right, color: colors.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final dateFormat = DateFormat('MMM d, yyyy HH:mm');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  order.id.substring(0, 8),
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              _StatusBadge(status: order.status),
            ],
          ),

          const SizedBox(height: 12),

          // User and plan
          Row(
            children: [
              Icon(Icons.person, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.userEmail ?? order.userId,
                  style: TextStyle(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Icon(Icons.local_offer, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                order.planName ?? order.planId,
                style: TextStyle(color: colors.textSecondary),
              ),
              const Spacer(),
              Text(
                '\$${order.amount.toStringAsFixed(2)} ${order.currency}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Dates
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: colors.textTertiary),
              const SizedBox(width: 4),
              Text(
                'Created: ${dateFormat.format(order.createdAt)}',
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
              if (order.completedAt != null) ...[
                const SizedBox(width: 16),
                Icon(Icons.check_circle, size: 14, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  'Completed: ${dateFormat.format(order.completedAt!)}',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withValues(alpha: 0.15) : colors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? chipColor : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? chipColor : colors.textSecondary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

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
        label = 'Premium';
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (status) {
      case 'completed':
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'pending':
        color = Colors.orange;
        icon = Icons.schedule;
        break;
      case 'failed':
        color = Colors.red;
        icon = Icons.error;
        break;
      case 'refunded':
        color = Colors.blue;
        icon = Icons.replay;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status.substring(0, 1).toUpperCase() + status.substring(1),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
