# Flow Shared Infrastructure Plan

## Overview

This document covers the backend infrastructure for the Flow productivity suite.

**Architecture Summary:**
- **3 Domains**: shared, tasks, projects (each deploys independently)
- **3 Databases**: shared_db, tasks_db, projects_db (each domain owns one)
- **Cross-domain**: REST APIs only (no shared DB access between domains)
- **Models**: Base types in `common/`, extensions in domain `models/` folders

---

## 1. Backend Architecture (Go)

### 1.1 Architecture Philosophy

**Domain-Driven Monorepo Design:**
- **Shared Domain**: Common models, auth, users, entities, AI - shared by all apps
- **Tasks Domain**: Flow Tasks specific logic, connects to Tasks DB
- **Projects Domain**: Flow Projects specific logic, connects to Projects DB
- **Future Domains**: Easy to add (e.g., Scheduling, Calendar)

**Why This Design:**
- **Scalability**: Add new apps without touching existing code
- **Data Isolation**: Each domain has its own database for performance
- **Model Integrity**: Common models ensure consistency across all apps
- **Independent Deployment**: Deploy domains separately if needed
- **Clear Boundaries**: Teams can work on domains independently

### 1.2 Framework Selection: Fiber v2

**Why Fiber:**
- Express-like API (familiar to most developers)
- Fastest Go web framework (built on fasthttp)
- Built-in middleware ecosystem
- WebSocket support out of the box

**Alternatives Considered:**
- Echo: Similar performance, more opinionated
- Gin: Most popular, slightly slower
- Chi: Minimal, stdlib compatible

### 1.3 Monorepo Project Structure

```
/backend
├── go.work                           # Go workspace file
├── go.work.sum
│
├── common/                           # ═══ SHARED CODE (library, not service) ═══
│   ├── go.mod                        # module github.com/user/flow/common
│   ├── models/
│   │   ├── task_base.go              # Base task struct (embedded by domains)
│   │   ├── user.go                   # User struct
│   │   └── types.go                  # Status, Priority, enums
│   ├── interfaces/
│   │   └── repository.go             # Repository contracts
│   ├── errors/
│   │   └── errors.go                 # Shared error types
│   └── dto/
│       └── responses.go              # Common API response types
│
├── shared/                           # ═══ SHARED DOMAIN SERVICE ═══
│   ├── go.mod                        # module github.com/user/flow/shared
│   ├── cmd/
│   │   └── main.go                   # ← ENTRYPOINT: shared-service
│   ├── server.go                     # Fiber app setup
│   ├── routes.go                     # Route registration
│   │
│   ├── auth/
│   │   ├── handler.go
│   │   ├── service.go
│   │   ├── jwt.go
│   │   ├── oauth_google.go
│   │   ├── oauth_apple.go
│   │   └── oauth_microsoft.go
│   │
│   ├── user/
│   │   ├── handler.go
│   │   ├── service.go
│   │   └── repository.go
│   │
│   ├── entity/
│   │   ├── handler.go
│   │   ├── service.go
│   │   └── repository.go
│   │
│   ├── ai/
│   │   ├── orchestrator.go
│   │   ├── prompts.go
│   │   └── decomposer.go
│   │
│   ├── database/
│   │   ├── postgres.go               # → connects to shared_db
│   │   ├── migrations/
│   │   │   ├── 000001_users.up.sql
│   │   │   ├── 000002_refresh_tokens.up.sql
│   │   │   ├── 000003_entities.up.sql
│   │   │   └── 000004_ai_decisions.up.sql
│   │   └── queries/
│   │       ├── users.sql
│   │       └── entities.sql
│   │
│   ├── Dockerfile                    # Builds shared-service container
│   └── .env.example
│
├── tasks/                            # ═══ TASKS DOMAIN SERVICE ═══
│   ├── go.mod                        # module github.com/user/flow/tasks
│   ├── cmd/
│   │   └── main.go                   # ← ENTRYPOINT: tasks-service
│   ├── server.go
│   ├── routes.go
│   │
│   ├── models/
│   │   └── task.go                   # Embeds common.TaskBase + extensions
│   │
│   ├── handler.go
│   ├── service.go
│   ├── repository.go
│   ├── promotion.go                  # POST /tasks/:id/promote → calls projects API
│   │
│   ├── rules/
│   │   └── depth_limit.go            # Enforces 2-layer max
│   │
│   ├── sync/                         # Offline sync logic
│   │   ├── handler.go
│   │   ├── service.go
│   │   └── resolver.go
│   │
│   ├── database/
│   │   ├── postgres.go               # → connects to tasks_db
│   │   ├── migrations/
│   │   │   └── 000001_tasks.up.sql
│   │   └── queries/
│   │       └── tasks.sql
│   │
│   ├── Dockerfile                    # Builds tasks-service container
│   └── .env.example
│
├── projects/                         # ═══ PROJECTS DOMAIN SERVICE ═══
│   ├── go.mod                        # module github.com/user/flow/projects
│   ├── cmd/
│   │   └── main.go                   # ← ENTRYPOINT: projects-service
│   ├── server.go
│   ├── routes.go
│   │
│   ├── models/
│   │   ├── project.go
│   │   ├── wbs_node.go               # Embeds common.TaskBase + extensions
│   │   └── dependency.go
│   │
│   ├── handler.go
│   ├── service.go
│   ├── repository.go
│   │
│   ├── waterfall/
│   │   ├── critical_path.go
│   │   └── scheduler.go
│   │
│   ├── gantt/
│   │   └── generator.go
│   │
│   ├── team/
│   │   ├── handler.go
│   │   ├── service.go
│   │   └── workload.go
│   │
│   ├── database/
│   │   ├── postgres.go               # → connects to projects_db
│   │   ├── migrations/
│   │   │   ├── 000001_projects.up.sql
│   │   │   ├── 000002_wbs_nodes.up.sql
│   │   │   ├── 000003_project_members.up.sql
│   │   │   └── 000004_dependencies.up.sql
│   │   └── queries/
│   │       ├── projects.sql
│   │       └── wbs_nodes.sql
│   │
│   ├── Dockerfile                    # Builds projects-service container
│   └── .env.example
│
├── gateway/                          # ═══ API GATEWAY (optional) ═══
│   ├── go.mod
│   ├── cmd/
│   │   └── main.go
│   ├── routes.go                     # Path-based routing to services
│   └── Dockerfile
│
├── pkg/                              # ═══ SHARED PACKAGES (utilities) ═══
│   ├── llm/
│   │   ├── client.go
│   │   ├── anthropic.go
│   │   ├── google.go
│   │   └── ollama.go
│   ├── middleware/
│   │   ├── auth.go
│   │   ├── cors.go
│   │   └── logging.go
│   ├── config/
│   │   └── config.go
│   └── httputil/
│       └── response.go
│
└── deploy/
    ├── docker-compose.yml            # All 3 services + 3 databases
    ├── docker-compose.dev.yml
    └── railway/
        ├── shared.toml
        ├── tasks.toml
        └── projects.toml
```

