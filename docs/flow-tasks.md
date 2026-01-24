# Flow Tasks Documentation

## Overview

Flow Tasks is a personal task management application with AI-powered features. It follows an offline-first architecture with optimistic UI updates and supports multiple platforms (Web, iOS, Android, Desktop).

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Flutter App (flow_tasks)                        │
├─────────────────────────────────────────────────────────────────────────┤
│  Presentation Layer                                                      │
│  ├── HomeScreen (3-panel layout: sidebar, list, detail)                 │
│  ├── LoginScreen, SettingsScreen, SubscriptionScreen                    │
│  └── Widgets (TaskTile, QuickAddBar, TaskDetailPanel, etc.)             │
├─────────────────────────────────────────────────────────────────────────┤
│  State Management (Riverpod)                                             │
│  ├── providers.dart (50+ providers)                                     │
│  ├── TaskActions, AIActions, AttachmentActions                          │
│  └── Auth, Theme, Sync state providers                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  Sync Engine                                                             │
│  ├── LocalTaskStore (optimistic state)                                  │
│  ├── SyncEngine (background sync)                                       │
│  └── SyncOperations (create, update, delete queues)                     │
├─────────────────────────────────────────────────────────────────────────┤
│  API Layer (flow_api package)                                            │
│  ├── FlowApiClient (Dio HTTP client)                                    │
│  ├── TasksService, AuthService                                          │
│  └── Token management, error handling                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  Models (flow_models package)                                            │
│  └── Task, Attachment, User, Subscription, AI models                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Tasks Backend Service                           │
├─────────────────────────────────────────────────────────────────────────┤
│  HTTP Handlers                                                           │
│  ├── handler.go (Task CRUD, attachments, entities)                      │
│  ├── ai_service.go (AI processing)                                      │
│  ├── subscription_handler.go (Plans, checkout)                          │
│  └── admin_handler.go (User/order management)                           │
├─────────────────────────────────────────────────────────────────────────┤
│  Database (PostgreSQL)                                                   │
│  └── tasks, task_attachments, ai_usage, ai_drafts, entity_aliases       │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Backend: Tasks Service

### Database Schema

#### Tasks Table

```sql
CREATE TABLE tasks (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                 UUID NOT NULL,
    title                   VARCHAR(500) NOT NULL,      -- User's original input
    description             TEXT,                        -- User's original input
    ai_cleaned_title        VARCHAR(500),               -- AI-enhanced (null = not cleaned)
    ai_cleaned_description  TEXT,                        -- AI-enhanced (null = not cleaned)
    status                  task_status NOT NULL DEFAULT 'pending',
    priority                SMALLINT NOT NULL DEFAULT 0,
    complexity              SMALLINT DEFAULT 0,          -- 1-10 scale
    due_at                  TIMESTAMPTZ,                 -- Full timestamp with timezone
    has_due_time            BOOLEAN DEFAULT FALSE,       -- true = specific time matters
    completed_at            TIMESTAMPTZ,
    tags                    TEXT[] DEFAULT '{}',         -- Hashtags: #Work, #Personal/Home
    parent_id               UUID REFERENCES tasks(id) ON DELETE CASCADE,
    depth                   SMALLINT NOT NULL DEFAULT 0 CHECK (depth <= 1),
    sort_order              INTEGER DEFAULT 0,
    ai_entities             JSONB DEFAULT '[]',          -- [{type, value}]
    duplicate_of            JSONB DEFAULT '[]',          -- [task_ids]
    duplicate_resolved      BOOLEAN DEFAULT FALSE,
    skip_auto_cleanup       BOOLEAN DEFAULT FALSE,
    version                 INTEGER NOT NULL DEFAULT 1,  -- Sync conflict detection
    device_id               VARCHAR(255),
    synced_at               TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at              TIMESTAMPTZ                  -- Soft delete
);

-- Enums
CREATE TYPE task_status AS ENUM ('pending', 'in_progress', 'completed', 'cancelled', 'archived');
```

