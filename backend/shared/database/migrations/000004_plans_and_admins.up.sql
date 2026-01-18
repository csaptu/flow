-- shared_db: Subscription plans (single source of truth)
CREATE TABLE subscription_plans (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    tier subscription_tier NOT NULL,

    -- Pricing
    price_monthly_cents INTEGER NOT NULL,
    price_yearly_cents INTEGER,
    currency VARCHAR(3) DEFAULT 'USD',

    -- Features (JSON array of feature strings)
    features JSONB DEFAULT '[]',

    -- Provider-specific IDs
    paddle_price_id VARCHAR(100),
    apple_product_id VARCHAR(100),
    google_product_id VARCHAR(100),

    -- Limits
    ai_calls_per_day INTEGER DEFAULT 0,

    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default plans
INSERT INTO subscription_plans (id, name, tier, price_monthly_cents, price_yearly_cents, ai_calls_per_day, features) VALUES
('free', 'Free', 'free', 0, 0, 5, '["Basic task management", "Up to 100 tasks", "5 AI calls per day"]'),
('light_monthly', 'Light Monthly', 'light', 499, NULL, 50, '["Unlimited tasks", "50 AI calls per day", "Priority support"]'),
('light_yearly', 'Light Yearly', 'light', 399, 4788, 50, '["Unlimited tasks", "50 AI calls per day", "Priority support", "2 months free"]'),
('premium_monthly', 'Premium Monthly', 'premium', 999, NULL, -1, '["Unlimited tasks", "Unlimited AI calls", "Priority support", "Advanced analytics"]'),
('premium_yearly', 'Premium Yearly', 'premium', 833, 9996, -1, '["Unlimited tasks", "Unlimited AI calls", "Priority support", "Advanced analytics", "2 months free"]');

CREATE INDEX idx_subscription_plans_tier ON subscription_plans(tier);
CREATE INDEX idx_subscription_plans_active ON subscription_plans(is_active);

-- Admin users (single source of truth)
CREATE TABLE admin_users (
    email VARCHAR(255) PRIMARY KEY,
    role VARCHAR(50) DEFAULT 'admin',
    added_at TIMESTAMPTZ DEFAULT NOW(),
    added_by VARCHAR(255)
);

-- Insert default admins
INSERT INTO admin_users (email, role) VALUES
('tupham@prepedu.com', 'super_admin');

CREATE INDEX idx_admin_users_role ON admin_users(role);
