-- Re-add archived columns if needed (rollback)
ALTER TABLE task_groups
ADD COLUMN archived BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN archived_at TIMESTAMPTZ;

CREATE INDEX idx_task_groups_archived ON task_groups(user_id, archived) WHERE deleted_at IS NULL;