**Key Indexes:**
- `idx_tasks_user` - User's tasks (excludes deleted)
- `idx_tasks_user_status` - Status filtering
- `idx_tasks_user_due` - Due date queries (excludes completed)
- `idx_tasks_parent` - Subtask lookup
- `idx_tasks_tags` - GIN index for hashtag search
- `idx_tasks_parent_order` - Subtask ordering

#### Task Attachments Table

```sql
CREATE TABLE task_attachments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id         UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL,
    type            attachment_type NOT NULL,  -- 'link', 'document', 'image'
    name            VARCHAR(255) NOT NULL,
    url             TEXT,                       -- For links or S3 URLs
    mime_type       VARCHAR(100),
    size_bytes      BIGINT,
    thumbnail_url   TEXT,
    metadata        JSONB DEFAULT '{}',
    data            BYTEA,                      -- File content (alternative to URL)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);
```

#### AI Usage Table

```sql
CREATE TABLE ai_usage (
    id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id  UUID NOT NULL,
    feature  ai_feature NOT NULL,
    used_at  DATE NOT NULL DEFAULT CURRENT_DATE,
    count    INTEGER NOT NULL DEFAULT 1,
    UNIQUE (user_id, feature, used_at)
);

CREATE TYPE ai_feature AS ENUM (
    'clean_title', 'clean_description', 'smart_due_date', 'reminder',
    'decompose', 'complexity', 'entity_extraction', 'recurring_detection',
    'auto_group', 'draft_email', 'draft_calendar', 'send_email', 'send_calendar'
);
```

#### Entity Aliases Table

```sql
CREATE TABLE entity_aliases (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    entity_type     VARCHAR(50) NOT NULL,   -- 'person', 'location', 'organization'
    alias_value     VARCHAR(255) NOT NULL,  -- Source value being merged
    canonical_value VARCHAR(255) NOT NULL,  -- Target canonical value
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, entity_type, alias_value)
);
```

---

### Task Model

```go
type Task struct {
    // Core fields
    ID          uuid.UUID
    UserID      uuid.UUID
    Title       string       // User's original input (always preserved)
    Description *string      // User's original input (always preserved)
    Status      Status       // pending, completed, cancelled, archived
    Priority    int          // 0-4 (none, low, medium, high, urgent)

    // Due date handling
    DueAt       *time.Time   // Full timestamp with timezone
    HasDueTime  bool         // true = specific time matters, false = date-only
    CompletedAt *time.Time

    // Hierarchy (max 2 levels)
    ParentID    *uuid.UUID
    Depth       int          // 0 = root, 1 = subtask
    SortOrder   int          // Order within parent

    // AI-enhanced fields (null = not processed)
    AICleanedTitle       *string
    AICleanedDescription *string
    Complexity           int           // 1-10 scale
    Entities             []TaskEntity  // Extracted people, places, orgs

    // Duplicate detection
    DuplicateOf       []string
    DuplicateResolved bool

    // Organization
    Tags []string  // Hashtags like #Work, #Personal/Home

    // Sync
    Version   int
    DeviceID  *string
    SyncedAt  *time.Time

    // Timestamps
    CreatedAt time.Time
    UpdatedAt time.Time
    DeletedAt *time.Time  // Soft delete

    // Flags
    SkipAutoCleanup bool  // Don't auto-process with AI
}

// Display fields (computed)
func (t *Task) GetDisplayTitle() string {
    if t.AICleanedTitle != nil && *t.AICleanedTitle != "" {
        return *t.AICleanedTitle
    }
    return t.Title
}
```

---

### API Endpoints

#### Task CRUD

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/api/v1/tasks` | Create task |
| GET | `/api/v1/tasks` | List all tasks |
| GET | `/api/v1/tasks/:id` | Get single task |
| PUT | `/api/v1/tasks/:id` | Update task |
| DELETE | `/api/v1/tasks/:id` | Soft delete task |
| POST | `/api/v1/tasks/:id/complete` | Mark complete |
| POST | `/api/v1/tasks/:id/uncomplete` | Mark incomplete |

#### Task Views

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/v1/tasks/today` | Due today or overdue |
| GET | `/api/v1/tasks/inbox` | No due date |
| GET | `/api/v1/tasks/upcoming` | Future due dates |
| GET | `/api/v1/tasks/completed` | Completed tasks |

