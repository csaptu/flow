-- Remove GIN index
DROP INDEX IF EXISTS idx_tasks_tags;

-- Remove sublists index
DROP INDEX IF EXISTS idx_task_groups_parent;

-- Remove constraints
ALTER TABLE task_groups DROP CONSTRAINT IF EXISTS task_group_unique_name;
ALTER TABLE task_groups DROP CONSTRAINT IF EXISTS task_group_max_depth;

-- Remove columns
ALTER TABLE task_groups DROP COLUMN IF EXISTS task_count;
ALTER TABLE task_groups DROP COLUMN IF EXISTS depth;
ALTER TABLE task_groups DROP COLUMN IF EXISTS parent_id;
