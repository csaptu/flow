-- Fix unique constraint for task_groups to properly handle NULL parent_id
-- PostgreSQL treats NULLs as distinct in regular unique constraints,
-- so we need partial indexes to enforce uniqueness for root-level lists

-- Drop the existing constraint that doesn't handle NULL correctly
ALTER TABLE task_groups DROP CONSTRAINT IF EXISTS task_group_unique_name;

-- Create partial unique index for root-level lists (parent_id IS NULL)
CREATE UNIQUE INDEX IF NOT EXISTS idx_task_groups_unique_root
ON task_groups (user_id, name)
WHERE parent_id IS NULL AND deleted_at IS NULL;

-- Create partial unique index for nested lists (parent_id IS NOT NULL)
CREATE UNIQUE INDEX IF NOT EXISTS idx_task_groups_unique_nested
ON task_groups (user_id, parent_id, name)
WHERE parent_id IS NOT NULL AND deleted_at IS NULL;