**Key Points:**
- Each domain (`shared/`, `tasks/`, `projects/`) has its own `go.mod`, `cmd/main.go`, `Dockerfile`
- `common/` is a library (imported by domains), not a running service
- `pkg/` contains shared utilities (imported by domains)
- Each domain connects to exactly ONE database

### 1.4 Database Architecture

**3 Databases, Strict Ownership:**

| Database | Owner Service | Tables |
|----------|---------------|--------|
| `shared_db` | shared-service | users, refresh_tokens, entities, ai_decisions |
| `tasks_db` | tasks-service | tasks |
| `projects_db` | projects-service | projects, wbs_nodes, project_members, dependencies |

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              API Gateway                                  │
│                          (Routes by path prefix)                          │
└────────────┬────────────────────┬────────────────────┬───────────────────┘
             │                    │                    │
   /api/v1/auth/*         /api/v1/tasks/*     /api/v1/projects/*
   /api/v1/users/*
   /api/v1/entities/*
             │                    │                    │
             ▼                    ▼                    ▼
    ┌────────────────┐   ┌────────────────┐   ┌────────────────┐
    │ shared-service │   │ tasks-service  │   │projects-service│
    │                │   │                │   │                │
    │ Port: 8081     │   │ Port: 8082     │   │ Port: 8083     │
    └───────┬────────┘   └───────┬────────┘   └───────┬────────┘
            │                    │                    │
            │ OWNS               │ OWNS               │ OWNS
            ▼                    ▼                    ▼
    ┌────────────────┐   ┌────────────────┐   ┌────────────────┐
    │   shared_db    │   │   tasks_db     │   │  projects_db   │
    │   Port: 5432   │   │   Port: 5433   │   │   Port: 5434   │
    │                │   │                │   │                │
    │ • users        │   │ • tasks        │   │ • projects     │
    │ • refresh_tkns │   │                │   │ • wbs_nodes    │
    │ • entities     │   │                │   │ • project_mems │
    │ • ai_decisions │   │                │   │ • dependencies │
    └────────────────┘   └────────────────┘   └────────────────┘

                    ┌────────────────┐
                    │     Redis      │
                    │   Port: 6379   │
                    │                │
                    │ • JWT blacklist│
                    │ • Rate limits  │
                    │ • Cache        │
                    └────────────────┘
```

**Cross-Service Communication:**
```
┌──────────────────────────────────────────────────────────────────────────┐
│                         PROMOTION FLOW EXAMPLE                            │
└──────────────────────────────────────────────────────────────────────────┘

Flow Tasks App                                      projects-service
     │                                                     │
     │ POST /api/v1/tasks/{id}/promote                    │
     │ {project_id, parent_node_id, keep_personal}        │
     ▼                                                     │
┌─────────────┐                                           │
│tasks-service│                                           │
│             │  1. Validate task exists                  │
│             │  2. Call projects-service API ───────────►│
│             │     POST /internal/wbs-nodes              │
│             │     {task data, source_task_id}           │
│             │                                           │
│             │  3. Receive created node ◄────────────────│
│             │                                           │
│             │  4a. If keep_personal:                    │
│             │      UPDATE tasks SET                     │
│             │        promoted_to_project_id = X,        │
│             │        promoted_to_node_id = Y            │
│             │                                           │
│             │  4b. If !keep_personal:                   │
│             │      UPDATE tasks SET deleted_at = NOW()  │
└─────────────┘                                           │
                                                          ▼
                                              ┌─────────────────┐
                                              │ projects_db     │
                                              │                 │
                                              │ INSERT wbs_nodes│
                                              │ (source_task_id)│
                                              └─────────────────┘
```

### 1.5 Cross-Domain Communication

```go
// common/events/task_events.go

// Events are published to Redis Streams for cross-domain communication

type TaskPromotedEvent struct {
    BaseEvent
    TaskID       uuid.UUID `json:"task_id"`
    UserID       uuid.UUID `json:"user_id"`
    Title        string    `json:"title"`
    Description  string    `json:"description"`
    TargetDomain string    `json:"target_domain"` // "projects"
}

type TaskCompletedEvent struct {
    BaseEvent
    TaskID      uuid.UUID `json:"task_id"`
    UserID      uuid.UUID `json:"user_id"`
    WBSNodeID   *uuid.UUID `json:"wbs_node_id,omitempty"` // If linked to project
}

// Projects domain listens for TaskPromoted → creates new project
// Tasks domain listens for WBSNodeCompleted → updates task status
```

### 1.6 Common Models Pattern

```go
// common/models/task_base.go

// TaskBase contains fields shared by ALL task-like entities
// Both Tasks domain and Projects domain extend this

type TaskBase struct {
    ID          uuid.UUID  `json:"id" db:"id"`
    UserID      uuid.UUID  `json:"user_id" db:"user_id"`
    Title       string     `json:"title" db:"title"`
    Description *string    `json:"description,omitempty" db:"description"`
    AISSummary  *string    `json:"ai_summary,omitempty" db:"ai_summary"`
    AISteps     []TaskStep `json:"ai_steps,omitempty" db:"ai_steps"`
    Status      Status     `json:"status" db:"status"`
    Priority    Priority   `json:"priority" db:"priority"`
    Complexity  int        `json:"complexity" db:"complexity"`
    StartDate   *time.Time `json:"start_date,omitempty" db:"start_date"`
    DueDate     *time.Time `json:"due_date,omitempty" db:"due_date"`
    CompletedAt *time.Time `json:"completed_at,omitempty" db:"completed_at"`
    Tags        []string   `json:"tags,omitempty" db:"tags"`
    CreatedAt   time.Time  `json:"created_at" db:"created_at"`
    UpdatedAt   time.Time  `json:"updated_at" db:"updated_at"`
    DeletedAt   *time.Time `json:"deleted_at,omitempty" db:"deleted_at"`
}

// common/models/common.go

type Status string

const (
    StatusPending    Status = "pending"
    StatusInProgress Status = "in_progress"
    StatusCompleted  Status = "completed"
    StatusCancelled  Status = "cancelled"
    StatusArchived   Status = "archived"
)

type Priority int

const (
    PriorityNone   Priority = 0
    PriorityLow    Priority = 1
    PriorityMedium Priority = 2
    PriorityHigh   Priority = 3
    PriorityUrgent Priority = 4
)
```

```go
// tasks/models/task.go

import "github.com/youruser/flow/common/models"

// Task extends TaskBase with Tasks-domain-specific fields
type Task struct {
    models.TaskBase

    // Tasks-specific fields
    ParentID     *uuid.UUID `json:"parent_id,omitempty" db:"parent_id"`
    Depth        int        `json:"depth" db:"depth"`        // 0 or 1 only
    LocalID      *string    `json:"local_id,omitempty" db:"local_id"`
    Version      int        `json:"version" db:"version"`
    LastSyncedAt *time.Time `json:"last_synced_at,omitempty" db:"last_synced_at"`

    // Computed/loaded
    Children     []Task     `json:"children,omitempty" db:"-"`
}
```

```go
// projects/models/wbs_node.go

import "github.com/youruser/flow/common/models"

// WBSNode extends TaskBase with Projects-domain-specific fields
type WBSNode struct {
    models.TaskBase

    // Projects-specific fields
    ProjectID        uuid.UUID  `json:"project_id" db:"project_id"`
    ParentID         *uuid.UUID `json:"parent_id,omitempty" db:"parent_id"`
    Path             string     `json:"path" db:"path"`           // ltree
    Depth            int        `json:"depth" db:"depth"`         // Unlimited
    WBSCode          string     `json:"wbs_code" db:"wbs_code"`   // "1.2.3"
    EstimatedHours   *int       `json:"estimated_hours,omitempty" db:"estimated_hours"`
    ActualHours      *int       `json:"actual_hours,omitempty" db:"actual_hours"`
    AssigneeID       *uuid.UUID `json:"assignee_id,omitempty" db:"assignee_id"`
    ProgressPercent  float64    `json:"progress_percent" db:"progress_percent"`

    // Computed/loaded
    Children         []WBSNode  `json:"children,omitempty" db:"-"`
    Dependencies     []Dependency `json:"dependencies,omitempty" db:"-"`
}
```

### 1.7 Adding New Domains (Future Scalability)

To add a new domain (e.g., Flow Schedule):

```
1. Create new folder: /backend/schedule/
2. Create go.mod: module github.com/youruser/flow/schedule
3. Import common models: import "github.com/youruser/flow/common/models"
4. Create domain-specific extensions
5. Add database migrations in schedule/database/migrations/
6. Create new service: cmd/schedule-service/main.go
7. Add routes in gateway/routes.go
8. Add Dockerfile: deploy/Dockerfile.schedule
9. Add to docker-compose.yml
```

**Example: Flow Schedule Domain**
```
/backend/schedule/
├── go.mod
├── handler.go
├── service.go
├── repository.go
├── models/
│   ├── event.go              # Extends models.TaskBase
│   ├── calendar.go
│   └── recurrence.go
├── rules/
│   ├── conflicts.go          # Conflict detection
│   └── availability.go       # Free/busy logic
├── database/
│   ├── postgres.go           # Connection to schedule_db
│   └── migrations/
│       ├── 000001_events.up.sql
│       └── 000002_calendars.up.sql
└── queries/
    └── events.sql
```

### 1.8 Key Go Dependencies

```go
// go.mod
module github.com/yourusername/flow

go 1.22

require (
    // Web Framework
    github.com/gofiber/fiber/v2 v2.52.0
    github.com/gofiber/websocket/v2 v2.2.1
    github.com/gofiber/jwt/v3 v3.3.10

    // Database
    github.com/jackc/pgx/v5 v5.5.0          // PostgreSQL driver
    github.com/redis/go-redis/v9 v9.4.0     // Redis client

    // Auth
    github.com/golang-jwt/jwt/v5 v5.2.0     // JWT
    golang.org/x/oauth2 v0.16.0             // OAuth2

    // Background Jobs
    github.com/hibiken/asynq v0.24.1        // Job queue

    // Utilities
    github.com/google/uuid v1.6.0           // UUIDs
    github.com/go-playground/validator/v10  // Validation
    github.com/rs/zerolog v1.31.0           // Logging
    github.com/spf13/viper v1.18.0          // Config

    // AI/LLM
    github.com/anthropics/anthropic-sdk-go  // Claude
    github.com/sashabaranov/go-openai       // OpenAI compatible
)
```

### 1.9 Configuration Management

```go
// pkg/config/config.go
package config

type Config struct {
    Server    ServerConfig
    Databases DatabasesConfig  // Multiple databases
    Redis     RedisConfig
    Auth      AuthConfig
    LLM       LLMConfig
}

type ServerConfig struct {
    Host            string `mapstructure:"HOST" default:"0.0.0.0"`
    Port            int    `mapstructure:"PORT" default:"8080"`
    ShutdownTimeout int    `mapstructure:"SHUTDOWN_TIMEOUT" default:"10"`
}

// DatabasesConfig holds connections for all domain databases
type DatabasesConfig struct {
    Shared   DatabaseConfig `mapstructure:"SHARED_DB"`   // Users, auth, entities
    Tasks    DatabaseConfig `mapstructure:"TASKS_DB"`    // Tasks domain
    Projects DatabaseConfig `mapstructure:"PROJECTS_DB"` // Projects domain
}

type DatabaseConfig struct {
    Host         string `mapstructure:"HOST" default:"localhost"`
    Port         int    `mapstructure:"PORT" default:"5432"`
    User         string `mapstructure:"USER" required:"true"`
    Password     string `mapstructure:"PASSWORD" required:"true"`
    Name         string `mapstructure:"NAME" required:"true"`
    SSLMode      string `mapstructure:"SSL_MODE" default:"disable"`
    MaxOpenConns int    `mapstructure:"MAX_OPEN_CONNS" default:"25"`
    MaxIdleConns int    `mapstructure:"MAX_IDLE_CONNS" default:"5"`
}

type RedisConfig struct {
    Host     string `mapstructure:"REDIS_HOST" default:"localhost"`
    Port     int    `mapstructure:"REDIS_PORT" default:"6379"`
    Password string `mapstructure:"REDIS_PASSWORD"`
    DB       int    `mapstructure:"REDIS_DB" default:"0"`
}

type AuthConfig struct {
    JWTSecret           string `mapstructure:"JWT_SECRET" required:"true"`
    JWTExpiryMinutes    int    `mapstructure:"JWT_EXPIRY_MINUTES" default:"15"`
    RefreshExpiryDays   int    `mapstructure:"REFRESH_EXPIRY_DAYS" default:"7"`
    GoogleClientID      string `mapstructure:"GOOGLE_CLIENT_ID"`
    GoogleClientSecret  string `mapstructure:"GOOGLE_CLIENT_SECRET"`
    AppleClientID       string `mapstructure:"APPLE_CLIENT_ID"`
    AppleTeamID         string `mapstructure:"APPLE_TEAM_ID"`
    AppleKeyID          string `mapstructure:"APPLE_KEY_ID"`
    ApplePrivateKey     string `mapstructure:"APPLE_PRIVATE_KEY"`
    MicrosoftClientID   string `mapstructure:"MICROSOFT_CLIENT_ID"`
    MicrosoftSecret     string `mapstructure:"MICROSOFT_CLIENT_SECRET"`
}

type LLMConfig struct {
    DefaultProvider    string `mapstructure:"LLM_DEFAULT_PROVIDER" default:"anthropic"`
    AnthropicAPIKey    string `mapstructure:"ANTHROPIC_API_KEY"`
    GoogleAPIKey       string `mapstructure:"GOOGLE_AI_API_KEY"`
    OpenAIAPIKey       string `mapstructure:"OPENAI_API_KEY"`
    OllamaHost         string `mapstructure:"OLLAMA_HOST" default:"http://localhost:11434"`
    OllamaModel        string `mapstructure:"OLLAMA_MODEL" default:"llama3.1:8b"`
}
```

---

## 2. Database Schema (PostgreSQL)

### 2.1 Extensions Required

```sql
-- migrations/000001_init_extensions.up.sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";      -- UUID generation
CREATE EXTENSION IF NOT EXISTS "ltree";          -- Hierarchical data
CREATE EXTENSION IF NOT EXISTS "pgcrypto";       -- Encryption
CREATE EXTENSION IF NOT EXISTS "pg_trgm";        -- Text similarity
-- Future: CREATE EXTENSION IF NOT EXISTS "vector"; -- pgvector for embeddings
```

### 2.2 Core Tables

```sql
-- migrations/000002_users.up.sql

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    email_verified BOOLEAN DEFAULT FALSE,
    password_hash VARCHAR(255),  -- NULL if OAuth-only
    name VARCHAR(255) NOT NULL,
    avatar_url TEXT,

    -- OAuth identifiers
    google_id VARCHAR(255) UNIQUE,
    apple_id VARCHAR(255) UNIQUE,
    microsoft_id VARCHAR(255) UNIQUE,

    -- Settings stored as JSONB for flexibility
    settings JSONB DEFAULT '{}',
    -- Example: {"theme": "dark", "notifications": true, "timezone": "America/Los_Angeles"}

    -- AI personalization
    ai_profile JSONB DEFAULT '{}',
    -- Example: {"archetype": "executive", "style": "concise", "peak_hours": [9,10,11]}

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_login_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ  -- Soft delete
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_google_id ON users(google_id) WHERE google_id IS NOT NULL;
CREATE INDEX idx_users_apple_id ON users(apple_id) WHERE apple_id IS NOT NULL;
CREATE INDEX idx_users_microsoft_id ON users(microsoft_id) WHERE microsoft_id IS NOT NULL;

-- Refresh tokens for JWT rotation
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    device_info JSONB,  -- {"platform": "ios", "device": "iPhone 15", "app_version": "1.0.0"}
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    revoked_at TIMESTAMPTZ
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);
```

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- tasks_db: migrations/000001_tasks.up.sql
-- ═══════════════════════════════════════════════════════════════════════════

-- Personal tasks table (Flow Tasks app only)
CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,  -- References shared_db.users (not FK, cross-db)

    -- Hierarchy (max 2 levels: 0=parent, 1=child)
    parent_id UUID REFERENCES tasks(id) ON DELETE CASCADE,
    depth INTEGER DEFAULT 0 CHECK (depth <= 1),  -- ENFORCED: max 2 layers

    -- Core fields
    title TEXT NOT NULL,
    description TEXT,
    ai_summary TEXT,
    ai_steps JSONB,
    -- Example: [{"step": 1, "action": "Turn off water valve", "done": false}]

    -- Status
    status VARCHAR(20) DEFAULT 'pending',
    -- Values: pending, in_progress, completed, cancelled
    priority INTEGER DEFAULT 0,  -- 0=none, 1=low, 2=medium, 3=high, 4=urgent
    complexity INTEGER DEFAULT 1,  -- 1-10 scale

    -- Dates
    due_date TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    -- Metadata
    tags TEXT[],

    -- ═══ PROMOTION TRACKING ═══
    promoted_to_project_id UUID,    -- Which project it was promoted to
    promoted_to_node_id UUID,       -- The wbs_node ID in projects_db
    promoted_at TIMESTAMPTZ,
    -- If set, UI shows "linked" indicator

    -- Sync tracking (offline-first)
    local_id VARCHAR(255),
    version INTEGER DEFAULT 1,
    last_synced_at TIMESTAMPTZ,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_tasks_user ON tasks(user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_tasks_parent ON tasks(parent_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_tasks_due_date ON tasks(user_id, due_date)
    WHERE deleted_at IS NULL AND status != 'completed';
CREATE INDEX idx_tasks_local_id ON tasks(user_id, local_id)
    WHERE local_id IS NOT NULL;
CREATE INDEX idx_tasks_promoted ON tasks(promoted_to_node_id)
    WHERE promoted_to_node_id IS NOT NULL;

-- Trigger to enforce depth limit
CREATE OR REPLACE FUNCTION check_task_depth() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.parent_id IS NOT NULL THEN
        SELECT depth + 1 INTO NEW.depth FROM tasks WHERE id = NEW.parent_id;
        IF NEW.depth > 1 THEN
            RAISE EXCEPTION 'Task depth cannot exceed 1 (max 2 layers). Consider promoting to a project.';
        END IF;
    ELSE
        NEW.depth = 0;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_task_depth
    BEFORE INSERT OR UPDATE OF parent_id ON tasks
    FOR EACH ROW EXECUTE FUNCTION check_task_depth();
```

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- projects_db: migrations/000001_projects.up.sql
-- ═══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "ltree";

-- Projects table
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL,  -- References shared_db.users

    -- Core
    name VARCHAR(255) NOT NULL,
    description TEXT,
    methodology VARCHAR(20) DEFAULT 'waterfall',
    -- Values: waterfall, agile, hybrid, kanban

    -- Status
    status VARCHAR(20) DEFAULT 'planning',
    -- Values: planning, active, on_hold, completed, cancelled

    -- Dates
    start_date DATE,
    target_end_date DATE,
    actual_end_date DATE,

    -- AI metadata
    ai_summary TEXT,
    ai_goals JSONB,

    -- Settings
    settings JSONB DEFAULT '{}',

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_projects_owner ON projects(owner_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_projects_status ON projects(owner_id, status) WHERE deleted_at IS NULL;
```

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- projects_db: migrations/000002_wbs_nodes.up.sql
-- ═══════════════════════════════════════════════════════════════════════════

-- WBS Nodes (Work Breakdown Structure) - Project tasks
CREATE TABLE wbs_nodes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Hierarchy (unlimited depth)
    parent_id UUID REFERENCES wbs_nodes(id) ON DELETE CASCADE,
    path LTREE,
    depth INTEGER DEFAULT 0,
    wbs_code VARCHAR(50),  -- "1.2.3" style code
    sort_order INTEGER DEFAULT 0,

    -- Core fields (same as personal tasks)
    title TEXT NOT NULL,
    description TEXT,
    ai_summary TEXT,
    ai_steps JSONB,

    -- Status
    status VARCHAR(20) DEFAULT 'pending',
    priority INTEGER DEFAULT 0,
    complexity INTEGER DEFAULT 1,

    -- Project-specific fields
    assignee_id UUID,  -- References shared_db.users
    estimated_hours INTEGER,
    actual_hours INTEGER,
    progress_percent DECIMAL(5,2) DEFAULT 0,

    -- Dates
    start_date DATE,
    end_date DATE,
    due_date TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    -- ═══ SOURCE TRACKING (if promoted from personal task) ═══
    source_user_id UUID,      -- Who promoted it
    source_task_id UUID,      -- Original task ID in tasks_db
    promoted_at TIMESTAMPTZ,
    -- Informational only - no sync back to tasks_db

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_wbs_project ON wbs_nodes(project_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_wbs_parent ON wbs_nodes(parent_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_wbs_assignee ON wbs_nodes(assignee_id)
    WHERE assignee_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX idx_wbs_path ON wbs_nodes USING GIST (path);
CREATE INDEX idx_wbs_source ON wbs_nodes(source_task_id)
    WHERE source_task_id IS NOT NULL;

-- Trigger to update path and wbs_code
CREATE OR REPLACE FUNCTION update_wbs_path() RETURNS TRIGGER AS $$
DECLARE
    parent_path LTREE;
    sibling_count INTEGER;
BEGIN
    IF NEW.parent_id IS NULL THEN
        -- Root level
        SELECT COUNT(*) INTO sibling_count
        FROM wbs_nodes
        WHERE project_id = NEW.project_id AND parent_id IS NULL AND id != NEW.id;

        NEW.path = text2ltree(NEW.project_id::text || '.' || NEW.id::text);
        NEW.depth = 0;
        NEW.wbs_code = (sibling_count + 1)::text || '.0';
    ELSE
        -- Child node
        SELECT path, depth INTO parent_path, NEW.depth
        FROM wbs_nodes WHERE id = NEW.parent_id;

        NEW.depth = NEW.depth + 1;
        NEW.path = parent_path || NEW.id::text;

        -- Calculate WBS code
        SELECT COUNT(*) INTO sibling_count
        FROM wbs_nodes
        WHERE parent_id = NEW.parent_id AND id != NEW.id;

        SELECT wbs_code INTO NEW.wbs_code FROM wbs_nodes WHERE id = NEW.parent_id;
        NEW.wbs_code = regexp_replace(NEW.wbs_code, '\.0$', '') || '.' || (sibling_count + 1)::text;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_wbs_path
    BEFORE INSERT ON wbs_nodes
    FOR EACH ROW EXECUTE FUNCTION update_wbs_path();
```

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- projects_db: migrations/000003_project_members.up.sql
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE project_members (
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,  -- References shared_db.users
    role VARCHAR(20) DEFAULT 'member',
    -- Values: owner, admin, member, viewer
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (project_id, user_id)
);

CREATE INDEX idx_project_members_user ON project_members(user_id);
```

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- projects_db: migrations/000004_dependencies.up.sql
-- ═══════════════════════════════════════════════════════════════════════════

-- WBS node dependencies (Waterfall logic)
CREATE TABLE dependencies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    predecessor_id UUID NOT NULL REFERENCES wbs_nodes(id) ON DELETE CASCADE,
    successor_id UUID NOT NULL REFERENCES wbs_nodes(id) ON DELETE CASCADE,

    type VARCHAR(10) DEFAULT 'FS',
    -- FS = Finish-to-Start (most common)
    -- SS = Start-to-Start
    -- FF = Finish-to-Finish
    -- SF = Start-to-Finish

    lag_days INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(predecessor_id, successor_id)
);

CREATE INDEX idx_deps_predecessor ON dependencies(predecessor_id);
CREATE INDEX idx_deps_successor ON dependencies(successor_id);
```

```sql
-- migrations/000006_entities.up.sql

-- Entity Ledger (people/contacts mentioned in tasks)
CREATE TABLE entities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Identity
    name VARCHAR(255) NOT NULL,
    normalized_name VARCHAR(255),  -- Lowercase, no accents for matching
    aliases TEXT[],  -- ["Sarah", "Sarah Chen", "S. Chen"]

    -- Contact info (if known)
    email VARCHAR(255),
    phone VARCHAR(50),

    -- AI-inferred profile
    profile JSONB DEFAULT '{}',
    /*
    Example:
    {
        "inferred_role": "Marketing Manager",
        "relationship": "Colleague",
        "organization": "Acme Corp",
        "communication_style": {
            "prefers": "concise",
            "channel": "email",
            "formality": 0.7
        },
        "context_tags": ["marketing", "budget", "Q3"],
        "last_topics": ["campaign launch", "vendor selection"]
    }
    */

    -- Confidence tracking
    confidence FLOAT DEFAULT 0.1,  -- 0.0 to 1.0
    observation_count INTEGER DEFAULT 1,
    hypothesis_conflicts INTEGER DEFAULT 0,

    -- Timestamps
    first_seen_at TIMESTAMPTZ DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_entities_user ON entities(user_id);
