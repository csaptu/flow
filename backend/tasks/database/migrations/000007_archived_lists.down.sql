-- Remove archived columns from task_groups
DROP INDEX IF EXISTS idx_task_groups_archived;

ALTER TABLE task_groups
DROP COLUMN IF EXISTS archived_at,
DROP COLUMN IF EXISTS archived;