#### Subtasks

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/api/v1/tasks/:id/children` | Create subtask |
| GET | `/api/v1/tasks/:id/children` | List subtasks |
| PUT | `/api/v1/tasks/:id/children/reorder` | Reorder subtasks |

#### Attachments

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/v1/tasks/:id/attachments` | List attachments |
| POST | `/api/v1/tasks/:id/attachments` | Add attachment |
| GET | `/api/v1/tasks/:id/attachments/:aid/download` | Download file |
| DELETE | `/api/v1/tasks/:id/attachments/:aid` | Delete attachment |

#### Entities (Smart Lists)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/api/v1/tasks/entities/merge` | Merge entities |
| DELETE | `/api/v1/tasks/entities/:type/:value` | Remove entity |
| GET | `/api/v1/tasks/entities/:type/:value/aliases` | Get aliases |

---

### Create Task Request/Response

**Request:**
```json
{
  "id": "client-uuid (optional)",
  "title": "Call John about project",
  "description": "Discuss timeline and budget",
  "due_at": "2024-01-15T14:00:00Z",
  "has_due_time": true,
  "priority": 2,
  "tags": ["#Work", "#Calls"],
  "parent_id": null
}
```

**Response:**
```json
{
  "id": "uuid",
  "title": "Call John about project",
  "description": "Discuss timeline and budget",
  "ai_cleaned_title": "Call John - project discussion",
  "ai_cleaned_description": null,
  "display_title": "Call John - project discussion",
  "display_description": "Discuss timeline and budget",
  "status": "pending",
  "priority": 2,
  "due_at": "2024-01-15T14:00:00Z",
  "has_due_time": true,
  "completed_at": null,
  "tags": ["#Work", "#Calls"],
  "parent_id": null,
  "depth": 0,
  "sort_order": 0,
  "complexity": 3,
  "has_children": false,
  "children_count": 0,
  "entities": [
    {"type": "person", "value": "John"}
  ],
  "duplicate_of": [],
  "duplicate_resolved": false,
  "created_at": "2024-01-10T10:00:00Z",
  "updated_at": "2024-01-10T10:00:00Z"
}
```

---

### AI Processing

#### Auto-Processing on Task Create

When a task is created, background AI processing extracts:

1. **Cleaned Title** - Concise, action-oriented (max 10 words)
2. **Summary** - Brief summary if description is long (max 20 words)
3. **Due Date** - ISO 8601 date if mentioned ("tomorrow", "next Monday")
4. **Complexity** - 1-10 scale (1=trivial, 10=complex project)
5. **Entities** - People, places, organizations mentioned
6. **Recurrence** - RRULE if recurring pattern detected

**Important:** AI results stored in separate fields. Original user input is NEVER modified.

#### Manual AI Features

| Feature | Endpoint | Description |
|---------|----------|-------------|
| Decompose | `POST /:id/ai/decompose` | Break into 2-5 subtasks |
| Clean | `POST /:id/ai/clean` | Clean title/description |
| Revert | `POST /:id/ai/revert` | Restore original content |
| Rate | `POST /:id/ai/rate` | Get complexity rating |
| Extract | `POST /:id/ai/extract` | Extract entities |
| Check Duplicates | `POST /:id/ai/check-duplicates` | Find similar tasks |
| Resolve Duplicate | `POST /:id/ai/resolve-duplicate` | Dismiss duplicate warning |
| Draft Email | `POST /:id/ai/email` | Generate email draft |
| Draft Invite | `POST /:id/ai/invite` | Generate calendar draft |

---

### Duplicate Detection System

The duplicate detection feature uses AI to identify tasks that may be duplicates of each other, helping users maintain a clean task list without redundant entries.

#### Database Schema

Two fields on the tasks table support duplicate tracking:

```sql
-- Added by migration 000016_duplicate_detection.up.sql
ALTER TABLE tasks ADD COLUMN duplicate_of JSONB DEFAULT '[]';       -- Array of task IDs
ALTER TABLE tasks ADD COLUMN duplicate_resolved BOOLEAN DEFAULT FALSE;  -- User dismissed warning
```

