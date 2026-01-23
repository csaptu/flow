-- Split due_date timestamp into separate date and time columns
-- due_date becomes DATE only, due_time is new TIME column (nullable)

-- Add new due_time column
ALTER TABLE tasks ADD COLUMN due_time TIME;

-- Extract time from existing due_date (only if not midnight, meaning a specific time was set)
UPDATE tasks
SET due_time = due_date::time
WHERE due_date IS NOT NULL
  AND (EXTRACT(HOUR FROM due_date) != 0 OR EXTRACT(MINUTE FROM due_date) != 0);

-- Convert due_date from timestamp to date (drops time portion)
ALTER TABLE tasks ALTER COLUMN due_date TYPE DATE USING due_date::date;
