# Flow Shared Services Documentation

## Overview

The Shared Services layer provides cross-domain functionality for the Flow platform, including authentication, user management, subscriptions, payment processing, and AI-powered features. This documentation covers the complete data flow from database to API.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Shared Service                            │
├─────────────────────────────────────────────────────────────────┤
│  Handlers (HTTP Layer)                                           │
│  ├── auth/handler.go      - Authentication endpoints             │
│  ├── user/handler.go      - User profile management              │
│  ├── subscription/handler.go - Subscription management           │
│  └── ai/handler.go        - AI task processing                   │
├─────────────────────────────────────────────────────────────────┤
│  Services (Business Logic)                                       │
│  ├── ai/service.go        - AI feature orchestration             │
│  ├── ai/context_builder.go - AI prompt construction              │
│  ├── ai/post_processor.go - AI response parsing                  │
│  └── ai/profile_refresh.go - User profile AI analysis            │
├─────────────────────────────────────────────────────────────────┤
│  Repository (Data Access)                                        │
│  ├── user.go, admin.go, subscription.go, plan.go                │
│  ├── order.go, payment.go, ai_config.go                         │
│  └── user_ai_profile.go, task.go (cross-domain)                 │
├─────────────────────────────────────────────────────────────────┤
│  Database (PostgreSQL)                                           │
│  └── users, subscriptions, orders, ai_prompt_configs, etc.      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Database Schema

### Tables Overview

| Table | Purpose |
|-------|---------|
| `users` | User accounts with OAuth support |
| `refresh_tokens` | JWT refresh token storage |
| `subscriptions` | User subscription status |
| `subscription_plans` | Available plans (Free, Light, Premium) |
| `orders` | Purchase order tracking |
| `payment_history` | Payment audit trail |
| `admin_users` | Admin email whitelist |
| `ai_prompt_configs` | Configurable AI instructions |
| `user_ai_profiles` | Per-user AI context data |

### Users Table

```sql
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           VARCHAR(255) NOT NULL UNIQUE,
    email_verified  BOOLEAN DEFAULT FALSE,
    password_hash   TEXT,
    name            VARCHAR(255) NOT NULL,
    avatar_url      TEXT,
    google_id       VARCHAR(255) UNIQUE,
    apple_id        VARCHAR(255) UNIQUE,
    microsoft_id    VARCHAR(255) UNIQUE,
    settings        JSONB DEFAULT '{}',
    ai_profile      JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    last_login_at   TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ
);
```

**Indexes:**
- `idx_users_email` - Email lookup (excludes soft-deleted)
- `idx_users_google_id`, `idx_users_apple_id`, `idx_users_microsoft_id` - OAuth lookups

### Subscriptions Table

```sql
CREATE TABLE subscriptions (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                 UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    tier                    subscription_tier NOT NULL DEFAULT 'free',
    status                  subscription_status NOT NULL DEFAULT 'active',
    provider                payment_provider,
    provider_subscription_id VARCHAR(255),
    provider_customer_id    VARCHAR(255),
    current_period_start    TIMESTAMPTZ,
    current_period_end      TIMESTAMPTZ,
    grace_period_end        TIMESTAMPTZ,
    cancel_at_period_end    BOOLEAN DEFAULT FALSE,
    cancelled_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

-- Enums
CREATE TYPE subscription_tier AS ENUM ('free', 'light', 'premium');
CREATE TYPE subscription_status AS ENUM ('active', 'grace_period', 'expired', 'cancelled');
CREATE TYPE payment_provider AS ENUM ('apple', 'google', 'paddle');
```

### Subscription Plans Table