- **duplicate_of**: JSON array of task UUIDs that this task may be a duplicate of
- **duplicate_resolved**: Boolean flag indicating user has reviewed and dismissed the warning

#### Detection Flow

```
User triggers "Similar" AI action on a task
    ↓
1. Backend receives POST /:id/ai/check-duplicates
    ↓
2. Check daily usage limit (Free: 10/day, Light/Premium: unlimited)
    ↓
3. Fetch user's other tasks (up to 100)
    ↓
4. Filter out:
   - The current task itself
   - Subtasks of the current task (children aren't duplicates)
   - Parent of the current task (if it's a subtask)
    ↓
5. Build comparison list using display titles (AI-cleaned if available)
   Format: "1. [uuid] Task title"
    ↓
6. Send to LLM with strict duplicate detection prompt:
   - Must be THE SAME TASK written differently
   - Must involve same people/entities AND same action/goal
   - "Inform Alice about X" + "Notify Alice about X" = DUPLICATE
   - "Cook beef" + "Tell Alice about onboarding" = NOT DUPLICATE
    ↓
7. LLM returns JSON with duplicate IDs and reasons
    ↓
8. Validate returned UUIDs:
   - Parse and verify UUID format
   - Exclude current task if AI mistakenly included it
   - Exclude cancelled tasks
   - Exclude parent/child relationships
   - Fetch full task objects for valid IDs
    ↓
9. Save valid duplicate IDs to task.duplicate_of field
   Set task.duplicate_resolved = false
    ↓
10. Return response with full task objects for display
```

#### API Request/Response

**Request:** `POST /api/v1/tasks/:id/ai/check-duplicates`

No request body required.

**Response:**
```json
{
  "success": true,
  "data": {
    "task": {
      "id": "current-task-uuid",
      "title": "Call John about project",
      "duplicate_of": ["other-task-uuid-1", "other-task-uuid-2"],
      "duplicate_resolved": false
    },
    "duplicates": [
      {
        "id": "other-task-uuid-1",
        "title": "Phone John re: project discussion",
        "display_title": "Call John - project"
      },
      {
        "id": "other-task-uuid-2",
        "title": "Ring John about the project",
        "display_title": "Contact John - project"
      }
    ],
    "reason": "These tasks all involve calling John about the same project"
  }
}
```

#### Resolution Flow

When user reviews duplicates, they have these options:

```
Similar Tasks Dialog shown
    ↓
Option 1: Delete duplicate task(s)
    - User taps trash icon on a similar task
    - Task is soft-deleted via DELETE /api/v1/tasks/:id
    - Removed from the dialog list
    ↓
Option 2: Keep All / Keep Both
    - User decides these are NOT duplicates
    - POST /:id/ai/resolve-duplicate called
    - Sets duplicate_resolved = true
    - Warning badge disappears from UI
    ↓
Option 3: Close dialog (no action)
    - duplicate_of remains populated
    - duplicate_resolved stays false
    - Warning badge stays visible for later review
```

**Resolve Duplicate Request:** `POST /api/v1/tasks/:id/ai/resolve-duplicate`

No request body required. Simply sets `duplicate_resolved = true`.

#### Frontend Model Integration

```dart
class Task {
  // Duplicate detection fields
  final List<String> duplicateOf;      // IDs of potential duplicates
  final bool duplicateResolved;         // User dismissed warning

  /// Returns true if task has unresolved duplicate warnings
  bool get hasDuplicateWarning => duplicateOf.isNotEmpty && !duplicateResolved;
}
```

#### UI Components

**Warning Badge** (TaskDetailPanel header):
- Orange "Similar" badge appears when `hasDuplicateWarning == true`
- Tapping badge opens dialog showing previously found duplicates
- Looks up tasks from local store by IDs in `duplicate_of`

**Similar Tasks Dialog**:
- Shows current task and all similar tasks side by side
- Displays AI's reason for flagging as duplicates
- Each similar task has:
  - Title and description preview
  - Trash button to delete that task
- Footer buttons:
  - "Keep All" / "Keep Both" - resolves duplicate, keeps all tasks
  - "Close" - dismisses dialog without resolving

