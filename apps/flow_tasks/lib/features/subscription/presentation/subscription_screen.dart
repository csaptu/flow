import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';

/// Subscription pricing screen with responsive 3-column layout
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? _selectedPlanId;
  bool _isLoading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final plans = ref.watch(subscriptionPlansProvider);
    final currentSub = ref.watch(userSubscriptionProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;

    // When embedded in settings, don't show app bar
    final isEmbedded = ModalRoute.of(context)?.settings.name == null;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: isEmbedded
          ? null
          : AppBar(
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
        data: (planList) => _buildContent(planList, currentSub, colors, isWide),
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
    bool isWide,
  ) {
    final currentTier = currentSub.valueOrNull?.tier ?? 'free';

    // Sort plans: free, light, premium
    final sortedPlans = List<SubscriptionPlan>.from(plans)
      ..sort((a, b) {
        const order = {'free': 0, 'light': 1, 'premium': 2};
        return (order[a.tier] ?? 0).compareTo(order[b.tier] ?? 0);
      });

    return SingleChildScrollView(
      padding: EdgeInsets.all(isWide ? 40 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            'Choose Your Plan',
            style: TextStyle(
              fontSize: isWide ? 32 : 28,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Unlock powerful AI features to boost your productivity',
            style: TextStyle(
              fontSize: 16,
              color: colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

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

          // Plan cards - 3 columns on wide, stacked on narrow
          if (isWide)
            _buildWideLayout(sortedPlans, currentTier, colors)
          else
            _buildNarrowLayout(sortedPlans, currentTier, colors),

          const SizedBox(height: 32),

          // Subscribe button
          if (_selectedPlanId != null)
            Center(
              child: SizedBox(
                width: isWide ? 300 : double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSubscribe,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),

          const SizedBox(height: 40),

          // Notes
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: colors.textTertiary),
                        const SizedBox(width: 8),
                        Text(
                          'Notes',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _NoteItem(
                      text: 'Cancel anytime. No questions asked.',
                      colors: colors,
                    ),
                    _NoteItem(
                      text: 'Secure payment via Paddle',
                      colors: colors,
                    ),
                    _NoteItem(
                      text: 'Usage limits reset daily at midnight UTC',
                      colors: colors,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(
    List<SubscriptionPlan> plans,
    String currentTier,
    FlowColorScheme colors,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: plans.map((plan) {
            final isPopular = plan.tier == 'premium';
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _PlanColumn(
                  plan: plan,
                  isSelected: _selectedPlanId == plan.id,
                  isCurrent: plan.tier == currentTier,
                  isPopular: isPopular,
                  showAllFeatures: true,
                  onSelect: plan.tier == currentTier
                      ? null
                      : () => setState(() => _selectedPlanId = plan.id),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(
    List<SubscriptionPlan> plans,
    String currentTier,
    FlowColorScheme colors,
  ) {
    return Column(
      children: plans.map((plan) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _PlanColumn(
            plan: plan,
            isSelected: _selectedPlanId == plan.id,
            isCurrent: plan.tier == currentTier,
            isPopular: plan.tier == 'premium',
            showAllFeatures: false, // Hide "early access" on narrow
            onSelect: plan.tier == currentTier
                ? null
                : () => setState(() => _selectedPlanId = plan.id),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _handleSubscribe() async {
    if (_selectedPlanId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tasksService = ref.read(tasksServiceProvider);
      final returnUrl = Uri.base.toString();

      final checkout = await tasksService.createCheckout(
        _selectedPlanId!,
        returnUrl: returnUrl,
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

class _PlanColumn extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isSelected;
  final bool isCurrent;
  final bool isPopular;
  final bool showAllFeatures;
  final VoidCallback? onSelect;

  const _PlanColumn({
    required this.plan,
    required this.isSelected,
    required this.isCurrent,
    required this.isPopular,
    required this.showAllFeatures,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    Color borderColor;
    Color? headerBgColor;

    if (isCurrent) {
      borderColor = colors.textTertiary;
      headerBgColor = colors.textTertiary;
    } else if (isSelected) {
      borderColor = colors.primary;
      headerBgColor = colors.primary;
    } else if (isPopular) {
      borderColor = Colors.purple;
      headerBgColor = Colors.purple;
    } else {
      borderColor = colors.border;
      headerBgColor = null;
    }

    // Filter features for narrow screens
    final features = showAllFeatures
        ? plan.features
        : plan.features
            .where((f) => !f.toLowerCase().contains('early access'))
            .toList();

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: isSelected || isPopular ? 2 : 1,
          ),
          boxShadow: isSelected || isPopular
              ? [
                  BoxShadow(
                    color: borderColor.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with badge
            if (headerBgColor != null)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: headerBgColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                ),
                child: Text(
                  isCurrent
                      ? 'Current Plan'
                      : isSelected
                          ? 'Selected'
                          : 'Most Popular',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Tier icon
                  _TierIcon(tier: plan.tier),
                  const SizedBox(height: 16),

                  // Plan name
                  Text(
                    plan.name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Price
                  if (plan.isFree)
                    Text(
                      'Free',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    )
                  else
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '\$${plan.priceMonthly.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          TextSpan(
                            text: '/mo',
                            style: TextStyle(
                              fontSize: 16,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Divider
                  Divider(color: colors.border),

                  const SizedBox(height: 16),

                  // Features
                  ...features.map((feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 18,
                              color: _getFeatureColor(plan.tier),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                feature,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),

                  const SizedBox(height: 16),

                  // Select button
                  if (!isCurrent)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: onSelect,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isSelected
                                ? colors.primary
                                : _getFeatureColor(plan.tier),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          isSelected ? 'Selected' : 'Select Plan',
                          style: TextStyle(
                            color: isSelected
                                ? colors.primary
                                : _getFeatureColor(plan.tier),
                            fontWeight: FontWeight.w600,
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

  Color _getFeatureColor(String tier) {
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

  const _TierIcon({required this.tier});

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
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }
}

class _NoteItem extends StatelessWidget {
  final String text;
  final FlowColorScheme colors;

  const _NoteItem({
    required this.text,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•',
            style: TextStyle(color: colors.textTertiary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
