-- Extend task_groups for nested lists (Bear-style #List/Sublist)
ALTER TABLE task_groups
ADD COLUMN parent_id UUID REFERENCES task_groups(id) ON DELETE CASCADE,
ADD COLUMN depth SMALLINT NOT NULL DEFAULT 0,
ADD COLUMN task_count INTEGER NOT NULL DEFAULT 0;

-- Constraint: max depth of 1 (2 levels: List/Sublist)
ALTER TABLE task_groups
ADD CONSTRAINT task_group_max_depth CHECK (depth <= 1);

-- Unique constraint: list name must be unique per user at each level
ALTER TABLE task_groups
ADD CONSTRAINT task_group_unique_name UNIQUE (user_id, parent_id, name);

-- Index for finding sublists
CREATE INDEX idx_task_groups_parent ON task_groups(parent_id) WHERE deleted_at IS NULL;

-- GIN index for tag searches (used for list: prefixed tags)
CREATE INDEX idx_tasks_tags ON tasks USING GIN(tags) WHERE deleted_at IS NULL;
