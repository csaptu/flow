import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
        ),
        title: const Text('Privacy Policy'),
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
                  'Privacy Policy',
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
                  'This policy describes how Flow Tasks collects, uses, and protects your personal information.',
                ),
                const SizedBox(height: FlowSpacing.xl),
                _buildSection(
                  context,
                  '1. Information We Collect',
                  null,
                  subsections: [
                    (
                      'Account Information',
                      'When you create an account, we collect your email address and name.'
                    ),
                    (
                      'Task Data',
                      'We store the tasks, descriptions, due dates, and other content you create.'
                    ),
                    (
                      'Usage Data',
                      'We collect information about how you use the service, including features used and time spent.'
                    ),
                  ],
                ),
                _buildSection(
                  context,
                  '2. How We Use Your Information',
                  null,
                  bullets: [
                    'To provide and improve our service',
                    'To personalize your experience',
                    'To process payments and manage subscriptions',
                    'To send important service updates',
                    'To provide AI-powered features',
                  ],
                ),
                _buildSection(
                  context,
                  '3. AI Processing',
                  'When you use AI features, your task content is sent to our AI provider (Anthropic) for processing. This data is:',
                  bullets: [
                    'Used only to generate responses for your request',
                    'Not used to train AI models',
                    'Not stored by the AI provider after processing',
                  ],
                ),
                _buildSection(
                  context,
                  '4. Data Storage and Security',
                  null,
                  bullets: [
                    'Your data is stored on secure servers (Railway, PostgreSQL)',
                    'We use encryption for data in transit (HTTPS)',
                    'Passwords are hashed and never stored in plain text',
                    'We implement industry-standard security practices',
                  ],
                ),
                _buildSection(
                  context,
                  '5. Data Sharing',
                  'We do not sell your personal information. We may share data with:',
                  bullets: [
                    'Service providers who help operate our service',
                    'Law enforcement when required by law',
                    'Other parties with your explicit consent',
                  ],
                ),
                _buildSection(
                  context,
                  '6. Your Rights',
                  'You have the right to:',
                  bullets: [
                    'Access your personal data',
                    'Export your data',
                    'Delete your account and data',
                    'Opt out of marketing communications',
                  ],
                ),
                _buildSection(
                  context,
                  '7. Cookies and Tracking',
                  'We use essential cookies to maintain your session. We do not use third-party tracking cookies.',
                ),
                _buildSection(
                  context,
                  '8. Data Retention',
                  'We retain your data while your account is active. After account deletion, data is permanently removed within 30 days.',
                ),
                _buildSection(
                  context,
                  '9. Children\'s Privacy',
                  'Our service is not intended for children under 13. We do not knowingly collect data from children.',
                ),
                _buildSection(
                  context,
                  '10. Changes to This Policy',
                  'We may update this policy from time to time. We will notify you of significant changes via email.',
                ),
                _buildSection(
                  context,
                  '11. Contact Us',
                  'For privacy questions or data requests, contact us at privacy@flowtasks.ai',
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