CREATE INDEX idx_entities_name ON entities(user_id, normalized_name);
CREATE INDEX idx_entities_email ON entities(email) WHERE email IS NOT NULL;

-- Entity mentions (links entities to tasks)
CREATE TABLE entity_mentions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_id UUID NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    context_snippet TEXT,  -- "Email Sarah about the budget"
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(entity_id, task_id)
);

CREATE INDEX idx_mentions_entity ON entity_mentions(entity_id);
CREATE INDEX idx_mentions_task ON entity_mentions(task_id);
```

```sql
-- migrations/000007_ai_decisions.up.sql

-- Decision log (for training adapters)
CREATE TABLE ai_decisions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Context
    decision_type VARCHAR(50) NOT NULL,
    -- Values: task_decomposition, priority_assignment, entity_inference,
    --         draft_email, schedule_suggestion, complexity_assessment

    context JSONB NOT NULL,
    -- Input context the AI had when making the decision

    -- AI output
    ai_choice JSONB NOT NULL,
    -- What the AI decided/generated

    -- User response
    user_action VARCHAR(50),
    -- Values: accepted, rejected, modified, ignored

    user_modification JSONB,
    -- If modified, what the user changed it to

    -- Scoring
    delta_score FLOAT,
    -- Calculated difference: -1.0 (completely wrong) to +1.0 (perfect)

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ  -- When user took action
);