**Auto-Resolution**:
- If user clicks badge but all duplicate tasks have been deleted
- System automatically calls resolve-duplicate
- Shows "Similar tasks no longer exist" message

#### AI Prompt Details

The duplicate detection prompt enforces strict matching rules:

```
Find tasks that are TRUE DUPLICATES of this task (same task written differently).

CURRENT TASK: "[title]"
[description if present]

OTHER TASKS (format: NUMBER. [UUID] Title):
1. [uuid-1] Task title one
2. [uuid-2] Task title two
...

STRICT RULES:
- A duplicate means THE SAME TASK written with different words
- MUST involve the same people/entities AND the same action/goal
- "Inform Alice about X" and "Notify Alice about X" = DUPLICATE (same person, same action)
- "Cook beef" and "Tell Alice about onboarding" = NOT DUPLICATE (completely different)
- Return EMPTY duplicates array [] if no true duplicates exist
- Copy the UUID exactly from the [brackets] - do not make up UUIDs

Return ONLY a JSON object:
{
  "duplicates": [
    {"id": "copy-the-exact-uuid-from-brackets", "reason": "why it's the same task"}
  ],
  "reason": "Brief explanation"
}
```

#### Usage Limits by Tier

| Tier | Daily Limit |
|------|-------------|
| Free | 10 checks/day |
| Light | Unlimited |
| Premium | Unlimited |

---

## Frontend: Flutter App

### Package: flow_models

#### Task Model (Dart)

```dart
class Task extends Equatable {
  final String id;
  final String title;              // User's original input
  final String? description;       // User's original input
  final String? aiCleanedTitle;    // AI version (null = not cleaned)
  final String? aiCleanedDescription;
  final TaskStatus status;
  final Priority priority;
  final DateTime? dueAt;
  final bool hasDueTime;
  final DateTime? completedAt;
  final List<String> tags;
  final String? parentId;
  final int depth;
  final int sortOrder;
  final int complexity;
  final bool hasChildren;
  final int childrenCount;
  final List<AIEntity> entities;
  final List<String> duplicateOf;
  final bool duplicateResolved;
  final bool skipAutoCleanup;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Computed properties
  String get displayTitle => aiCleanedTitle ?? title;
  String? get displayDescription => aiCleanedDescription ?? description;
  bool get isCompleted => status == TaskStatus.completed;
  bool get titleWasCleaned => aiCleanedTitle != null && aiCleanedTitle!.isNotEmpty;

  bool get isOverdue {
    if (isCompleted || dueAt == null) return false;
    final now = DateTime.now();
    if (hasDueTime) {
      return dueAt!.isBefore(now);
    } else {
      // Date-only: overdue only if date is strictly before today
      final today = DateTime(now.year, now.month, now.day);
      final dueDate = DateTime(dueAt!.year, dueAt!.month, dueAt!.day);
      return dueDate.isBefore(today);
    }
  }
}
```

#### Enums

```dart
enum TaskStatus { pending, inProgress, completed, cancelled, archived }

enum Priority { none(0), low(1), medium(2), high(3), urgent(4) }

enum AttachmentType { link, document, image }

enum AISetting { auto, ask }  // 'off' converted to 'ask'
```

---

### Package: flow_api

#### API Client Configuration

```dart
class ApiConfig {
  final String sharedServiceUrl;
  final String tasksServiceUrl;
  final String projectsServiceUrl;

  factory ApiConfig.development() => ApiConfig(
    sharedServiceUrl: 'http://localhost:8080/api/v1',
    tasksServiceUrl: 'http://localhost:8081/api/v1',
    projectsServiceUrl: 'http://localhost:8082/api/v1',
  );

  factory ApiConfig.production() => ApiConfig(
    sharedServiceUrl: 'https://api.flowapp.io/shared/v1',
    tasksServiceUrl: 'https://api.flowapp.io/tasks/v1',
    projectsServiceUrl: 'https://api.flowapp.io/projects/v1',
  );
}
```

#### Token Management

