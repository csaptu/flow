import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
        ),
        title: const Text('Terms of Service'),
      ),
      body: SingleChildScrollView(
        padding: FlowSpacing.screenPadding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Terms of Service',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: FlowSpacing.sm),
                Text(
                  'Last updated: January 2025',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: FlowSpacing.lg),
                const Text(
                  'Welcome to Flow Tasks. By using our service, you agree to these terms.',
                ),
                const SizedBox(height: FlowSpacing.xl),
                _buildSection(
                  context,
                  '1. Service Description',
                  'Flow Tasks is a task management application with AI-powered features to help you organize and complete tasks efficiently.',
                ),
                _buildSection(
                  context,
                  '2. User Accounts',
                  null,
                  bullets: [
                    'You must provide accurate information when creating an account',
                    'You are responsible for maintaining the security of your account',
                    'You must be at least 13 years old to use this service',
                  ],
                ),
                _buildSection(
                  context,
                  '3. Acceptable Use',
                  'You agree not to:',
                  bullets: [
                    'Use the service for any illegal purposes',
                    'Attempt to gain unauthorized access to our systems',
                    'Interfere with or disrupt the service',
                    'Upload malicious content',
                  ],
                ),
                _buildSection(
                  context,
                  '4. Payment and Refunds',
                  null,
                  subsections: [
                    (
                      'Subscription Plans',
                      'We offer Free, Light, and Premium subscription tiers with different features and limits.'
                    ),
                    (
                      'Billing',
                      'Paid subscriptions are billed monthly or annually. You can cancel at any time.'
                    ),
                    (
                      'Refunds',
                      'We offer refunds within 7 days of purchase if you are not satisfied with the service.'
                    ),
                  ],
                ),
                _buildSection(
                  context,
                  '5. Data and Privacy',
                  'Your data is stored securely. We do not sell your personal information. See our Privacy Policy for details.',
                ),
                _buildSection(
                  context,
                  '6. AI Features',
                  null,
                  bullets: [
                    'AI features use third-party services (Anthropic Claude)',
                    'AI-generated content is provided as suggestions only',
                    'We do not guarantee the accuracy of AI outputs',
                  ],
                ),
                _buildSection(
                  context,
                  '7. Intellectual Property',
                  'You retain ownership of your content. We retain ownership of the service and its features.',
                ),
                _buildSection(
                  context,
                  '8. Limitation of Liability',
                  'Flow Tasks is provided "as is" without warranties. We are not liable for any damages arising from your use of the service.',
                ),
                _buildSection(
                  context,
                  '9. Changes to Terms',
                  'We may update these terms from time to time. Continued use of the service constitutes acceptance of the updated terms.',
                ),
                _buildSection(
                  context,
                  '10. Contact',
                  'For questions about these terms, contact us at support@flowtasks.ai',
                ),
                const SizedBox(height: FlowSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    String? content, {
    List<String>? bullets,
    List<(String, String)>? subsections,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FlowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: FlowSpacing.sm),
          if (content != null) Text(content),
          if (bullets != null)
            ...bullets.map((b) => Padding(
                  padding: const EdgeInsets.only(left: FlowSpacing.md, top: FlowSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('\u2022 '),
                      Expanded(child: Text(b)),
                    ],
                  ),
                )),
          if (subsections != null)
            ...subsections.map((s) => Padding(
                  padding: const EdgeInsets.only(top: FlowSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.$1,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: FlowSpacing.xs),
                      Text(s.$2),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
