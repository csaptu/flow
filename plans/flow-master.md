# Flow Project - Master Plan

## Overview

**Flow** is an AI-powered productivity suite consisting of two apps with independent backends:
- **Flow Tasks** - Simple 2-layer task management (like Google Tasks + AI)
  - Personal tasks + "Assigned to Me" view (from projects)
- **Flow Projects** - Full project management with Waterfall/Gantt (like MS Project + AI)

**Key Architecture Decisions:**
- 3 independent domains (shared, tasks, projects)
- 3 separate databases (shared_db, tasks_db, projects_db)
- Personal → Project promotion is a **COPY** (not move)
- No sync between personal and project tasks after promotion

## Detailed Plans

| Document | Description |
|----------|-------------|
| [flow-shared.md](./flow-shared.md) | Backend, Database, Auth, AI Layer, Infrastructure |
| [flow-tasks.md](./flow-tasks.md) | Flow Tasks app - Flutter implementation |
| [flow-projects.md](./flow-projects.md) | Flow Projects app - Flutter implementation |

---

## Technology Stack Summary

| Layer | Technology |
|-------|------------|
| **Backend** | Go 1.22 + Fiber v2 |
| **Database** | PostgreSQL 16 on Railway (JSONB, ltree, pgvector) |
| **Cache/Queue** | Redis 7 on Railway (Streams for messaging) |
| **Frontend** | Flutter 3.x (single codebase for all platforms) |
| **State** | Riverpod + Freezed |
| **Local DB** | Drift (SQLite) for offline-first client storage |
| **Auth** | JWT + OAuth (Google, Apple, Microsoft) |
| **LLM** | Claude (primary) + Gemini + OpenAI + Ollama |
| **Hosting** | Railway (all DBs + backend), no local DB even for dev |

---

## Confirmed Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Backend Language | **Go** | Performance, concurrency for real-time sync |
| Frontend Framework | **Flutter** | Single codebase for iOS, Android, Web, Desktop |
| Database | **PostgreSQL on Railway** | JSONB flexibility + no local DB setup needed |
| Database Strategy | **Railway for all envs** | Dev/staging/prod all use Railway-hosted DBs |
| Offline Strategy | **Full offline-first** | Local SQLite (Drift), background sync, conflict resolution |
| OAuth Providers | **Google + Apple + Microsoft** | Enterprise-ready, App Store compliance |
| Message Queue | **Redis Streams** | Simple, already using Redis for cache |
| LLM Strategy | **Multi-provider + self-hosted** | Flexibility, privacy option with Ollama |

---

## Backend Architecture (Domain-Driven)

**3 Independent Domains, 3 Databases:**

| Domain | Database | Responsibilities |
|--------|----------|------------------|
| **Shared** | `shared_db` | Users, Auth, Entities, AI decisions |
| **Tasks** | `tasks_db` | Personal tasks, sync, 2-layer limit |
| **Projects** | `projects_db` | Projects, WBS nodes, dependencies, team |

**Key Design Principles:**
- Each domain deploys independently
- Each domain owns its database exclusively
- Cross-domain communication via REST APIs (not shared DB access)
- Common base models in `common/`, domain extensions in domain folders

```
┌─────────────────────────────────────────────────────────────────────┐
│                          API Gateway                                 │
│                      (Routes by path prefix)                         │
└───────────┬─────────────────────┬─────────────────────┬─────────────┘
            │                     │                     │
  /api/v1/auth/*          /api/v1/tasks/*      /api/v1/projects/*
  /api/v1/users/*
  /api/v1/entities/*
            │                     │                     │
            ▼                     ▼                     ▼
   ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
   │ shared-service  │   │ tasks-service   │   │projects-service │
   │                 │   │                 │   │                 │
   │ - Auth          │   │ - Personal CRUD │   │ - Project CRUD  │
   │ - Users         │   │ - 2-layer limit │   │ - WBS nodes     │
   │ - Entities      │   │ - Sync/offline  │   │ - Dependencies  │
   │ - AI orchestr.  │   │ - Promotion API │   │ - Team/assign   │
   └────────┬────────┘   └────────┬────────┘   └────────┬────────┘
            │                     │                     │
            ▼                     ▼                     ▼
   ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
   │   shared_db     │   │    tasks_db     │   │  projects_db    │
   │                 │   │                 │   │                 │
   │ - users         │   │ - tasks         │   │ - projects      │
   │ - refresh_tokens│   │                 │   │ - wbs_nodes     │
   │ - entities      │   │                 │   │ - project_members│
   │ - ai_decisions  │   │                 │   │ - dependencies  │
   └─────────────────┘   └─────────────────┘   └─────────────────┘
```