CREATE INDEX idx_decisions_user ON ai_decisions(user_id);
CREATE INDEX idx_decisions_type ON ai_decisions(user_id, decision_type);
CREATE INDEX idx_decisions_unresolved ON ai_decisions(user_id)
    WHERE resolved_at IS NULL;
```

```sql
-- migrations/000008_actions.up.sql

-- Agentic actions (drafts requiring user approval)
CREATE TABLE agentic_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    task_id UUID REFERENCES tasks(id) ON DELETE SET NULL,
    entity_id UUID REFERENCES entities(id) ON DELETE SET NULL,

    -- Action type
    action_type VARCHAR(50) NOT NULL,
    -- Values: email_draft, calendar_invite, reminder

    -- Status
    status VARCHAR(50) DEFAULT 'pending_review',
    -- Values: pending_review, approved, sent, dismissed, failed

    -- Content
    payload JSONB NOT NULL,
    /*
    Example for email_draft:
    {
        "to": "sarah@example.com",
        "subject": "Q3 Budget Review",
        "body": "Hi Sarah,\n\nJust checking in on...",
        "suggested_send_time": "2024-01-15T09:00:00Z"
    }

    Example for calendar_invite:
    {
        "title": "Sync with Sarah",
        "attendees": ["sarah@example.com"],
        "suggested_times": ["2024-01-15T10:00:00Z", "2024-01-15T14:00:00Z"],
        "duration_minutes": 30,
        "description": "Discuss Q3 budget"
    }

    Example for reminder:
    {
        "message": "Follow up on bathroom repair",
        "remind_at": "2024-01-16T09:00:00Z"
    }
    */

    -- AI reasoning (for debugging/learning)
    ai_reasoning TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    executed_at TIMESTAMPTZ
);

