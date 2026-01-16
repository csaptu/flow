-- Rollback AI usage tracking

DROP TABLE IF EXISTS ai_drafts;
DROP TABLE IF EXISTS ai_processing_queue;
DROP TABLE IF EXISTS user_subscriptions;
DROP TABLE IF EXISTS ai_usage;

DROP TYPE IF EXISTS ai_feature;
DROP TYPE IF EXISTS user_tier;
