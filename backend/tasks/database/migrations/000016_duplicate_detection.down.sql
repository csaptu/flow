-- Remove duplicate detection fields from tasks
ALTER TABLE tasks DROP COLUMN IF EXISTS duplicate_of;
ALTER TABLE tasks DROP COLUMN IF EXISTS duplicate_resolved;