```sql
CREATE TABLE subscription_plans (
    id                  VARCHAR(50) PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    tier                subscription_tier NOT NULL,
    price_monthly_cents INTEGER NOT NULL,
    price_yearly_cents  INTEGER,
    currency            VARCHAR(3) DEFAULT 'USD',
    features            JSONB DEFAULT '[]',
    paddle_price_id     VARCHAR(100),
    apple_product_id    VARCHAR(100),
    google_product_id   VARCHAR(100),
    ai_calls_per_day    INTEGER DEFAULT 0,  -- -1 = unlimited
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);
```

**Seeded Plans:**
| ID | Tier | Monthly Price | AI Calls/Day |
|----|------|---------------|--------------|
| free | free | $0 | 5 |
| light_monthly | light | $4.99 | 50 |
| light_yearly | light | $47.88/yr | 50 |
| premium_monthly | premium | $9.99 | unlimited |
| premium_yearly | premium | $99.96/yr | unlimited |

### User AI Profiles Table

```sql
CREATE TABLE user_ai_profiles (
    user_id                 UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,

    -- Editable fields (admin can modify)
    identity_summary        TEXT,
    communication_style     TEXT,
    work_context           TEXT,
    personal_context       TEXT,
    social_graph           TEXT,
    locations_context      TEXT,
    routine_patterns       TEXT,
    task_style_preferences TEXT,
    goals_and_priorities   TEXT,

    -- Auto-generated fields (AI refreshes)
    recent_activity_summary TEXT,
    current_focus          TEXT,
    upcoming_commitments   TEXT,

    -- Refresh tracking
    last_refreshed_at      TIMESTAMPTZ DEFAULT NOW(),
    refresh_trigger        VARCHAR(50),
    tasks_since_refresh    INTEGER DEFAULT 0,

    created_at             TIMESTAMPTZ DEFAULT NOW(),
    updated_at             TIMESTAMPTZ DEFAULT NOW()
);
```

### AI Prompt Configs Table

```sql
CREATE TABLE ai_prompt_configs (
    key         VARCHAR(100) PRIMARY KEY,
    value       TEXT NOT NULL,
    description TEXT,
    updated_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_by  VARCHAR(255)
);
```

**Key Configurations:**
| Key | Purpose |
|-----|---------|
| `clean_title_instruction` | How to clean task titles |
| `summary_instruction` | How to summarize descriptions |
| `complexity_instruction` | Complexity rating scale (1-10) |
| `due_date_instruction` | Due date extraction rules |
| `entities_instruction` | Entity types to extract |
| `decompose_rules` | Task decomposition guidelines |
| `system_first_context` | System prompt for AI assistant |

---

## Common Types & Models

### File: `backend/common/models/types.go`

#### Status Enum
```go
const (
    StatusPending    Status = "pending"
    StatusInProgress Status = "in_progress"
    StatusCompleted  Status = "completed"
    StatusCancelled  Status = "cancelled"
    StatusArchived   Status = "archived"
)
```

#### Priority Enum
```go
const (
    PriorityNone   Priority = 0
    PriorityLow    Priority = 1
    PriorityMedium Priority = 2
    PriorityHigh   Priority = 3
    PriorityUrgent Priority = 4
)
```

#### AISetting Enum
```go
const (
    AISettingAuto AISetting = "auto"  // AI runs automatically
    AISettingAsk  AISetting = "ask"   // AI suggests, user approves
    AISettingOff  AISetting = "off"   // Feature disabled
)
```

### File: `backend/common/models/user.go`

#### User Model
```go
type User struct {
    ID            uuid.UUID
    Email         string
    EmailVerified bool
    PasswordHash  *string
    Name          string
    AvatarURL     *string
    GoogleID      *string
    AppleID       *string
    MicrosoftID   *string
    Settings      json.RawMessage  // UserSettings
    AIProfile     json.RawMessage  // AIUserProfile
    CreatedAt     time.Time
    UpdatedAt     time.Time
    LastLoginAt   *time.Time
    DeletedAt     *time.Time
}
```

