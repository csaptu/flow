-- Create attachment type enum
CREATE TYPE attachment_type AS ENUM ('link', 'document', 'image');

-- Create attachments table
CREATE TABLE task_attachments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    type attachment_type NOT NULL,
    name VARCHAR(255) NOT NULL,
    url TEXT NOT NULL,                    -- S3 URL for files, original URL for links
    mime_type VARCHAR(100),
    size_bytes BIGINT,
    thumbnail_url TEXT,                   -- For images/links with previews
    metadata JSONB DEFAULT '{}',          -- Link preview data, dimensions, etc.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    -- Links don't need mime_type/size_bytes, but files do
    CONSTRAINT valid_file_metadata CHECK (
        (type = 'link') OR (mime_type IS NOT NULL AND size_bytes IS NOT NULL)
    )
);

-- Index for finding attachments by task
CREATE INDEX idx_attachments_task ON task_attachments(task_id) WHERE deleted_at IS NULL;

-- Index for finding attachments by user (for quota tracking)
CREATE INDEX idx_attachments_user ON task_attachments(user_id) WHERE deleted_at IS NULL;
