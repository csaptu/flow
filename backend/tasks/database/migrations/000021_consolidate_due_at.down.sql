-- Revert: split due_at back into due_date (DATE) and due_time (TIME)

-- Drop index
DROP INDEX IF EXISTS idx_tasks_due_at;

-- Add back old columns
ALTER TABLE tasks ADD COLUMN due_date DATE;
ALTER TABLE tasks ADD COLUMN due_time TIME;

-- Migrate data back
UPDATE tasks SET
  due_date = due_at::date,
  due_time = CASE
    WHEN has_due_time = true THEN due_at::time
    ELSE NULL
  END
WHERE due_at IS NOT NULL;

-- Drop new columns
ALTER TABLE tasks DROP COLUMN due_at;
ALTER TABLE tasks DROP COLUMN has_due_time;
