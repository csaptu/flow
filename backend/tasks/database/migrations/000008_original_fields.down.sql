-- Remove original title/description fields
ALTER TABLE tasks DROP COLUMN IF EXISTS skip_auto_cleanup;
ALTER TABLE tasks DROP COLUMN IF EXISTS original_description;
ALTER TABLE tasks DROP COLUMN IF EXISTS original_title;
