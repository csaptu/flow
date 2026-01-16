-- Add data column for storing file content as BLOB
ALTER TABLE task_attachments ADD COLUMN data BYTEA;

-- Update the check constraint to allow files without URL when data is present
ALTER TABLE task_attachments DROP CONSTRAINT IF EXISTS valid_file_metadata;
ALTER TABLE task_attachments ADD CONSTRAINT valid_file_metadata CHECK (
    (type = 'link') OR
    (mime_type IS NOT NULL AND size_bytes IS NOT NULL AND (url IS NOT NULL OR data IS NOT NULL))
);

-- Allow null URL for files stored in database
ALTER TABLE task_attachments ALTER COLUMN url DROP NOT NULL;