#### UserSettings
```go
type UserSettings struct {
    Theme         string         // "light", "dark", "system"
    Notifications bool
    Timezone      string         // e.g., "America/Los_Angeles"
    Language      string         // e.g., "en", "vi"
    AIPreferences AIPreferences
}
```

#### AIPreferences
```go
type AIPreferences struct {
    CleanTitle          AISetting  // Auto-clean task titles
    CleanDescription    AISetting  // Auto-clean descriptions
    Decompose           AISetting  // Decompose tasks into subtasks
    EntityExtraction    AISetting  // Extract entities from tasks
    DuplicateCheck      AISetting  // Detect duplicate tasks
    RecurringDetection  AISetting  // Detect recurring patterns
    SendEmail           AISetting  // Send emails automatically
    SendCalendar        AISetting  // Create calendar events
}
```

### File: `backend/common/dto/responses.go`

#### Standard API Response
```go
type APIResponse struct {
    Success bool        `json:"success"`
    Data    interface{} `json:"data,omitempty"`
    Error   *APIError   `json:"error,omitempty"`
    Meta    *APIMeta    `json:"meta,omitempty"`
}

type APIError struct {
    Code    string                 `json:"code"`
    Message string                 `json:"message"`
    Details map[string]interface{} `json:"details,omitempty"`
}

type APIMeta struct {
    Page       int   `json:"page"`
    PageSize   int   `json:"page_size"`
    TotalCount int64 `json:"total_count"`
    TotalPages int   `json:"total_pages"`
}
```

---

## API Endpoints

### Authentication (`/api/v1/auth`)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/auth/register` | Create new account |
| POST | `/auth/login` | Email/password login |
| POST | `/auth/dev-login` | Dev-only quick login |
| POST | `/auth/refresh` | Refresh access token |
| POST | `/auth/logout` | Logout (revoke token) |
| POST | `/auth/google` | Google OAuth login |
| POST | `/auth/apple` | Apple Sign-In login |
| GET | `/auth/me` | Get current user |
| PUT | `/auth/me` | Update profile |

#### Register Request
```json
{
  "email": "user@example.com",
  "password": "min8chars",
  "name": "User Name"
}
```

#### Login Response
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "email_verified": false,
    "name": "User Name",
    "avatar_url": "https://...",
    "created_at": "2024-01-01T00:00:00Z",
    "updated_at": "2024-01-01T00:00:00Z"
  },
  "access_token": "JWT token",
  "refresh_token": "refresh token hash",
  "expires_at": "2024-01-01T01:00:00Z"
}
```

### Subscriptions (`/api/v1`)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/subscriptions/:user_id` | Get user subscription |
| GET | `/plans` | List subscription plans |
| GET | `/plans/:plan_id` | Get plan details |

### AI Features (`/api/v1/tasks/:id/ai`)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/:id/ai/decompose` | Break task into subtasks |
| POST | `/:id/ai/clean` | Clean title/description |
| POST | `/:id/ai/revert` | Revert AI-cleaned content |
| POST | `/:id/ai/rate` | Rate task complexity |
| POST | `/:id/ai/extract` | Extract entities |
| POST | `/:id/ai/remind` | Suggest reminder time |
| POST | `/:id/ai/email` | Draft email from task |
| POST | `/:id/ai/invite` | Create calendar draft |
| POST | `/:id/ai/check-duplicates` | Find duplicates |
| POST | `/:id/ai/resolve-duplicate` | Mark resolved |
| GET | `/entities` | Get all entities (Smart Lists) |
| DELETE | `/:id/entities/:type/:value` | Remove entity |

### AI Management (`/api/v1/ai`)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/usage` | Get AI usage stats |
| GET | `/tier` | Get user tier + limits |
| GET | `/drafts` | Get pending drafts |
| POST | `/drafts/:id/approve` | Approve draft |
| DELETE | `/drafts/:id` | Delete draft |

---

## Business Logic

### Authentication Flow

