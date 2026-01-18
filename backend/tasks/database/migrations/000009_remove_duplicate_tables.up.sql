-- Migration: Remove duplicate tables that now live in shared database
-- These tables are now accessed via the shared repository (monorepo internal API)

-- Drop orders table (now in shared database)
DROP TABLE IF EXISTS orders;

-- Drop user_subscriptions FIRST (has FK to subscription_plans)
DROP TABLE IF EXISTS user_subscriptions;

-- Drop subscription_plans table (now in shared database)
DROP TABLE IF EXISTS subscription_plans;

-- Drop admin_users table (now in shared database)
DROP TABLE IF EXISTS admin_users;

-- Drop payment_provider type if it exists (from 000006)
DROP TYPE IF EXISTS payment_provider;

-- Drop order_status type if it exists (from 000006)
DROP TYPE IF EXISTS order_status;

-- Note: user_tier type is kept as it may still be used for reference,
-- but the actual subscription tier is now retrieved from shared repository
