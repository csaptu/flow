-- Remove task_groups table (lists are now derived dynamically from hashtags in task descriptions)

-- First, remove the group_id foreign key and column from tasks
ALTER TABLE tasks DROP COLUMN IF EXISTS group_id;

-- Drop indexes on task_groups
DROP INDEX IF EXISTS idx_task_groups_parent;
DROP INDEX IF EXISTS idx_task_groups_user;

-- Drop task_groups table
DROP TABLE IF EXISTS task_groups;
