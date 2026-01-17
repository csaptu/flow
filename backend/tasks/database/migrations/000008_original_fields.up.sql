-- Add original title/description fields for AI cleanup revert functionality
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS original_title VARCHAR(500);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS original_description TEXT;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS skip_auto_cleanup BOOLEAN NOT NULL DEFAULT FALSE;

-- Optional: migrate data from original_text to original_title if needed
-- UPDATE tasks SET original_title = original_text WHERE original_text IS NOT NULL AND original_title IS NULL;