```dart
class FlowApiClient {
  String? _accessToken;
  String? _refreshToken;
  final FlutterSecureStorage _storage;

  Future<void> init() async {
    // Load tokens from secure storage on app start
    _accessToken = await _storage.read(key: 'access_token');
    _refreshToken = await _storage.read(key: 'refresh_token');
  }

  Future<void> setTokens(String accessToken, String refreshToken) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  // Auto-refresh on 401 with retry
  Future<bool> _refreshAccessToken() async {
    final response = await _sharedClient.post('/auth/refresh', data: {
      'refresh_token': _refreshToken,
    });
    // Update tokens and retry original request
  }
}
```

#### TasksService Methods

```dart
class TasksService {
  // CRUD
  Future<Task> create({...});
  Future<Task> getById(String id);
  Future<PaginatedResponse<Task>> list({int page, int pageSize});
  Future<Task> update(String id, {...});
  Future<void> delete(String id);

  // Status
  Future<Task> complete(String id);
  Future<Task> uncomplete(String id);

  // Views
  Future<List<Task>> getToday();
  Future<List<Task>> getInbox();
  Future<List<Task>> getUpcoming();
  Future<PaginatedResponse<Task>> getCompleted({...});

  // Subtasks
  Future<Task> createChild(String parentId, {...});
  Future<List<Task>> getChildren(String parentId);
  Future<void> reorderChildren(String parentId, List<String> taskIds);

  // AI
  Future<AIDecomposeResult> aiDecompose(String id);
  Future<Task> aiClean(String id, {String field = 'both'});
  Future<Task> aiRevert(String id);
  Future<AIExtractResult> aiExtract(String id);
  Future<AIDuplicatesResult> aiCheckDuplicates(String id);
  Future<AIRateResult> aiRate(String id);

  // Attachments
  Future<List<Attachment>> getAttachments(String taskId);
  Future<Attachment> createLinkAttachment(String taskId, {...});
  Future<Attachment> uploadFileAttachment(String taskId, {...});
  Future<void> deleteAttachment(String taskId, String attachmentId);

  // Entities
  Future<Map<String, List<SmartListItem>>> getEntities();
  Future<void> mergeEntities(String type, String from, String to);
}
```

---

### State Management (Riverpod)

#### Key Providers

```dart
// API & Services
final apiClientProvider = Provider<FlowApiClient>((ref) => ...);
final tasksServiceProvider = Provider<TasksService>((ref) => ...);

// Authentication
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((ref) => ...);

// Local Storage & Sync
final localTaskStoreProvider = StateNotifierProvider<LocalTaskStore, LocalTaskState>((ref) => ...);
final syncEngineProvider = Provider<SyncEngine>((ref) => ...);

// Task Data
final tasksProvider = Provider<List<Task>>((ref) => ...);  // Merged server + optimistic
final todayTasksProvider = Provider<List<Task>>((ref) => ...);
final next7DaysTasksProvider = Provider<List<Task>>((ref) => ...);
final completedTasksProvider = Provider<List<Task>>((ref) => ...);

// Task Actions
final taskActionsProvider = Provider<TaskActions>((ref) => ...);
final aiActionsProvider = Provider<AIActions>((ref) => ...);

// Selection
final selectedTaskIdProvider = StateProvider<String?>((ref) => null);
final selectedTaskProvider = Provider<Task?>((ref) => ...);

// Lists
final listTreeProvider = Provider<List<TaskList>>((ref) => ...);  // Dynamic hashtag lists
final selectedListIdProvider = StateProvider<String?>((ref) => null);

// Smart Lists (AI entities)
final smartListsProvider = FutureProvider<Map<String, List<SmartListItem>>>((ref) => ...);
final selectedSmartListProvider = StateProvider<SmartListSelection?>((ref) => null);

// Theme
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) => ...);
```

#### TaskActions

```dart
class TaskActions {
  Future<Task> create({
    required String title,
    String? description,
    DateTime? dueAt,
    bool hasDueTime = false,
    int? priority,
    List<String>? tags,
    String? parentId,
  });

  Future<Task> update(String taskId, {
    String? title,
    String? description,
    DateTime? dueAt,
    bool? hasDueTime,
    bool clearDueAt = false,
    int? priority,
    String? status,
    List<String>? tags,
    String? parentId,
  });

  Future<void> complete(String taskId);
  Future<void> uncomplete(String taskId);
  Future<void> delete(String taskId);
  Future<Task> aiRevert(String taskId);
  Future<void> reorderSubtasks(String parentId, List<String> taskIds);
}
```

