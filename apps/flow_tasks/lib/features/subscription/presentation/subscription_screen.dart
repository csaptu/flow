import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';

/// Subscription pricing screen with 3 compact plan cards
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? _selectedTier; // Store tier, not plan ID - plan ID depends on billing period
  bool _isLoading = false;
  String? _error;
  bool _isYearly = true; // Default to yearly for better value

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final plans = ref.watch(subscriptionPlansProvider);
    final currentSub = ref.watch(userSubscriptionProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(
          'Upgrade Plan',
          style: TextStyle(color: colors.textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
      ),
      body: plans.when(
        data: (planList) => _buildContent(planList, currentSub, colors),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.error),
              const SizedBox(height: 16),
              Text(
                'Failed to load plans',
                style: TextStyle(color: colors.textPrimary),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(subscriptionPlansProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    List<SubscriptionPlan> plans,
    AsyncValue<UserSubscription> currentSub,
    FlowColorScheme colors,
  ) {
    final currentTier = currentSub.valueOrNull?.tier ?? 'free';
    final screenWidth = MediaQuery.of(context).size.width;

    // Group plans by tier - keep only one plan per tier
    final plansByTier = <String, SubscriptionPlan>{};
    for (final plan in plans) {
      if (!plansByTier.containsKey(plan.tier)) {
        plansByTier[plan.tier] = plan;
      }
    }

    // Sort by tier order: free, light, premium
    final tierOrder = ['free', 'light', 'premium'];
    final uniquePlans = tierOrder
        .where((tier) => plansByTier.containsKey(tier))
        .map((tier) => plansByTier[tier]!)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header
          Text(
            'Choose Your Plan',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Unlock powerful AI features',
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Billing toggle
          _buildBillingToggle(colors),
          const SizedBox(height: 24),

          // Error message
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colors.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 3 Plan cards side by side (one per tier)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: uniquePlans.map((plan) {
                final isFirst = plan == uniquePlans.first;
                final isLast = plan == uniquePlans.last;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: isFirst ? 0 : 4,
                      right: isLast ? 0 : 4,
                    ),
                    child: _CompactPlanCard(
                      plan: plan,
                      isYearly: _isYearly,
                      isSelected: _selectedTier == plan.tier,
                      isCurrent: plan.tier == currentTier,
                      isNarrow: screenWidth < 500,
                      onSelect: plan.tier == currentTier
                          ? null
                          : () => setState(() => _selectedTier = plan.tier),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // Subscribe button
          if (_selectedTier != null)
            SizedBox(
              width: 280,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSubscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Continue to Payment',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),

          const SizedBox(height: 32),

          // Notes - compact
          Text(
            'Cancel anytime • Secure payment via Paddle',
            style: TextStyle(
              fontSize: 12,
              color: colors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBillingToggle(FlowColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            label: 'Monthly',
            isSelected: !_isYearly,
            onTap: () => setState(() => _isYearly = false),
            colors: colors,
          ),
          _ToggleButton(
            label: 'Yearly',
            badge: 'Save 20%',
            isSelected: _isYearly,
            onTap: () => setState(() => _isYearly = true),
            colors: colors,
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubscribe() async {
    if (_selectedTier == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tasksService = ref.read(tasksServiceProvider);
      final returnUrl = Uri.base.toString();

      // Get all plans and find the correct one based on tier and billing period
      final plans = ref.read(subscriptionPlansProvider).valueOrNull ?? [];
      final suffix = _isYearly ? 'yearly' : 'monthly';

      // Find plan matching tier and billing period (e.g., "light_yearly" or "light_monthly")
      final targetPlanId = '${_selectedTier}_$suffix';
      final plan = plans.firstWhere(
        (p) => p.id == targetPlanId || (p.tier == _selectedTier && p.id.contains(suffix)),
        orElse: () => plans.firstWhere((p) => p.tier == _selectedTier),
      );

      final checkout = await tasksService.createCheckout(
        plan.id,
        returnUrl: returnUrl,
        isYearly: _isYearly,
      );

      if (mounted) {
        _showCheckoutDialog(checkout);
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

  void _showCheckoutDialog(CheckoutResponse checkout) {
    final colors = context.flowColors;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Complete Payment',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order ID: ${checkout.orderId}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Text(
              'Amount: \$${checkout.amount.toStringAsFixed(2)} ${checkout.currency}/month',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You will be redirected to Paddle to complete your payment securely.',
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _launchPaddleCheckout(checkout);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
            ),
            child: const Text('Pay Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchPaddleCheckout(CheckoutResponse checkout) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Paddle checkout will open here. Order: ${checkout.orderId}',
          ),
          duration: const Duration(seconds: 3),
        ),
      );

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          ref.invalidate(userSubscriptionProvider);
        }
      });
    }
  }
}

/// Toggle button for billing period
class _ToggleButton extends StatelessWidget {
  final String label;
  final String? badge;
  final bool isSelected;
  final VoidCallback onTap;
  final FlowColorScheme colors;

  const _ToggleButton({
    required this.label,
    this.badge,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : colors.textSecondary,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.green,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact plan card that works on mobile
class _CompactPlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isYearly;
  final bool isSelected;
  final bool isCurrent;
  final bool isNarrow;
  final VoidCallback? onSelect;

  const _CompactPlanCard({
    required this.plan,
    required this.isYearly,
    required this.isSelected,
    required this.isCurrent,
    required this.isNarrow,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final tierColor = _getTierColor(plan.tier);

    Color borderColor;
    if (isCurrent) {
      borderColor = colors.primary;
    } else if (isSelected) {
      borderColor = tierColor;
    } else {
      borderColor = colors.border;
    }

    // Calculate price - use actual yearly price if available
    final monthlyPrice = plan.priceMonthly;
    // Yearly price per month = yearly total / 12
    final yearlyMonthlyPrice = plan.priceYearly != null
        ? plan.priceYearly! / 12
        : plan.priceMonthly * 0.8;
    final displayPrice = isYearly ? yearlyMonthlyPrice : monthlyPrice;
    final yearlyTotal = plan.priceYearly ?? (plan.priceMonthly * 12 * 0.8);

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: (isSelected || isCurrent) ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // Header badge
            if (isCurrent || isSelected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isCurrent ? colors.primary : tierColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                ),
                child: Text(
                  isCurrent ? 'Current' : 'Selected',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),

            // Content
            Padding(
              padding: EdgeInsets.all(isNarrow ? 12 : 16),
              child: Column(
                children: [
                  // Icon
                  _TierIcon(tier: plan.tier, size: isNarrow ? 36 : 44),
                  SizedBox(height: isNarrow ? 8 : 12),

                  // Plan name
                  Text(
                    plan.tier == 'light' ? 'Basic' : plan.name.split(' ').first,
                    style: TextStyle(
                      fontSize: isNarrow ? 14 : 16,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: isNarrow ? 4 : 8),

                  // Price
                  if (plan.isFree)
                    Text(
                      'Free',
                      style: TextStyle(
                        fontSize: isNarrow ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    )
                  else
                    Column(
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '\$${displayPrice.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: isNarrow ? 20 : 24,
                                  fontWeight: FontWeight.bold,
                                  color: colors.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: '/mo',
                                style: TextStyle(
                                  fontSize: isNarrow ? 10 : 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isYearly && !plan.isFree)
                          Text(
                            '\$${yearlyTotal.toStringAsFixed(0)}/year',
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.textTertiary,
                            ),
                          ),
                      ],
                    ),

                  SizedBox(height: isNarrow ? 8 : 12),

                  // Key features (compact)
                  ...plan.features.take(isNarrow ? 2 : 3).map((feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check,
                              size: 12,
                              color: tierColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                feature,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: isNarrow ? 10 : 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )),

                  SizedBox(height: isNarrow ? 8 : 12),

                  // Select button
                  if (!isCurrent)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: onSelect,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isSelected ? tierColor : colors.border,
                          ),
                          padding: EdgeInsets.symmetric(
                            vertical: isNarrow ? 6 : 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          isSelected ? 'Selected' : 'Select',
                          style: TextStyle(
                            color: isSelected ? tierColor : colors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: isNarrow ? 11 : 12,
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: null,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.primary),
                          padding: EdgeInsets.symmetric(
                            vertical: isNarrow ? 6 : 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Current',
                          style: TextStyle(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: isNarrow ? 11 : 12,
                          ),
                        ),
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

class _TierIcon extends StatelessWidget {
  final String tier;
  final double size;

  const _TierIcon({required this.tier, this.size = 44});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (tier) {
      case 'premium':
        icon = Icons.diamond;
        color = Colors.purple;
        break;
      case 'light':
        icon = Icons.bolt;
        color = Colors.blue;
        break;
      default:
        icon = Icons.person;
        color = Colors.grey;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}
