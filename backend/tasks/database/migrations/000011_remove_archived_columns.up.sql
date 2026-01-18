-- Remove archived columns from task_groups
-- Lists are now hashtag-based only, no CRUD archive functionality
DROP INDEX IF EXISTS idx_task_groups_archived;

ALTER TABLE task_groups
DROP COLUMN IF EXISTS archived_at,
DROP COLUMN IF EXISTS archived;
