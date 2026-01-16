-- Drop indexes
DROP INDEX IF EXISTS idx_attachments_user;
DROP INDEX IF EXISTS idx_attachments_task;

-- Drop table
DROP TABLE IF EXISTS task_attachments;

-- Drop enum
DROP TYPE IF EXISTS attachment_type;
