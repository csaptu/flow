# Flow - AI-Powered Productivity Suite

Flow is a comprehensive productivity suite consisting of two applications:

- **Flow Tasks** - Simple, fast task capture with 2-layer hierarchy (like Google Tasks meets TickTick)
- **Flow Projects** - Full project management with WBS, Gantt charts, and dependencies

## Architecture

```
flow/
├── backend/           # Go microservices
│   ├── common/        # Shared models, interfaces, errors
│   ├── pkg/           # Utilities (config, middleware, LLM client)
│   ├── shared/        # Auth, users, subscriptions service
│   ├── tasks/         # Tasks service
│   └── projects/      # Projects service
├── apps/
│   ├── flow_tasks/    # Flutter Tasks app
│   └── flow_projects/ # Flutter Projects app
└── packages/
    ├── flow_api/      # Dart API client
    └── flow_models/   # Shared Dart models
```

## Tech Stack

**Backend:**
- Go 1.21+ with Fiber v2
- PostgreSQL (3 databases: shared_db, tasks_db, projects_db)
- Redis for caching/sessions
- JWT authentication with refresh token rotation
- Multi-provider LLM support (Anthropic, Google, OpenAI, Ollama)

**Frontend:**
- Flutter 3.16+ (cross-platform: iOS, Android, Web, macOS, Windows, Linux)
- Riverpod for state management
- GoRouter for navigation
- Bear App-inspired design system

## Development

### Prerequisites

- Go 1.21+
- Flutter 3.16+
- Docker & Docker Compose
- PostgreSQL 15+ (or use Docker)

### Backend Setup

```bash
# Start databases
docker-compose up -d postgres-shared postgres-tasks postgres-projects redis

# Run migrations
cd backend/shared && go run cmd/migrate/main.go up
cd backend/tasks && go run cmd/migrate/main.go up
cd backend/projects && go run cmd/migrate/main.go up

# Start services
cd backend/shared && go run cmd/main.go
cd backend/tasks && go run cmd/main.go
cd backend/projects && go run cmd/main.go
```

### Flutter Setup

```bash
# Install dependencies
cd apps/flow_tasks && flutter pub get
cd apps/flow_projects && flutter pub get

# Run apps
flutter run -d macos  # or chrome, ios, android
```

### Docker Compose (Full Stack)

```bash
# Copy environment file
cp .env.example .env

# Start everything
docker-compose up -d

# Services available at:
# - Shared API: http://localhost:8080
# - Tasks API: http://localhost:8081
# - Projects API: http://localhost:8082
```

## Environment Variables

See `.env.example` for all required environment variables.

Key variables:
- `JWT_SECRET` - Secret for JWT signing
- `DATABASE_URL` - PostgreSQL connection string
- `REDIS_URL` - Redis connection string
- `ANTHROPIC_API_KEY` - For AI features
- `GOOGLE_AI_API_KEY` - For AI features (fallback)

## License

Private - All rights reserved
