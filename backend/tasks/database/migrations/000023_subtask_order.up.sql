-- Add sort_order field for subtask ordering within a parent
ALTER TABLE tasks ADD COLUMN sort_order INTEGER DEFAULT 0;

-- Create index for efficient ordering queries
CREATE INDEX idx_tasks_parent_order ON tasks(parent_id, sort_order) WHERE parent_id IS NOT NULL AND deleted_at IS NULL;

-- Initialize sort_order for existing subtasks based on created_at
-- This preserves the current ordering (oldest first)
WITH ordered_subtasks AS (
    SELECT id, parent_id,
           ROW_NUMBER() OVER (PARTITION BY parent_id ORDER BY created_at ASC) - 1 as new_order
    FROM tasks
    WHERE parent_id IS NOT NULL AND deleted_at IS NULL
)
UPDATE tasks
SET sort_order = ordered_subtasks.new_order
FROM ordered_subtasks
WHERE tasks.id = ordered_subtasks.id;