**Cross-Domain Data Flow:**
```
Flow Tasks App                              Flow Projects App
     │                                            │
     ▼                                            ▼
┌─────────┐  "Assigned to Me"  ┌──────────────────────┐
│ tasks   │ ◄───── REST API ───│ projects-service     │
│ service │                    │ GET /users/:id/      │
└────┬────┘                    │     assigned-tasks   │
     │                         └──────────────────────┘
     │ Promote Task
     │ POST /tasks/:id/promote
     │
     ▼
┌──────────────────────────────────────────────────────┐
│ 1. Copy task data to projects_db.wbs_nodes           │
│ 2. If keep_personal: update tasks_db.tasks with link │
│ 3. If !keep_personal: soft-delete tasks_db.tasks     │
└──────────────────────────────────────────────────────┘
```

---

## Monorepo Structure

```
/flow
├── backend/                           # Go backend (domain-driven)
│   │
│   ├── common/                        # ═══ SHARED CODE (imported by all) ═══
│   │   ├── go.mod                     # module github.com/user/flow/common
│   │   ├── models/                    # Base models (embedded by domains)
│   │   │   ├── task_base.go           # TaskBase struct
│   │   │   ├── user.go                # User struct
│   │   │   └── types.go               # Status, Priority enums
│   │   ├── interfaces/                # Repository contracts
│   │   ├── errors/                    # Shared error types
│   │   └── dto/                       # Shared request/response types
│   │
│   ├── shared/                        # ═══ SHARED DOMAIN SERVICE ═══
│   │   ├── go.mod                     # module github.com/user/flow/shared
│   │   ├── cmd/
│   │   │   └── main.go                # shared-service entrypoint
│   │   ├── auth/                      # JWT, OAuth handlers
│   │   ├── user/                      # User CRUD
│   │   ├── entity/                    # Entity Ledger
│   │   ├── ai/                        # LLM orchestration
│   │   ├── database/
│   │   │   ├── postgres.go            # Connection to shared_db
│   │   │   ├── migrations/            # shared_db migrations
│   │   │   └── queries/               # sqlc queries
│   │   ├── Dockerfile                 # Builds shared-service
│   │   └── .env.example
│   │
│   ├── tasks/                         # ═══ TASKS DOMAIN SERVICE ═══
│   │   ├── go.mod                     # module github.com/user/flow/tasks
│   │   ├── cmd/
│   │   │   └── main.go                # tasks-service entrypoint
│   │   ├── models/
│   │   │   └── task.go                # Embeds common.TaskBase + extensions
│   │   ├── handler.go                 # HTTP handlers
│   │   ├── service.go                 # Business logic
│   │   ├── repository.go              # DB operations
│   │   ├── promotion.go               # Promote to project (calls projects API)
│   │   ├── rules/
│   │   │   └── depth_limit.go         # 2-layer enforcement
│   │   ├── database/
│   │   │   ├── postgres.go            # Connection to tasks_db
│   │   │   ├── migrations/            # tasks_db migrations
│   │   │   └── queries/               # sqlc queries
│   │   ├── Dockerfile                 # Builds tasks-service
│   │   └── .env.example
│   │
│   ├── projects/                      # ═══ PROJECTS DOMAIN SERVICE ═══
│   │   ├── go.mod                     # module github.com/user/flow/projects
│   │   ├── cmd/
│   │   │   └── main.go                # projects-service entrypoint
│   │   ├── models/
│   │   │   ├── project.go             # Project struct
│   │   │   ├── wbs_node.go            # Embeds common.TaskBase + extensions
│   │   │   └── dependency.go          # Task dependency
│   │   ├── handler.go                 # HTTP handlers
│   │   ├── service.go                 # Business logic
│   │   ├── repository.go              # DB operations
│   │   ├── waterfall/                 # Critical path, scheduling
│   │   ├── gantt/                     # Gantt chart data generation
│   │   ├── team/                      # Team & assignment logic
│   │   ├── database/
│   │   │   ├── postgres.go            # Connection to projects_db
│   │   │   ├── migrations/            # projects_db migrations
│   │   │   └── queries/               # sqlc queries
│   │   ├── Dockerfile                 # Builds projects-service
│   │   └── .env.example
│   │
│   ├── gateway/                       # ═══ API GATEWAY (optional) ═══
│   │   ├── go.mod
│   │   ├── cmd/
│   │   │   └── main.go
│   │   ├── routes.go                  # Path-based routing to services
│   │   └── Dockerfile
│   │
│   ├── pkg/                           # ═══ SHARED PACKAGES ═══
│   │   ├── llm/                       # Multi-provider LLM client
│   │   ├── middleware/                # Auth, CORS, logging
│   │   ├── config/                    # Config loading
│   │   └── httputil/                  # Response helpers
│   │
│   └── deploy/
│       ├── docker-compose.yml         # All services + 3 DBs
│       ├── docker-compose.dev.yml     # Dev overrides
│       └── railway/                   # Railway configs per service
│
├── apps/                              # Flutter apps
│   ├── flow_tasks/                    # Personal + Assigned view
│   ├── flow_projects/                 # Full PM app
│   └── flow_shared/                   # Shared Flutter widgets
│
├── packages/                          # Shared Dart packages
│   ├── flow_api/                      # API client (calls all 3 services)
│   ├── flow_models/                   # Dart models (mirrors backend)
│   └── flow_database/                 # Drift schemas for offline
│
└── melos.yaml                         # Monorepo management
```