/*
═══════════════════════════════════════════════════════════════════════════════
AGENTIC ACTION EXECUTION - TECHNOLOGY REQUIREMENTS
═══════════════════════════════════════════════════════════════════════════════

┌─────────────────┬────────────────────────────┬───────────────────────────────┐
│ Action Type     │ Technology                 │ Implementation                │
├─────────────────┼────────────────────────────┼───────────────────────────────┤
│ email_draft     │ OAuth + Gmail/Outlook API  │ User connects their email     │
│                 │ OR SendGrid (fallback)     │ account via OAuth. We send    │
│                 │                            │ AS the user, not from our     │
│                 │                            │ domain.                       │
│                 │                            │                               │
│                 │ Gmail: googleapis.com/gmail│                               │
│                 │ Outlook: graph.microsoft   │                               │
│                 │          .com/v1.0/me/     │                               │
│                 │          sendMail          │                               │
├─────────────────┼────────────────────────────┼───────────────────────────────┤
│ calendar_invite │ OAuth + Google Calendar/   │ User connects calendar via    │
│                 │ Outlook Calendar API       │ OAuth. We create events on    │
│                 │                            │ their behalf.                 │
│                 │                            │                               │
│                 │ Google: googleapis.com/    │                               │
│                 │         calendar/v3        │                               │
│                 │ Outlook: graph.microsoft   │                               │
│                 │          .com/v1.0/me/     │                               │
│                 │          calendar/events   │                               │
├─────────────────┼────────────────────────────┼───────────────────────────────┤
│ reminder        │ Firebase Cloud Messaging   │ Schedule push notification    │
│                 │ (FCM) + APNs               │ to user's device at specified │
│                 │                            │ time. No external account     │
│                 │                            │ needed.                       │
└─────────────────┴────────────────────────────┴───────────────────────────────┘

OAuth Scopes Required:
- Gmail: https://www.googleapis.com/auth/gmail.send
- Google Calendar: https://www.googleapis.com/auth/calendar.events
- Microsoft: Mail.Send, Calendars.ReadWrite

User Flow:
1. First time user tries to approve email/calendar action
2. "Connect your Google/Microsoft account to send emails"
3. OAuth consent screen
4. Store refresh token in users.oauth_tokens (encrypted)
5. Use token to execute action
*/

