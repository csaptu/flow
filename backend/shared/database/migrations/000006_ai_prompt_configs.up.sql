-- AI Prompt Configurations table
-- Stores configurable instruction strings for AI features
CREATE TABLE ai_prompt_configs (
    key VARCHAR(100) PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by VARCHAR(255)
);

-- Create index for faster lookups
CREATE INDEX idx_ai_prompt_configs_updated_at ON ai_prompt_configs(updated_at);

-- Seed default values
INSERT INTO ai_prompt_configs (key, value, description) VALUES
('clean_title_instruction', 'Concise, action-oriented title (max 10 words)', 'Instruction for cleaned title format'),
('summary_instruction', 'Brief summary if description is long (max 20 words)', 'Instruction for task summary'),
('complexity_instruction', '1-10 scale (1=trivial like ''buy milk'', 10=complex multi-step project)', 'Instruction for complexity rating'),
('due_date_instruction', 'ISO 8601 date if mentioned (e.g., ''tomorrow'' = next day, ''next week'' = next Monday)', 'Instruction for due date extraction'),
('reminder_instruction', 'ISO 8601 datetime if ''remind me'' or similar phrase found', 'Instruction for reminder detection'),
('entities_instruction', 'person|place|organization', 'Entity types to extract'),
('recurrence_instruction', 'RRULE string if recurring pattern detected (e.g., ''every Monday'')', 'Instruction for recurrence detection'),
('suggested_group_instruction', 'Category suggestion based on content (e.g., ''Work'', ''Shopping'', ''Health'')', 'Instruction for auto-grouping'),
('decompose_step_count', '2-5', 'Number of steps for decomposition'),
('decompose_rules', 'Each step should be a single, concrete action
Steps should be in logical order
Use action verbs (Call, Send, Research, Write, etc.)
Keep each step under 10 words', 'Rules for task decomposition');
