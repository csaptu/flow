-- Rollback: Recreate duplicate tables (not recommended - use shared repository instead)

-- Recreate types
CREATE TYPE payment_provider AS ENUM ('paddle', 'apple_iap', 'google_play', 'manual');
CREATE TYPE order_status AS ENUM ('pending', 'completed', 'failed', 'refunded', 'cancelled');

-- Recreate user_subscriptions
CREATE TABLE user_subscriptions (
    user_id UUID PRIMARY KEY,
    tier user_tier NOT NULL DEFAULT 'free',
    plan_id VARCHAR(50),
    provider payment_provider,
    provider_subscription_id VARCHAR(255),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    stripe_customer_id VARCHAR(255),
    stripe_subscription_id VARCHAR(255),
    cancelled_at TIMESTAMPTZ,
    cancel_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Recreate subscription_plans
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

-- Recreate admin_users
CREATE TABLE admin_users (
    email VARCHAR(255) PRIMARY KEY,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    added_by VARCHAR(255)
);

-- Recreate orders
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