CREATE INDEX idx_actions_user ON agentic_actions(user_id);
CREATE INDEX idx_actions_status ON agentic_actions(user_id, status);
CREATE INDEX idx_actions_task ON agentic_actions(task_id) WHERE task_id IS NOT NULL;
```

```sql
-- migrations/000009_sync.up.sql

-- Sync tracking for offline-first
CREATE TABLE sync_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255) NOT NULL,

    -- Operation
    operation VARCHAR(20) NOT NULL,  -- create, update, delete
    table_name VARCHAR(50) NOT NULL,
    record_id UUID NOT NULL,
    payload JSONB NOT NULL,

    -- Conflict resolution
    client_timestamp TIMESTAMPTZ NOT NULL,
    server_timestamp TIMESTAMPTZ DEFAULT NOW(),
    resolved BOOLEAN DEFAULT FALSE,
    resolution_type VARCHAR(20),  -- client_wins, server_wins, merged

    -- Processing
    processed_at TIMESTAMPTZ,
    error TEXT
);

CREATE INDEX idx_sync_user_device ON sync_queue(user_id, device_id);
CREATE INDEX idx_sync_unprocessed ON sync_queue(user_id)
    WHERE processed_at IS NULL;
```

### 2.3 sqlc Configuration

```yaml
# sqlc.yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "queries/"
    schema: "migrations/"
    gen:
      go:
        package: "db"
        out: "pkg/database/queries"
        sql_package: "pgx/v5"
        emit_json_tags: true
        emit_prepared_queries: true
        emit_interface: true
        emit_exact_table_names: false
        emit_empty_slices: true
        overrides:
          - db_type: "uuid"
            go_type: "github.com/google/uuid.UUID"
          - db_type: "timestamptz"
            go_type: "time.Time"
          - db_type: "jsonb"
            go_type: "json.RawMessage"
          - db_type: "ltree"
            go_type: "string"
```

---

## 3. Authentication System

### 3.1 JWT Structure

```go
// internal/auth/jwt.go

type TokenClaims struct {
    jwt.RegisteredClaims
    UserID    uuid.UUID `json:"uid"`
    Email     string    `json:"email"`
    TokenType string    `json:"type"` // "access" or "refresh"
}

type TokenPair struct {
    AccessToken  string    `json:"access_token"`
    RefreshToken string    `json:"refresh_token"`
    ExpiresAt    time.Time `json:"expires_at"`
}
```

### 3.2 OAuth Flows

**Google OAuth:**
1. Client initiates with Google Sign-In SDK
2. Client receives ID token
3. Client sends ID token to `/auth/google`
4. Backend verifies token with Google
5. Backend creates/updates user, returns JWT pair

**Apple Sign-In:**
1. Client initiates with Apple Sign-In
2. Client receives authorization code + identity token
3. Client sends to `/auth/apple`
4. Backend verifies with Apple's public keys
5. Backend creates/updates user, returns JWT pair

**Microsoft OAuth:**
1. Client redirects to Microsoft login
2. Microsoft redirects back with code
3. Client sends code to `/auth/microsoft`
4. Backend exchanges code for tokens
5. Backend creates/updates user, returns JWT pair

### 3.3 Auth Endpoints

```
POST /auth/register          # Email/password registration
POST /auth/login             # Email/password login
POST /auth/refresh           # Refresh access token
POST /auth/logout            # Revoke refresh token
POST /auth/google            # Google OAuth
POST /auth/apple             # Apple OAuth
POST /auth/microsoft         # Microsoft OAuth
POST /auth/forgot-password   # Request password reset
POST /auth/reset-password    # Complete password reset
GET  /auth/me                # Get current user
```

---

## 4. AI/LLM Layer

### 4.1 LLM Client Interface

```go
// pkg/llm/client.go

type Provider string

const (
    ProviderAnthropic Provider = "anthropic"
    ProviderGoogle    Provider = "google"
    ProviderOpenAI    Provider = "openai"
    ProviderOllama    Provider = "ollama"
)

type Message struct {
    Role    string `json:"role"`    // system, user, assistant
    Content string `json:"content"`
}

type CompletionRequest struct {
    Provider    Provider
    Model       string
    Messages    []Message
    MaxTokens   int
    Temperature float64
    Tools       []Tool  // For function calling
}

type CompletionResponse struct {
    Content   string
    ToolCalls []ToolCall
    Usage     Usage
}

