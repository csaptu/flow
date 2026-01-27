-- Page contents for public pages (terms, privacy, etc.)
CREATE TABLE IF NOT EXISTS page_contents (
    key VARCHAR(50) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by VARCHAR(255)
);

-- Insert default content
INSERT INTO page_contents (key, title, content) VALUES
('terms', 'Terms of Service', '# Terms of Service

**Last updated: January 2025**

Welcome to Flow Tasks. By using our service, you agree to these terms.

## 1. Service Description

Flow Tasks is a task management application with AI-powered features to help you organize and complete your work efficiently.

## 2. User Accounts

- You must provide accurate information when creating an account
- You are responsible for maintaining the security of your account
- You must be at least 13 years old to use this service

## 3. Acceptable Use

You agree not to:
- Use the service for any illegal purposes
- Attempt to gain unauthorized access to our systems
- Interfere with or disrupt the service
- Upload malicious content

## 4. Payment and Refunds

### Subscription Plans
We offer Free, Light, and Premium subscription tiers. Paid subscriptions are billed monthly or annually.

### 15-Day Money-Back Guarantee
**We offer a 15-day money-back guarantee for any reason.** If you are not satisfied with your paid subscription, contact us within 15 days of your purchase for a full refund. No questions asked.

### Cancellation
You may cancel your subscription at any time. Access continues until the end of your billing period.

## 5. Intellectual Property

- You retain ownership of your content
- We retain ownership of the Flow Tasks service and technology
- AI-generated suggestions are provided as-is without warranty

## 6. Privacy

Your privacy is important to us. Please review our Privacy Policy for details on how we handle your data.

## 7. Limitation of Liability

Flow Tasks is provided "as is" without warranties. We are not liable for any indirect, incidental, or consequential damages.

## 8. Changes to Terms

We may update these terms from time to time. Continued use of the service constitutes acceptance of updated terms.

## 9. Contact

For questions about these terms, contact us at support@flowtasks.ai'),

('privacy', 'Privacy Policy', '# Privacy Policy

**Last updated: January 2025**

Flow Tasks ("we", "our", or "us") is committed to protecting your privacy. This policy explains how we collect, use, and protect your information.

## 1. Information We Collect

### Account Information
- Email address
- Name
- Password (encrypted)

### Task Data
- Tasks you create
- Task descriptions and metadata
- Attachments you upload

### Usage Information
- App usage patterns
- Feature usage statistics
- Device information

### AI Processing
- Task content may be processed by AI to provide features like:
  - Title cleaning
  - Entity extraction
  - Due date suggestions
  - Task decomposition

## 2. How We Use Your Information

We use your information to:
- Provide and improve our services
- Process your tasks and data
- Send important service updates
- Provide customer support
- Analyze usage patterns to improve the app

## 3. Data Storage and Security

- Your data is stored securely on servers in the United States
- We use encryption for data in transit and at rest
- We implement industry-standard security measures
- Passwords are hashed and never stored in plain text

## 4. Third-Party Services

We may use third-party services for:
- **Authentication**: Google Sign-In, Apple Sign-In
- **AI Processing**: Anthropic Claude, OpenAI (task content may be sent to these services)
- **Payments**: Paddle (payment information is handled by Paddle)
- **Analytics**: Anonymous usage statistics

## 5. Data Sharing

We do not sell your personal information. We may share data:
- With AI providers to process your tasks (content only, not personal info)
- When required by law
- To protect our rights or safety

## 6. Your Rights

You have the right to:
- Access your data
- Export your data
- Delete your account and data
- Opt out of AI features

## 7. Data Retention

- Active account data is retained while your account is active
- Deleted tasks are permanently removed after 30 days
- If you delete your account, all data is removed within 30 days

## 8. Children''s Privacy

Flow Tasks is not intended for children under 13. We do not knowingly collect data from children under 13.

## 9. Changes to This Policy

We may update this policy from time to time. We will notify you of significant changes via email or in-app notification.

## 10. Contact Us

For privacy-related questions or requests, contact us at:
- Email: privacy@flowtasks.ai

## 11. California Residents

If you are a California resident, you have additional rights under the CCPA including:
- Right to know what data we collect
- Right to delete your data
- Right to opt out of data sales (we do not sell data)')
ON CONFLICT (key) DO NOTHING;
