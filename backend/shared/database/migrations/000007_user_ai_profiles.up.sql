-- User AI Profiles table
-- Stores per-user AI context information for personalized assistance
CREATE TABLE user_ai_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,

    -- Editable fields (admin can modify)
    identity_summary TEXT,           -- Who they are
    communication_style TEXT,        -- Tone, verbosity preferences
    work_context TEXT,               -- Job, projects, responsibilities
    personal_context TEXT,           -- Family, hobbies, personal life
    social_graph TEXT,               -- Key people mentioned
    locations_context TEXT,          -- Frequent locations
    routine_patterns TEXT,           -- Daily/weekly patterns
    task_style_preferences TEXT,     -- How they like tasks structured
    goals_and_priorities TEXT,       -- Stated goals

    -- Auto-generated fields (refreshed by AI)
    recent_activity_summary TEXT,    -- Last 7 days summary
    current_focus TEXT,              -- Current project/focus
    upcoming_commitments TEXT,       -- Near-term deadlines

    -- Refresh tracking
    last_refreshed_at TIMESTAMPTZ DEFAULT NOW(),
    refresh_trigger VARCHAR(50),     -- 'manual', 'scheduled', 'task_milestone'
    tasks_since_refresh INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for refresh queries
CREATE INDEX idx_user_ai_profiles_refresh ON user_ai_profiles(last_refreshed_at, tasks_since_refresh);

-- Seed system first context in ai_prompt_configs
INSERT INTO ai_prompt_configs (key, value, description) VALUES
('system_first_context',
'You are Flow AI, an assistant for Flow Tasks - a personal task management app.

PRINCIPLES:
- Be concise and actionable
- Respect user privacy
- Focus on productivity

RESTRICTIONS (Universal):
- No violence, weapons, harm instructions
- No self-harm or suicide content
- No pornographic/explicit content
- No illegal activities assistance
- No medical/legal/financial advice (suggest professionals)

RESTRICTIONS (Regional):
- Vietnam/China: No political commentary, no criticism of government/leaders
- Monarchies (Thailand, Saudi Arabia, UAE, etc.): No disrespect to royal family

OUTPUT: Always respond in valid JSON when requested.',
'System prompt - First Context (editable in Admin)')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, description = EXCLUDED.description;