type Client interface {
    Complete(ctx context.Context, req CompletionRequest) (*CompletionResponse, error)
    Stream(ctx context.Context, req CompletionRequest) (<-chan StreamChunk, error)
}
```

### 4.2 Provider Routing

```go
// internal/ai/orchestrator.go

type TaskType string

const (
    TaskDecomposition   TaskType = "decomposition"    // Break task into steps
    TaskEntityExtract   TaskType = "entity_extract"   // Find people in text
    TaskDraftEmail      TaskType = "draft_email"      // Write email draft
    TaskSummarize       TaskType = "summarize"        // Clean up description
    TaskComplexity      TaskType = "complexity"       // Assess task complexity
    TaskProfileInfer    TaskType = "profile_infer"    // Background profiling
)

// ProviderRouting maps task types to preferred providers
var ProviderRouting = map[TaskType][]Provider{
    TaskDecomposition:  {ProviderAnthropic, ProviderOpenAI},     // Claude best for structured output
    TaskEntityExtract:  {ProviderOllama, ProviderAnthropic},     // Privacy-first, fast
    TaskDraftEmail:     {ProviderAnthropic},                     // Claude only (Constitutional AI)
    TaskSummarize:      {ProviderGoogle, ProviderAnthropic},     // Gemini good, cheap
    TaskComplexity:     {ProviderOllama, ProviderGoogle},        // Local or cheap
    TaskProfileInfer:   {ProviderGoogle},                        // Long context for history
}
```

### 4.3 System Prompts

```go
// internal/ai/prompts.go

const TaskDecompositionPrompt = `You are a task decomposition assistant. Given a task description, break it down into clear, actionable steps.

Rules:
1. Create 2-5 steps maximum (keep it simple)
2. Each step should be completable in one sitting
3. Use action verbs (Call, Write, Review, Send)
4. If the task seems too complex (would need >5 steps or multiple days), mark complexity as HIGH

Output JSON:
{
  "summary": "Concise 5-10 word title",
  "steps": [
    {"step": 1, "action": "Do X"},
    {"step": 2, "action": "Do Y"}
  ],
  "complexity": "LOW|MEDIUM|HIGH",
  "estimated_minutes": 30,
  "suggest_project": false
}`

const EntityExtractionPrompt = `Extract people mentioned in this task. For each person, infer what you can about their relationship to the user.

Rules:
1. Only extract real people, not companies or generic roles
2. Note the context of the mention
3. Infer relationship type: colleague, client, family, friend, service_provider, unknown

Output JSON:
{
  "entities": [
    {
      "name": "Sarah",
      "context": "Email Sarah about budget",
      "inferred_relationship": "colleague",
      "inferred_role": "works on financial matters"
    }
  ]
}`

const ProfileInferencePrompt = `You are analyzing a user's task history to update the profile of a person they interact with.

Current profile: {{CURRENT_PROFILE}}
Recent interactions: {{INTERACTIONS}}

Update the profile based on new evidence. Increase confidence if evidence is consistent, decrease if contradictory.

Rules:
1. Never make assumptions about sensitive topics (politics, religion, health)
2. Focus on professional context and communication preferences
3. If evidence conflicts with current profile, note the conflict

Output the updated profile JSON.`
```

### 4.4 Background Jobs (Asynq)

```go
// internal/ai/worker.go

const (
    TypeTaskDecompose    = "ai:task:decompose"
    TypeEntityExtract    = "ai:entity:extract"
    TypeProfileUpdate    = "ai:profile:update"
    TypeDecayCleanup     = "ai:decay:cleanup"
    TypeDraftGenerate    = "ai:draft:generate"
)

// Task payloads
type TaskDecomposePayload struct {
    TaskID uuid.UUID `json:"task_id"`
    UserID uuid.UUID `json:"user_id"`
}

type ProfileUpdatePayload struct {
    UserID   uuid.UUID `json:"user_id"`
    EntityID uuid.UUID `json:"entity_id"`
}

type DecayCleanupPayload struct {
    UserID uuid.UUID `json:"user_id"`
}
```

---

## 5. Real-time & Sync

### 5.1 WebSocket Protocol

```go
// internal/websocket/protocol.go

type MessageType string

const (
    MsgTypeSync       MessageType = "sync"
    MsgTypeTaskUpdate MessageType = "task_update"
    MsgTypeAgentAction MessageType = "agent_action"
    MsgTypePing       MessageType = "ping"
    MsgTypePong       MessageType = "pong"
)

type WSMessage struct {
    Type      MessageType     `json:"type"`
    Payload   json.RawMessage `json:"payload"`
    Timestamp time.Time       `json:"ts"`
}

type SyncPayload struct {
    LastSyncedAt time.Time `json:"last_synced_at"`
    DeviceID     string    `json:"device_id"`
}

type TaskUpdatePayload struct {
    TaskID    uuid.UUID `json:"task_id"`
    Operation string    `json:"op"` // create, update, delete
    Data      *Task     `json:"data,omitempty"`
}
```

### 5.2 Sync Strategy

**Client → Server (Push):**
1. Client makes local change, stores in local SQLite
2. Client queues change in `pending_sync` table
3. Background worker sends changes to `/sync/push`
4. Server applies changes, returns server timestamps
5. Client marks changes as synced

**Server → Client (Pull):**
1. Client sends last sync timestamp to `/sync/pull`
2. Server returns all changes since that timestamp
3. Client applies changes to local SQLite
4. Client updates last sync timestamp

**Conflict Resolution:**
- **Last-Write-Wins (LWW):** Default for most fields
- **Vector Clocks:** For complex merges (task ordering)
- **Server Authority:** For computed fields (AI summaries)

---

## 6. Infrastructure

### 6.1 Database Hosting Strategy

**All databases are hosted on Railway** - no local database instances, even for development.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DATABASE HOSTING (RAILWAY)                           │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   LOCAL DEVELOPMENT                        PRODUCTION                       │
│   ───────────────────                      ──────────────                   │
│                                                                             │
│   ┌─────────────────┐                      ┌─────────────────┐              │
│   │ Backend (local) │                      │ Backend         │              │
│   │ Flutter (local) │                      │ (Railway)       │              │
│   └────────┬────────┘                      └────────┬────────┘              │
│            │                                        │                       │
│            │  Internet                              │  Internal             │
│            │                                        │                       │
│            ▼                                        ▼                       │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                         RAILWAY                                      │  │
│   │  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐                │  │
│   │  │ shared_db   │   │ tasks_db    │   │ projects_db │                │  │
│   │  │ PostgreSQL  │   │ PostgreSQL  │   │ PostgreSQL  │                │  │
│   │  └─────────────┘   └─────────────┘   └─────────────┘                │  │
│   │                                                                      │  │
│   │  ┌─────────────┐                                                    │  │
│   │  │ Redis       │  (cache, queues)                                   │  │
│   │  └─────────────┘                                                    │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Why Railway for all environments:**
| Benefit | Description |
|---------|-------------|
| **No local setup** | No PostgreSQL installation needed for developers |
| **Consistent data** | Dev/staging/prod use same database engine version |
| **Team sharing** | Multiple developers can share a dev database |
| **Easy migrations** | Run migrations once, applies to shared dev DB |
| **Free tier** | Railway's free tier covers development needs |

**Environment Strategy:**

| Environment | Database Instance | Usage |
|-------------|-------------------|-------|
| `development` | `flow-dev-shared`, `flow-dev-tasks`, `flow-dev-projects` | Local backend testing |
| `staging` | `flow-staging-*` | Pre-production testing |
| `production` | `flow-prod-*` | Live users |

### 6.2 Environment Variables

```bash
# .env.development (connects to Railway dev databases)