```
1. User submits credentials
   ↓
2. Handler validates input
   ↓
3. Repository looks up user by email
   ↓
4. Password verified with bcrypt
   ↓
5. JWT access token generated (configurable expiry)
   ↓
6. Refresh token hash stored in DB
   ↓
7. last_login_at updated
   ↓
8. AuthResponse returned to client
```

### Token Refresh Flow

```
1. Client sends refresh_token
   ↓
2. Handler hashes token
   ↓
3. Repository validates: not revoked, not expired
   ↓
4. Old token revoked (rotation)
   ↓
5. New token pair generated
   ↓
6. Response returned
```

### OAuth Flow (Google/Apple)

```
1. Client authenticates with provider (Google/Apple)
   ↓
2. Client sends ID token to backend
   ↓
3. Backend verifies token with provider
   ↓
4. Check if user exists by provider ID
   ↓
5. If not, check if email exists (account linking)
   ↓
6. Create new user or link provider to existing
   ↓
7. Generate tokens and return
```

### Subscription Tier System

| Tier | AI Calls/Day | Features |
|------|--------------|----------|
| Free | 5 | Clean title (20), Clean description (20), Duplicate check (10) |
| Light | 50 | + Decompose (30), Entity extraction, Email drafts (10), Calendar drafts (10) |
| Premium | Unlimited | All features unlimited |

### AI Feature Usage Tracking

```go
// Check and increment usage
func (s *AIService) CheckAndIncrementUsage(ctx context.Context, userID uuid.UUID, feature string) (bool, error) {
    tier := repository.GetUserTier(ctx, userID)
    limit := s.getFeatureLimit(tier, feature)

    if limit == -1 {
        // Unlimited - allow and increment
        repository.IncrementAIUsage(ctx, userID, feature)
        return true, nil
    }

    usage := repository.GetAIUsage(ctx, userID)
    if usage[feature] >= limit {
        return false, nil  // Rate limited
    }

    repository.IncrementAIUsage(ctx, userID, feature)
    return true, nil
}
```

### User AI Profile Refresh

**Triggers:**
1. New user (no profile exists)
2. Task milestone: `tasks_since_refresh >= 10`
3. Scheduled: `hours_since_refresh >= 24`

**Profile Fields:**
- **Editable (9 fields):** identity_summary, communication_style, work_context, personal_context, social_graph, locations_context, routine_patterns, task_style_preferences, goals_and_priorities
- **Auto-generated (3 fields):** recent_activity_summary, current_focus, upcoming_commitments

---

## Repository Layer

### User Repository Methods

```go
GetUserByID(ctx, userID uuid.UUID) (*User, error)
GetUserByEmail(ctx, email string) (*User, error)
ListUsersWithSubscriptions(ctx, tier string, limit, offset int) ([]UserWithSubscription, int, error)
```

### Subscription Repository Methods

```go
GetUserSubscription(ctx, userID uuid.UUID) (*Subscription, error)
GetUserTier(ctx, userID uuid.UUID) (string, error)  // Returns "free" if none
UpsertSubscription(ctx, sub *Subscription) error
CancelSubscription(ctx, userID uuid.UUID) error
```

### AI Config Repository Methods

```go
GetAIPromptConfig(ctx, key string) (string, error)
GetAIPromptConfigsAsMap(ctx) (map[string]string, error)
UpdateAIPromptConfig(ctx, key, value, updatedBy string) error
```

### User AI Profile Repository Methods

```go
GetUserAIProfile(ctx, userID uuid.UUID) (*UserAIProfile, error)
UpsertUserAIProfile(ctx, profile *UserAIProfile) error
UpdateUserAIProfileField(ctx, userID uuid.UUID, field, value string) error
IncrementTasksSinceRefresh(ctx, userID uuid.UUID) error
GetUsersNeedingProfileRefresh(ctx, taskThreshold, hoursSinceRefresh int) ([]UserNeedingRefresh, error)
```

---

