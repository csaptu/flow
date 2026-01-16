-- Remove data column
ALTER TABLE task_attachments DROP COLUMN IF EXISTS data;

-- Restore original constraint
ALTER TABLE task_attachments DROP CONSTRAINT IF EXISTS valid_file_metadata;
ALTER TABLE task_attachments ADD CONSTRAINT valid_file_metadata CHECK (
    (type = 'link') OR (mime_type IS NOT NULL AND size_bytes IS NOT NULL)
);

-- Restore NOT NULL on url
ALTER TABLE task_attachments ALTER COLUMN url SET NOT NULL;
