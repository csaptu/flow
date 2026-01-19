-- Add ai_cleaned_description flag for tracking AI-cleaned descriptions
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS ai_cleaned_description BOOLEAN NOT NULL DEFAULT FALSE;
