-- Remove sort_order field
DROP INDEX IF EXISTS idx_tasks_parent_order;
ALTER TABLE tasks DROP COLUMN IF EXISTS sort_order;
