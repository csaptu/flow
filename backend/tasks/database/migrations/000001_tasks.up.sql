-- tasks_db: Tasks table
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE task_status AS ENUM ('pending', 'in_progress', 'completed', 'cancelled', 'archived');
CREATE TYPE task_priority AS ENUM ('0', '1', '2', '3', '4'); -- none, low, medium, high, urgent

CREATE TABLE task_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    icon VARCHAR(50),
    color VARCHAR(20),
    ai_created BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_task_groups_user ON task_groups(user_id) WHERE deleted_at IS NULL;

CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,

    -- Content
    title VARCHAR(500) NOT NULL,
    description TEXT,
    original_text TEXT,

    -- AI-generated content
    ai_summary VARCHAR(255),
    ai_steps JSONB DEFAULT '[]',

    -- Status and priority
    status task_status NOT NULL DEFAULT 'pending',
    priority SMALLINT NOT NULL DEFAULT 0,
    complexity SMALLINT DEFAULT 0, -- 1-10 scale

    -- Dates
    start_date TIMESTAMPTZ,
    due_date TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    -- Tags
    tags TEXT[] DEFAULT '{}',

    -- Hierarchy (max 2 layers)
    parent_id UUID REFERENCES tasks(id) ON DELETE CASCADE,
    depth SMALLINT NOT NULL DEFAULT 0,

    -- Recurrence
    recurrence_rule VARCHAR(255),
    last_occurrence TIMESTAMPTZ,
    next_occurrence TIMESTAMPTZ,

    -- AI feature flags
    ai_cleaned_title BOOLEAN DEFAULT FALSE,
    ai_extracted_due BOOLEAN DEFAULT FALSE,
    ai_decomposed BOOLEAN DEFAULT FALSE,

    -- Entities (people, places, etc.)
    entities JSONB DEFAULT '[]',

    -- Grouping
    group_id UUID REFERENCES task_groups(id) ON DELETE SET NULL,
    group_name VARCHAR(255),

    -- Project promotion
    promoted_to_project UUID,

    -- Sync fields
    version INTEGER NOT NULL DEFAULT 1,
    device_id VARCHAR(255),
    synced_at TIMESTAMPTZ,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    -- Constraint: max depth of 1 (2 layers total)
    CONSTRAINT task_max_depth CHECK (depth <= 1)
);

CREATE INDEX idx_tasks_user ON tasks(user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_tasks_user_status ON tasks(user_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_tasks_user_due ON tasks(user_id, due_date) WHERE deleted_at IS NULL AND status != 'completed';
CREATE INDEX idx_tasks_parent ON tasks(parent_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_tasks_group ON tasks(group_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_tasks_promoted ON tasks(promoted_to_project) WHERE promoted_to_project IS NOT NULL;

-- For syncing: find tasks updated after a certain time
CREATE INDEX idx_tasks_sync ON tasks(user_id, updated_at) WHERE deleted_at IS NULL;
