-- Orders and subscription management

-- Order status enum
CREATE TYPE order_status AS ENUM ('pending', 'completed', 'failed', 'refunded', 'cancelled');

-- Payment provider enum
CREATE TYPE payment_provider AS ENUM ('paddle', 'apple_iap', 'google_play', 'manual');

-- Subscription plans with pricing
CREATE TABLE subscription_plans (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    tier user_tier NOT NULL,
    price_monthly DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    paddle_price_id VARCHAR(100),
    apple_product_id VARCHAR(100),
    google_product_id VARCHAR(100),
    features JSONB NOT NULL DEFAULT '[]',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default plans
INSERT INTO subscription_plans (id, name, tier, price_monthly, features) VALUES
('free', 'Free', 'free', 0, '["Clean Title (20/day)", "Clean Description (20/day)", "Smart Due Dates", "Reminders"]'),
('light_monthly', 'Light', 'light', 4.99, '["All Free features (unlimited)", "AI Decompose (30/day)", "Complexity scoring", "Entity extraction", "Auto-grouping (10/day)", "Draft emails (10/day)", "Draft calendar (10/day)"]'),
('premium_monthly', 'Premium', 'premium', 9.99, '["All Light features (unlimited)", "Priority support", "Early access to new features"]');

-- Orders table
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    plan_id VARCHAR(50) NOT NULL REFERENCES subscription_plans(id),
    provider payment_provider NOT NULL,
    provider_order_id VARCHAR(255),
    provider_subscription_id VARCHAR(255),
    amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    status order_status NOT NULL DEFAULT 'pending',
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    refunded_at TIMESTAMPTZ
);

CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_provider ON orders(provider, provider_order_id);

-- Add more fields to user_subscriptions
ALTER TABLE user_subscriptions
ADD COLUMN IF NOT EXISTS plan_id VARCHAR(50) REFERENCES subscription_plans(id),
ADD COLUMN IF NOT EXISTS provider payment_provider,
ADD COLUMN IF NOT EXISTS provider_subscription_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS cancel_reason TEXT;

-- Admin users table (separate from shared service users for task service isolation)
CREATE TABLE admin_users (
    email VARCHAR(255) PRIMARY KEY,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    added_by VARCHAR(255)
);

-- Insert initial admin
INSERT INTO admin_users (email) VALUES ('quangtu.pham@gmail.com');
