-- Revert to the original unique constraint (warning: doesn't handle NULL parent_id correctly)
DROP INDEX IF EXISTS idx_task_groups_unique_root;
DROP INDEX IF EXISTS idx_task_groups_unique_nested;

-- Re-add the original constraint
ALTER TABLE task_groups
ADD CONSTRAINT task_group_unique_name UNIQUE (user_id, parent_id, name);