## Error Handling

### Standard Error Codes

| Code | HTTP | Description |
|------|------|-------------|
| `BAD_REQUEST` | 400 | Invalid input |
| `UNAUTHORIZED` | 401 | Invalid/missing auth |
| `FORBIDDEN` | 403 | Insufficient permissions |
| `NOT_FOUND` | 404 | Resource not found |
| `CONFLICT` | 409 | Duplicate resource |
| `RATE_LIMIT` | 429 | Rate limit exceeded |
| `INTERNAL_ERROR` | 500 | Server error |

### Error Response Format

```json
{
  "success": false,
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "AI usage limit reached for today"
  }
}
```

---

## Middleware

### Authentication Middleware

```go
// Protects all /api/v1/* routes except whitelist
func AuthMiddleware(db *pgxpool.Pool, jwtSecret string) fiber.Handler {
    // Whitelist: /auth/login, /auth/register, /auth/refresh, /auth/google, /auth/apple
    // Validates JWT Bearer token
    // Sets userID in context
}
```

### Admin Middleware

```go
// Checks if user email is in admin_users table
func AdminOnly(db *pgxpool.Pool) fiber.Handler {
    userID := middleware.GetUserID(c)
    user := repository.GetUserByID(ctx, userID)
    isAdmin := repository.IsAdmin(ctx, user.Email)
    if !isAdmin {
        return httputil.Forbidden(c, "Admin access required")
    }
}
```

---

## Package Utilities (`backend/pkg/`)

### LLM Client (`pkg/llm/`)

Multi-provider LLM client supporting:
- **Anthropic Claude** (primary)
- **OpenAI GPT-4**
- **Google Gemini**
- **Ollama** (local)

```go
type MultiClient struct {
    primary   LLMClient
    fallbacks []LLMClient
}

func (c *MultiClient) Complete(ctx context.Context, prompt string, opts Options) (string, error)
```

### OAuth Providers (`pkg/oauth/`)

```go
// Google OAuth
func VerifyGoogleIDToken(ctx context.Context, idToken string) (*GoogleUser, error)

// Apple Sign-In
func VerifyAppleIDToken(ctx context.Context, idToken string) (*AppleUser, error)
```

### HTTP Utilities (`pkg/httputil/`)

```go
func Success(c *fiber.Ctx, data interface{}) error
func SuccessWithMeta(c *fiber.Ctx, data interface{}, meta *dto.APIMeta) error
func BadRequest(c *fiber.Ctx, message string) error
func Unauthorized(c *fiber.Ctx, message string) error
func Forbidden(c *fiber.Ctx, message string) error
func NotFound(c *fiber.Ctx, resource string) error
func InternalError(c *fiber.Ctx, message string) error
```

---

## Configuration

### Environment Variables

```bash
# Database
DATABASE_URL=postgres://user:pass@host:5432/shared_db

# JWT
JWT_SECRET=your-secret-key
JWT_EXPIRY=1h
REFRESH_TOKEN_EXPIRY=168h  # 7 days

# OAuth
GOOGLE_CLIENT_ID=xxx
APPLE_TEAM_ID=xxx
APPLE_KEY_ID=xxx
APPLE_PRIVATE_KEY=xxx

# LLM
ANTHROPIC_API_KEY=xxx
OPENAI_API_KEY=xxx
GOOGLE_AI_API_KEY=xxx

# Payment
PADDLE_API_KEY=xxx
PADDLE_WEBHOOK_SECRET=xxx
```

---

## Summary

The Shared Services layer provides:
1. **Authentication** - Multi-provider OAuth + email/password with JWT tokens
2. **User Management** - Profile CRUD with settings and preferences
3. **Subscriptions** - Three-tier system (Free, Light, Premium) with multiple payment providers
4. **AI Features** - Rate-limited AI operations with configurable prompts
5. **Admin Tools** - User management, order tracking, AI configuration
