-- Restore task_groups table and group_id column

-- Recreate task_groups table
CREATE TABLE task_groups (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    name VARCHAR(100) NOT NULL,
    icon VARCHAR(50),
    color VARCHAR(7),
    parent_id UUID REFERENCES task_groups(id) ON DELETE CASCADE,
    depth SMALLINT NOT NULL DEFAULT 0,
    task_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT task_group_max_depth CHECK (depth <= 1)
);

-- Add indexes
CREATE INDEX idx_task_groups_user ON task_groups(user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_task_groups_parent ON task_groups(parent_id) WHERE deleted_at IS NULL;

-- Re-add group_id column to tasks
ALTER TABLE tasks ADD COLUMN group_id UUID REFERENCES task_groups(id) ON DELETE SET NULL;
