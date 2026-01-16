-- AI Usage Tracking for rate limiting by tier

-- User subscription tiers
CREATE TYPE user_tier AS ENUM ('free', 'light', 'premium');

-- AI feature types for tracking
CREATE TYPE ai_feature AS ENUM (
    'clean_title',
    'clean_description',
    'smart_due_date',
    'reminder',
    'decompose',
    'complexity',
    'entity_extraction',
    'recurring_detection',
    'auto_group',
    'draft_email',
    'draft_calendar',
    'send_email',
    'send_calendar'
);

-- Daily AI usage tracking
CREATE TABLE ai_usage (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    feature ai_feature NOT NULL,
    used_at DATE NOT NULL DEFAULT CURRENT_DATE,
    count INTEGER NOT NULL DEFAULT 1,

    -- Unique constraint: one row per user per feature per day
    CONSTRAINT ai_usage_unique UNIQUE (user_id, feature, used_at)
);

CREATE INDEX idx_ai_usage_user_date ON ai_usage(user_id, used_at);

-- User tier info (could also be in shared service, but keeping here for simplicity)
-- In production, this would likely come from a billing/subscription service
CREATE TABLE user_subscriptions (
    user_id UUID PRIMARY KEY,
    tier user_tier NOT NULL DEFAULT 'free',
    started_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    stripe_customer_id VARCHAR(255),
    stripe_subscription_id VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- AI processing queue for async/batch processing
CREATE TABLE ai_processing_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    features TEXT[] NOT NULL, -- Array of features to process
    status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    result JSONB,
    error TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

CREATE INDEX idx_ai_queue_status ON ai_processing_queue(status) WHERE status = 'pending';

-- Draft storage for email/calendar drafts
CREATE TABLE ai_drafts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    draft_type VARCHAR(20) NOT NULL, -- 'email' or 'calendar'
    content JSONB NOT NULL, -- {to, subject, body} for email, {title, start, end, attendees} for calendar
    status VARCHAR(20) NOT NULL DEFAULT 'draft', -- draft, approved, sent, cancelled
    created_at TIMESTAMPTZ DEFAULT NOW(),
    sent_at TIMESTAMPTZ
);

CREATE INDEX idx_ai_drafts_user ON ai_drafts(user_id, status);
