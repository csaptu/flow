-- Revert: Restore old schema structure
-- Note: Data migration is lossy - we can restore structure but not all original data

-- Step 1: Add back the removed columns
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS ai_summary VARCHAR(255);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS user_input_title VARCHAR(500);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS user_input_description TEXT;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS original_text TEXT;

-- Step 2: Store current text values temporarily
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS ai_cleaned_title_temp VARCHAR(500);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS ai_cleaned_description_temp TEXT;

UPDATE tasks SET ai_cleaned_title_temp = ai_cleaned_title;
UPDATE tasks SET ai_cleaned_description_temp = ai_cleaned_description;

-- Step 3: Drop text columns
ALTER TABLE tasks DROP COLUMN IF EXISTS ai_cleaned_title;
ALTER TABLE tasks DROP COLUMN IF EXISTS ai_cleaned_description;

-- Step 4: Add back boolean columns
ALTER TABLE tasks ADD COLUMN ai_cleaned_title BOOL NOT NULL DEFAULT false;
ALTER TABLE tasks ADD COLUMN ai_cleaned_description BOOL NOT NULL DEFAULT false;

-- Step 5: Migrate data back - if ai_cleaned_title_temp has value, set flag and copy to ai_summary
UPDATE tasks
SET ai_cleaned_title = true, ai_summary = ai_cleaned_title_temp
WHERE ai_cleaned_title_temp IS NOT NULL;

UPDATE tasks
SET ai_cleaned_description = true
WHERE ai_cleaned_description_temp IS NOT NULL;

-- Step 6: Clean up temp columns
ALTER TABLE tasks DROP COLUMN IF EXISTS ai_cleaned_title_temp;
ALTER TABLE tasks DROP COLUMN IF EXISTS ai_cleaned_description_temp;
