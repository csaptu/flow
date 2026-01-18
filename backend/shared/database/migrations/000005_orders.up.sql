-- shared_db: Orders table for purchase tracking

CREATE TYPE order_status AS ENUM ('pending', 'completed', 'failed', 'refunded', 'cancelled');

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id VARCHAR(50) NOT NULL REFERENCES subscription_plans(id),

    provider payment_provider NOT NULL,
    provider_order_id VARCHAR(255),
    provider_subscription_id VARCHAR(255),

    amount_cents INTEGER NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',

    status order_status NOT NULL DEFAULT 'pending',
    metadata JSONB,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    refunded_at TIMESTAMPTZ
);

CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_provider ON orders(provider, provider_order_id);
CREATE INDEX idx_orders_created ON orders(created_at DESC);
