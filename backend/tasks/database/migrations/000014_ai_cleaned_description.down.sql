-- Remove ai_cleaned_description column
ALTER TABLE tasks DROP COLUMN IF EXISTS ai_cleaned_description;
