-- shared_db: Subscriptions and payments
CREATE TYPE subscription_tier AS ENUM ('free', 'light', 'premium');
CREATE TYPE payment_provider AS ENUM ('apple', 'google', 'paddle');
CREATE TYPE subscription_status AS ENUM ('active', 'grace_period', 'expired', 'cancelled');

CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Subscription details
    tier subscription_tier NOT NULL DEFAULT 'free',
    status subscription_status NOT NULL DEFAULT 'active',

    -- Payment provider
    provider payment_provider,
    provider_subscription_id VARCHAR(255),
    provider_customer_id VARCHAR(255),

    -- Billing period
    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,

    -- Grace period (payment retry)
    grace_period_end TIMESTAMPTZ,

    -- Cancellation
    cancel_at_period_end BOOLEAN DEFAULT FALSE,
    cancelled_at TIMESTAMPTZ,

    -- Receipt validation
    latest_receipt TEXT,
    receipt_validated_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id)
);

CREATE INDEX idx_subscriptions_provider ON subscriptions(provider, provider_subscription_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
CREATE INDEX idx_subscriptions_period_end ON subscriptions(current_period_end);

-- Payment history for auditing
CREATE TABLE payment_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES subscriptions(id),

    provider payment_provider NOT NULL,
    provider_transaction_id VARCHAR(255),

    amount_cents INTEGER NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',

    tier subscription_tier NOT NULL,
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ,

    status VARCHAR(50) NOT NULL,
    failure_reason TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_payment_history_user ON payment_history(user_id);
