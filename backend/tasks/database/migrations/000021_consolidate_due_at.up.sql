-- Consolidate due_date (DATE) and due_time (TIME) into due_at (TIMESTAMPTZ) + has_due_time (BOOLEAN)
-- This enables proper timezone support while maintaining date-only vs datetime distinction

-- Add new columns
ALTER TABLE tasks ADD COLUMN due_at TIMESTAMPTZ;
ALTER TABLE tasks ADD COLUMN has_due_time BOOLEAN DEFAULT false;

-- Migrate data: combine due_date and due_time into due_at
UPDATE tasks SET
  due_at = CASE
    WHEN due_date IS NOT NULL AND due_time IS NOT NULL THEN
      (due_date + due_time)::timestamp AT TIME ZONE 'UTC'
    WHEN due_date IS NOT NULL THEN
      due_date::timestamp AT TIME ZONE 'UTC'
    ELSE NULL
  END,
  has_due_time = (due_time IS NOT NULL)
WHERE due_date IS NOT NULL;

-- Drop old columns
ALTER TABLE tasks DROP COLUMN due_date;
ALTER TABLE tasks DROP COLUMN due_time;

-- Create index for efficient due date queries
CREATE INDEX idx_tasks_due_at ON tasks(due_at) WHERE due_at IS NOT NULL AND deleted_at IS NULL;
