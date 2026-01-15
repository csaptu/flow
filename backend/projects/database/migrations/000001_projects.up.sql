-- projects_db: Projects and WBS tables
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE project_status AS ENUM ('planning', 'active', 'on_hold', 'completed', 'cancelled');
CREATE TYPE methodology AS ENUM ('waterfall', 'agile', 'hybrid', 'kanban');
CREATE TYPE member_role AS ENUM ('owner', 'admin', 'member', 'viewer');
CREATE TYPE wbs_status AS ENUM ('pending', 'in_progress', 'completed', 'cancelled', 'archived');
CREATE TYPE dependency_type AS ENUM ('FS', 'SS', 'FF', 'SF');

-- Projects table
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status project_status NOT NULL DEFAULT 'planning',
    methodology methodology NOT NULL DEFAULT 'waterfall',
    color VARCHAR(20),
    icon VARCHAR(50),
    start_date TIMESTAMPTZ,
    target_date TIMESTAMPTZ,
    owner_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_projects_owner ON projects(owner_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_projects_status ON projects(status) WHERE deleted_at IS NULL;

-- Project members
CREATE TABLE project_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    role member_role NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    left_at TIMESTAMPTZ,

    UNIQUE(project_id, user_id)
);

CREATE INDEX idx_project_members_project ON project_members(project_id) WHERE left_at IS NULL;
CREATE INDEX idx_project_members_user ON project_members(user_id) WHERE left_at IS NULL;

-- WBS Nodes (Work Breakdown Structure)
CREATE TABLE wbs_nodes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES wbs_nodes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL, -- Creator

    -- Content
    title VARCHAR(500) NOT NULL,
    description TEXT,
    ai_summary VARCHAR(255),
    ai_steps JSONB DEFAULT '[]',

    -- Status and priority
    status wbs_status NOT NULL DEFAULT 'pending',
    priority SMALLINT NOT NULL DEFAULT 0,
    complexity SMALLINT DEFAULT 0,

    -- Hierarchy (unlimited depth unlike Tasks)
    depth SMALLINT NOT NULL DEFAULT 0,
    path VARCHAR(255) NOT NULL DEFAULT '', -- Materialized path e.g. "1.2.3"
    position INTEGER NOT NULL DEFAULT 0,

    -- Assignment
    assignee_id UUID,

    -- Scheduling
    planned_start TIMESTAMPTZ,
    planned_end TIMESTAMPTZ,
    actual_start TIMESTAMPTZ,
    actual_end TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    duration INTEGER, -- In days
    progress FLOAT NOT NULL DEFAULT 0, -- 0-100

    -- Dates
    start_date TIMESTAMPTZ,
    due_date TIMESTAMPTZ,

    -- Tags
    tags TEXT[] DEFAULT '{}',

    -- Agile fields
    story_points INTEGER,
    sprint_id UUID,

    -- Promoted from Tasks
    promoted_from_task UUID,

    -- Critical path
    is_critical BOOLEAN DEFAULT FALSE,

    -- Version for optimistic locking
    version INTEGER NOT NULL DEFAULT 1,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_wbs_nodes_project ON wbs_nodes(project_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_wbs_nodes_parent ON wbs_nodes(parent_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_wbs_nodes_path ON wbs_nodes(project_id, path) WHERE deleted_at IS NULL;
CREATE INDEX idx_wbs_nodes_assignee ON wbs_nodes(assignee_id) WHERE deleted_at IS NULL AND status != 'completed';
CREATE INDEX idx_wbs_nodes_promoted ON wbs_nodes(promoted_from_task) WHERE promoted_from_task IS NOT NULL;

-- WBS Dependencies
CREATE TABLE wbs_dependencies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    predecessor_id UUID NOT NULL REFERENCES wbs_nodes(id) ON DELETE CASCADE,
    successor_id UUID NOT NULL REFERENCES wbs_nodes(id) ON DELETE CASCADE,
    dependency_type dependency_type NOT NULL DEFAULT 'FS',
    lag_days INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(predecessor_id, successor_id)
);

CREATE INDEX idx_wbs_deps_project ON wbs_dependencies(project_id);
CREATE INDEX idx_wbs_deps_predecessor ON wbs_dependencies(predecessor_id);
CREATE INDEX idx_wbs_deps_successor ON wbs_dependencies(successor_id);