**Independent Deployment Guarantee:**
```
┌────────────────────────────────────────────────────────────────────────┐
│ Each domain is a SEPARATE Go module with its own:                      │
│  • go.mod           (own dependencies)                                 │
│  • cmd/main.go      (own entrypoint)                                   │
│  • Dockerfile       (own container)                                    │
│  • database/        (own DB connection & migrations)                   │
│  • .env.example     (own config)                                       │
│                                                                        │
│ Deploy independently to Railway/Fly/K8s as separate services           │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Foundation
- [ ] Initialize Go backend with Fiber
- [ ] PostgreSQL schema + migrations
- [ ] Auth system (JWT + OAuth)
- [ ] Basic API structure
- [ ] Docker Compose setup

### Phase 2: Flow Tasks MVP
- [ ] Flutter project setup with Riverpod
- [ ] Drift local database
- [ ] Task CRUD (2-layer limit)
- [ ] Offline-first sync
- [ ] AI task decomposition

### Phase 3: Flow Projects MVP
- [ ] Project CRUD
- [ ] WBS tree view
- [ ] Basic Gantt chart
- [ ] Task promotion from Flow Tasks

### Phase 4: Advanced Features
- [ ] Dependencies (all types)
- [ ] Critical path calculation
- [ ] Team collaboration
- [ ] AI estimation & risk analysis
- [ ] Agentic actions (draft emails)

### Phase 5: Polish & Launch
- [ ] Entity Ledger (people inference)
- [ ] Decision learning (adapter training)
- [ ] Push notifications
- [ ] App Store submission

---

## Key Integration Points

```
┌─────────────┐     Promote      ┌─────────────────┐
│ Flow Tasks  │ ───────────────► │  Flow Projects  │
│ (2 layers)  │                  │  (unlimited)    │
│             │ ◄─────────────── │                 │
└─────────────┘     Export       └─────────────────┘
       │                                  │
       │           ┌──────────┐           │
       └──────────►│ Backend  │◄──────────┘
                   │   API    │
                   └────┬─────┘
                        │
              ┌─────────┴─────────┐
              │                   │
        ┌─────┴─────┐      ┌─────┴─────┐
        │PostgreSQL │      │   Redis   │
        │  (Data)   │      │ (Cache/Q) │
        └───────────┘      └───────────┘
```

---

## Verification Checklist

After implementation, verify:

1. **Backend**
   - `docker-compose up` starts all services
   - `curl localhost:8080/health` returns healthy
   - Database migrations applied

2. **Flow Tasks**
   - Create task → appears in list
   - Complete task → syncs to server
   - Offline mode → create task → reconnect → syncs
   - AI decomposition generates steps

3. **Flow Projects**
   - Create project → WBS view works
   - Add dependencies → Gantt shows lines
   - Promote task from Flow Tasks → creates project

4. **Cross-platform**
   - iOS/Android simulators work
   - Web build works
   - Desktop builds work (macOS, Windows)

---

## Next Command

To begin implementation, run:

```bash
# Initialize the monorepo
mkdir -p backend/cmd/api backend/internal backend/pkg backend/migrations
mkdir -p apps/flow_tasks apps/flow_projects apps/flow_shared
mkdir -p packages/flow_api packages/flow_models packages/flow_database
mkdir -p deploy docs

# Initialize Go module
cd backend && go mod init github.com/yourusername/flow
```
