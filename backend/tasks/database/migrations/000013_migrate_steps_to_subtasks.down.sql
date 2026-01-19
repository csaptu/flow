-- Reverse migration: re-add ai_steps columns
-- Note: This does NOT restore the original data, only the schema

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS ai_steps JSONB DEFAULT '[]';
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS ai_decomposed BOOLEAN DEFAULT FALSE;

-- Delete subtasks that were created from migration (depth = 1)
-- This is destructive - the original step data cannot be fully recovered
DELETE FROM tasks WHERE depth = 1 AND parent_id IS NOT NULL;
