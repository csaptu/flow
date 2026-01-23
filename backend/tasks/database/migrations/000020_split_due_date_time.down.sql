-- Revert: Combine due_date and due_time back into single timestamp
-- Convert due_date back to timestamp and combine with due_time

ALTER TABLE tasks ALTER COLUMN due_date TYPE TIMESTAMP USING
  CASE
    WHEN due_time IS NOT NULL THEN (due_date + due_time)::timestamp
    ELSE due_date::timestamp
  END;

DROP COLUMN IF EXISTS due_time;
