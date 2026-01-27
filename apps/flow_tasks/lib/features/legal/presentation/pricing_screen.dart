import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';

class PricingScreen extends StatelessWidget {
  const PricingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
        ),
        title: const Text('Pricing'),
      ),
      body: SingleChildScrollView(
        padding: FlowSpacing.screenPadding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              children: [
                const SizedBox(height: FlowSpacing.lg),
                Text(
                  'Simple, transparent pricing',
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FlowSpacing.sm),
                Text(
                  'Choose the plan that works for you',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: FlowColors.lightTextSecondary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FlowSpacing.xxl),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 700) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildPlanCard(context, _freePlan)),
                          const SizedBox(width: FlowSpacing.md),
                          Expanded(child: _buildPlanCard(context, _lightPlan, isPopular: true)),
                          const SizedBox(width: FlowSpacing.md),
                          Expanded(child: _buildPlanCard(context, _premiumPlan)),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _buildPlanCard(context, _freePlan),
                        const SizedBox(height: FlowSpacing.md),
                        _buildPlanCard(context, _lightPlan, isPopular: true),
                        const SizedBox(height: FlowSpacing.md),
                        _buildPlanCard(context, _premiumPlan),
                      ],
                    );
                  },
                ),
                const SizedBox(height: FlowSpacing.xxl),
                Text(
                  'All plans include',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: FlowSpacing.md),
                Wrap(
                  spacing: FlowSpacing.xl,
                  runSpacing: FlowSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildFeatureChip(context, 'Unlimited tasks'),
                    _buildFeatureChip(context, 'Subtasks'),
                    _buildFeatureChip(context, 'Tags & hashtags'),
                    _buildFeatureChip(context, 'Due dates'),
                    _buildFeatureChip(context, 'File attachments'),
                    _buildFeatureChip(context, 'Cross-device sync'),
                  ],
                ),
                const SizedBox(height: FlowSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, _PlanData plan, {bool isPopular = false}) {
    return Container(
      padding: const EdgeInsets.all(FlowSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(FlowSpacing.radiusMd),
        border: Border.all(
          color: isPopular ? FlowColors.primary : Colors.grey.shade300,
          width: isPopular ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPopular)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: FlowColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Most Popular',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          if (isPopular) const SizedBox(height: FlowSpacing.sm),
          Text(
            plan.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: FlowSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                plan.price,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (plan.period.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text(
                    plan.period,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: FlowColors.lightTextSecondary,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: FlowSpacing.sm),
          Text(
            plan.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: FlowColors.lightTextSecondary,
                ),
          ),
          const SizedBox(height: FlowSpacing.lg),
          ...plan.features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: FlowSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: FlowColors.primary, size: 20),
                    const SizedBox(width: FlowSpacing.sm),
                    Expanded(child: Text(f)),
                  ],
                ),
              )),
          const SizedBox(height: FlowSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: isPopular
                ? FilledButton(
                    onPressed: () => context.go('/register'),
                    child: const Text('Get Started'),
                  )
                : OutlinedButton(
                    onPressed: () => context.go('/register'),
                    child: const Text('Get Started'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(BuildContext context, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, color: FlowColors.primary, size: 18),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

class _PlanData {
  final String name;
  final String price;
  final String period;
  final String description;
  final List<String> features;

  const _PlanData({
    required this.name,
    required this.price,
    required this.period,
    required this.description,
    required this.features,
  });
}

const _freePlan = _PlanData(
  name: 'Free',
  price: '\$0',
  period: '',
  description: 'Perfect for getting started',
  features: [
    '10 AI cleanups per day',
    '5 AI decompose per day',
    '3 similar task checks per day',
    'Basic Smart Lists',
  ],
);

const _lightPlan = _PlanData(
  name: 'Light',
  price: '\$4.99',
  period: '/month',
  description: 'For power users',
  features: [
    'Unlimited AI cleanups',
    'Unlimited AI decompose',
    'Unlimited similar checks',
    'Advanced Smart Lists',
    'Priority support',
  ],
);

const _premiumPlan = _PlanData(
  name: 'Premium',
  price: '\$9.99',
  period: '/month',
  description: 'For teams and professionals',
  features: [
    'Everything in Light',
    'AI email drafts',
    'AI calendar invites',
    'API access',
    'Custom integrations',
  ],
);