---

### Sync Engine

#### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        LocalTaskStore                            │
├─────────────────────────────────────────────────────────────────┤
│  serverTasks      - Source of truth (from backend)              │
│  optimisticTasks  - Local changes not yet synced                │
│  deletedTaskIds   - Marked for deletion                         │
│  pendingOperations - Queue of sync operations                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         SyncEngine                               │
├─────────────────────────────────────────────────────────────────┤
│  - Periodic sync every 30 seconds (when online)                 │
│  - Processes pending operations sequentially                    │
│  - Retries failed operations up to 3 times                      │
│  - Connectivity monitoring (mobile/desktop)                     │
└─────────────────────────────────────────────────────────────────┘
```

#### Optimistic Update Flow

```
1. User creates task
   ↓
2. LocalTaskStore.createTask()
   - Generate client UUID
   - Create optimistic Task
   - Queue SyncOperation.create
   - Update state immediately
   ↓
3. UI reflects change instantly
   ↓
4. SyncEngine processes operation (async)
   - Send to backend
   - On success: Move optimistic → server
   - On error: Retry up to 3 times
   ↓
5. Server version merged back
```

#### Smart AI Field Preservation

When updating a task, AI-cleaned fields are only cleared if:
1. The field IS being updated (title != null)
2. AND new value differs from original (title != existing.title)
3. AND new value differs from AI version (title != existing.aiCleanedTitle)

This preserves AI edits when user focuses/blurs without changes.

---

### UI Screens

#### HomeScreen (3-Panel Layout)

```
┌──────────────┬────────────────────────────┬──────────────────┐
│   Sidebar    │       Task List            │   Detail Panel   │
│              │                            │                  │
│ • Today      │ ┌────────────────────────┐ │ Task Title       │
│ • Next 7d    │ │ Overdue                │ │ Description      │
│ • All        │ │  • Task 1              │ │ Due Date/Time    │
│ • Completed  │ │  • Task 2              │ │ Priority         │
│ • Trash      │ ├────────────────────────┤ │ Tags             │
│              │ │ Today                  │ │ Subtasks         │
│ My Lists     │ │  • Task 3              │ │ Attachments      │
│ • #Work      │ │  • Task 4              │ │                  │
│ • #Personal  │ ├────────────────────────┤ │ AI Actions       │
│              │ │ Tomorrow               │ │ • Clean          │
│ Smart Lists  │ │  • Task 5              │ │ • Decompose      │
│ • John (5)   │ └────────────────────────┘ │ • Extract        │
│ • NYC (3)    │                            │                  │
│              │ [+ Add a task...]          │                  │
└──────────────┴────────────────────────────┴──────────────────┘
```

**Responsive Breakpoints:**
- Wide (>700px): Full 3-panel layout
- Narrow (<700px): Sidebar collapses, detail as bottom sheet

#### TaskTile Features

- Priority color indicator (checkbox border)
- Strikethrough animation on completion (0.5s)
- Fly-away animation after strikethrough
- Due date display (Today, Tomorrow, Jan 15)
- Overdue indicator (red text)
- Subtask count badge
- Entity chips (Person, Location)
- Drag-and-drop to create subtasks
- Swipe-to-trash gesture

#### TaskDetailPanel Features

- Dual controller: display (AI-cleaned) vs. raw
- Debounced auto-save (800ms)
- Due date/time picker (Google Tasks style)
- AI cooking dialog for long operations
- Image paste with markdown reference
- Attachment upload and list
- Subtask management

---

### Theme System

#### Design Language

Inspired by Bear notes app:
- Warm, human-centric colors
- Flat design (no elevation)
- Subtle shadows and borders
- System font with comfortable line height

#### Color Palette

```dart
// Primary (Bear's signature red-orange)
primary: Color(0xFFDA4453)
primaryLight: Color(0xFFED5565)
primaryDark: Color(0xFFC43D4B)

