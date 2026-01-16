-- Rollback orders and subscription management

DROP TABLE IF EXISTS admin_users;
DROP TABLE IF EXISTS orders;

ALTER TABLE user_subscriptions
DROP COLUMN IF EXISTS plan_id,
DROP COLUMN IF EXISTS provider,
DROP COLUMN IF EXISTS provider_subscription_id,
DROP COLUMN IF EXISTS cancelled_at,
DROP COLUMN IF EXISTS cancel_reason;

DROP TABLE IF EXISTS subscription_plans;

DROP TYPE IF EXISTS payment_provider;
DROP TYPE IF EXISTS order_status;
