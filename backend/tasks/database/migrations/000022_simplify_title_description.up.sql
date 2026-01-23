-- Simplify title/description handling
-- title = user input (always what user writes)
-- ai_cleaned_title = AI cleaned version (text, not bool) - display this if not null
-- ai_cleaned_description = AI cleaned version (text, not bool) - display this if not null

-- Step 1: Add temporary columns to store existing data
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS ai_cleaned_title_new VARCHAR(500);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS ai_cleaned_description_new TEXT;

-- Step 2: Migrate data - if ai_cleaned_title was true, the ai_summary was the cleaned title
-- Copy ai_summary to ai_cleaned_title_new where ai_cleaned_title was true
UPDATE tasks
SET ai_cleaned_title_new = ai_summary
WHERE ai_cleaned_title = true AND ai_summary IS NOT NULL;

-- For ai_cleaned_description, we don't have a separate field for the cleaned text
-- The description field itself contains the cleaned version if ai_cleaned_description was true
-- So we leave ai_cleaned_description_new as null (user will need to re-clean if desired)

-- Step 3: Drop old boolean columns
ALTER TABLE tasks DROP COLUMN IF EXISTS ai_cleaned_title;
ALTER TABLE tasks DROP COLUMN IF EXISTS ai_cleaned_description;

-- Step 4: Rename new columns
ALTER TABLE tasks RENAME COLUMN ai_cleaned_title_new TO ai_cleaned_title;
ALTER TABLE tasks RENAME COLUMN ai_cleaned_description_new TO ai_cleaned_description;

-- Step 5: Remove unused columns
ALTER TABLE tasks DROP COLUMN IF EXISTS ai_summary;
ALTER TABLE tasks DROP COLUMN IF EXISTS user_input_title;
ALTER TABLE tasks DROP COLUMN IF EXISTS user_input_description;
ALTER TABLE tasks DROP COLUMN IF EXISTS original_text;