// Light Theme
background: Color(0xFFFAFAFA)
surface: Color(0xFFFFFFFF)
textPrimary: Color(0xFF2C2C2E)
textSecondary: Color(0xFF636366)

// Dark Theme
background: Color(0xFF1C1C1E)
surface: Color(0xFF2C2C2E)
textPrimary: Color(0xFFF2F2F7)
textSecondary: Color(0xFFAEAEB2)

// Priority Colors
urgent: Color(0xFFFF6B6B)  // Red
high: Color(0xFFFFAB4A)    // Orange
medium: Color(0xFFFFD93D)  // Yellow
low: Color(0xFF6BCB77)     // Green
```

---

### Dynamic Lists (Hashtags)

Tasks can include hashtags in their tags field:
- `#Work` - Root level list
- `#Work/Projects` - Nested list
- `#Personal/Home` - Two-level nesting supported

Lists are dynamically extracted from all tasks:

```dart
final listTreeProvider = Provider<List<TaskList>>((ref) {
  final tasks = ref.watch(tasksProvider);
  // Extract all unique hashtags
  // Build tree structure
  // Count tasks per hashtag
  return buildListTree(tasks);
});
```

---

### Smart Lists (AI Entities)

AI extracts entities from task content:
- **Person**: "Call John", "Email Sarah"
- **Location**: "Meeting in NYC", "Flight to London"
- **Organization**: "Meeting with Microsoft", "Call CDIMEX"

Smart Lists aggregate entities:
```dart
final smartListsProvider = FutureProvider<Map<String, List<SmartListItem>>>((ref) async {
  final service = ref.watch(tasksServiceProvider);
  return service.getEntities();
  // Returns: {person: [{value: "John", count: 5}, ...], ...}
});
```

Entity aliases allow merging:
```dart
// "Jon" and "John" can be merged
await service.mergeEntities('person', 'Jon', 'John');
// Tasks not modified - aliases resolved on display
```

---

## Data Flow Summary

### Create Task Flow

```
User types "Call John tomorrow"
    ↓
QuickAddBar.onSubmit()
    ↓
ref.read(taskActionsProvider).create(title: "Call John tomorrow")
    ↓
LocalTaskStore.createTask()
  - Generate UUID
  - Create optimistic Task
  - Queue SyncOperation.create
    ↓
UI updates instantly (optimistic)
    ↓
SyncEngine.syncNow() (background)
  - POST /api/v1/tasks
    ↓
Backend processes:
  - Create task record
  - AI auto-processing (async):
    - Clean title → "Call John"
    - Extract due date → tomorrow
    - Extract entity → {type: "person", value: "John"}
    ↓
LocalTaskStore.onSyncSuccess()
  - Replace optimistic with server version
    ↓
UI updates with AI-enhanced data
```

### Complete Task Flow

```
User taps checkbox
    ↓
ExpandableTaskTile.onComplete()
    ↓
ref.read(taskActionsProvider).complete(taskId)
    ↓
Optimistic update: status = completed
    ↓
Strikethrough animation (0.5s)
    ↓
Fly-away animation (0.5s)
    ↓
Backend: POST /api/v1/tasks/:id/complete
    ↓
Task moves to Completed group
```

---

## Configuration

### Environment Variables (Backend)

```bash
# Database
DATABASE_URL=postgres://user:pass@host:5432/tasks_db

# Shared Service Connection
SHARED_SERVICE_URL=http://localhost:8080

# LLM (via shared service)
ANTHROPIC_API_KEY=xxx
```

### Environment Variables (Flutter)

```bash
# API URLs
SHARED_API_URL=http://localhost:8080/api/v1
TASKS_API_URL=http://localhost:8081/api/v1
```

---

## Summary

Flow Tasks provides:

1. **Offline-First Architecture** - Optimistic updates with background sync
2. **AI-Enhanced Tasks** - Automatic title cleaning, entity extraction, due date parsing
3. **Smart Organization** - Dynamic hashtag lists + AI-powered Smart Lists
4. **Multi-Platform** - Flutter app for Web, iOS, Android, Desktop
5. **Subscription Tiers** - Free (basic), Light (more AI), Premium (unlimited)