# ══════ DATABASES (Railway) ══════
SHARED_DB_URL=postgresql://flow:xxx@containers.railway.app:5432/flow_shared
TASKS_DB_URL=postgresql://flow:xxx@containers.railway.app:5433/flow_tasks
PROJECTS_DB_URL=postgresql://flow:xxx@containers.railway.app:5434/flow_projects

# ══════ REDIS (Railway) ══════
REDIS_URL=redis://default:xxx@containers.railway.app:6379

# ══════ LOCAL SERVICES (optional) ══════
OLLAMA_HOST=http://localhost:11434  # Local LLM for dev
```

```bash
# .env.production (Railway injects these automatically)

SHARED_DB_URL=${{Postgres-Shared.DATABASE_URL}}
TASKS_DB_URL=${{Postgres-Tasks.DATABASE_URL}}
PROJECTS_DB_URL=${{Postgres-Projects.DATABASE_URL}}
REDIS_URL=${{Redis.REDIS_URL}}
```

### 6.3 Docker Compose (Local Backend Only)

```yaml
# deploy/docker-compose.yml
# Only runs backend services locally - databases are on Railway
version: '3.8'

services:
  # ══════ API GATEWAY ══════
  gateway:
    build:
      context: ./backend
      dockerfile: deploy/Dockerfile.gateway
    ports:
      - "8080:8080"
    env_file:
      - .env.development
    networks:
      - flow-network

  # ══════ DOMAIN SERVICES ══════
  tasks-service:
    build:
      context: ./backend
      dockerfile: deploy/Dockerfile.tasks
    env_file:
      - .env.development
    networks:
      - flow-network

  projects-service:
    build:
      context: ./backend
      dockerfile: deploy/Dockerfile.projects
    env_file:
      - .env.development
    networks:
      - flow-network

  worker:
    build:
      context: ./backend
      dockerfile: deploy/Dockerfile.worker
    env_file:
      - .env.development
    networks:
      - flow-network

  # ══════ LOCAL SERVICES (optional) ══════
  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]  # If available
    networks:
      - flow-network

networks:
  flow-network:
    driver: bridge

volumes:
  ollama_data:
```

### 6.4 Development Overrides

```yaml
# deploy/docker-compose.dev.yml
# Use: docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

version: '3.8'

services:
  gateway:
    volumes:
      - ../backend:/app  # Hot reload
    command: ["air", "-c", ".air.toml"]  # Live reload

  tasks-service:
    volumes:
      - ../backend:/app
    command: ["air", "-c", ".air.tasks.toml"]

  projects-service:
    volumes:
      - ../backend:/app
    command: ["air", "-c", ".air.projects.toml"]
```

### 6.5 Railway Configuration

```toml
# railway.toml
[build]
builder = "dockerfile"
dockerfilePath = "backend/Dockerfile"

[deploy]
startCommand = "./api"
healthcheckPath = "/health"
healthcheckTimeout = 10
restartPolicyType = "on_failure"
restartPolicyMaxRetries = 3
```

### 6.4 Backend Dockerfiles

```dockerfile
# backend/Dockerfile
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git ca-certificates

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY . .

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /api ./cmd/api

# Runtime image
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

COPY --from=builder /api /api

EXPOSE 8080

ENTRYPOINT ["/api"]
```

---

## 7. API Endpoints Overview

### 7.1 Auth
```
POST   /api/v1/auth/register
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
POST   /api/v1/auth/logout
POST   /api/v1/auth/google
POST   /api/v1/auth/apple
POST   /api/v1/auth/microsoft
GET    /api/v1/auth/me
```

### 7.2 Tasks (Shared)
```
GET    /api/v1/tasks                    # List tasks (with filters)
POST   /api/v1/tasks                    # Create task
GET    /api/v1/tasks/:id                # Get task
PUT    /api/v1/tasks/:id                # Update task
DELETE /api/v1/tasks/:id                # Delete task
POST   /api/v1/tasks/:id/complete       # Mark complete
POST   /api/v1/tasks/:id/decompose      # AI decompose
GET    /api/v1/tasks/:id/children       # Get child tasks
```

### 7.3 Projects (Flow Projects only)
```
GET    /api/v1/projects
POST   /api/v1/projects
GET    /api/v1/projects/:id
PUT    /api/v1/projects/:id
DELETE /api/v1/projects/:id
GET    /api/v1/projects/:id/tasks       # Get project WBS
POST   /api/v1/projects/:id/promote     # Promote task to project
```

### 7.4 Entities
```
GET    /api/v1/entities                 # List known entities
GET    /api/v1/entities/:id             # Get entity profile
PUT    /api/v1/entities/:id             # Update entity (user corrections)
GET    /api/v1/entities/:id/tasks       # Tasks mentioning entity
```

### 7.5 Sync
```
POST   /api/v1/sync/push                # Push local changes
POST   /api/v1/sync/pull                # Pull server changes
GET    /api/v1/sync/status              # Sync status
```

### 7.6 Agentic
```
GET    /api/v1/actions                  # List pending actions
GET    /api/v1/actions/:id              # Get action detail
POST   /api/v1/actions/:id/approve      # Approve and send
POST   /api/v1/actions/:id/dismiss      # Dismiss action
PUT    /api/v1/actions/:id              # Edit before sending
```

---

## 8. Monitoring & Observability

### 8.1 Health Check
```go
// GET /health
{
  "status": "healthy",
  "version": "1.0.0",
  "services": {
    "database": "ok",
    "redis": "ok",
    "llm": "ok"
  }
}
```

### 8.2 Metrics (Prometheus)
- `flow_http_requests_total`
- `flow_http_request_duration_seconds`
- `flow_tasks_created_total`
- `flow_ai_requests_total`
- `flow_ai_request_duration_seconds`
- `flow_sync_operations_total`
- `flow_websocket_connections`

### 8.3 Logging (Zerolog)
```go
// Structured JSON logging
{
  "level": "info",
  "time": "2024-01-15T10:30:00Z",
  "caller": "task/handler.go:45",
  "request_id": "abc123",
  "user_id": "uuid",
  "method": "POST",
  "path": "/api/v1/tasks",
  "status": 201,
  "latency_ms": 45,
  "message": "task created"
}
```

---

## Next: See flow-tasks.md and flow-projects.md for app-specific plans.
