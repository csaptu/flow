# Flow Development Makefile
.PHONY: help dev dev-shared dev-tasks dev-projects stop logs migrate test

# Load environment variables from .env file
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

help:
	@echo "Flow Development Commands"
	@echo "========================="
	@echo "  make dev           - Run all backend services"
	@echo "  make dev-shared    - Run shared service only"
	@echo "  make dev-tasks     - Run tasks service only"
	@echo "  make dev-projects  - Run projects service only"
	@echo "  make stop          - Stop all services"
	@echo "  make logs          - View all service logs"
	@echo "  make migrate       - Run database migrations"
	@echo "  make test          - Run all tests"

# Run all services concurrently
dev:
	@echo "Starting all backend services..."
	@trap 'kill 0' INT; \
	(cd backend/shared && go run cmd/main.go) & \
	(cd backend/tasks && go run cmd/main.go) & \
	(cd backend/projects && go run cmd/main.go) & \
	wait

# Individual services
dev-shared:
	@echo "Starting shared service..."
	cd backend/shared && go run cmd/main.go

dev-tasks:
	@echo "Starting tasks service..."
	cd backend/tasks && go run cmd/main.go

dev-projects:
	@echo "Starting projects service..."
	cd backend/projects && go run cmd/main.go

# Stop all running services
stop:
	@echo "Stopping services..."
	@pkill -f "go run cmd/main.go" || true
	@echo "Services stopped"

# Database migrations
migrate:
	@echo "Running migrations..."
	cd backend/shared && go run cmd/migrate/main.go up
	cd backend/tasks && go run cmd/migrate/main.go up
	cd backend/projects && go run cmd/migrate/main.go up
	@echo "Migrations complete"

migrate-down:
	@echo "Rolling back migrations..."
	cd backend/shared && go run cmd/migrate/main.go down
	cd backend/tasks && go run cmd/migrate/main.go down
	cd backend/projects && go run cmd/migrate/main.go down

# Tests
test:
	@echo "Running tests..."
	cd backend/shared && go test ./...
	cd backend/tasks && go test ./...
	cd backend/projects && go test ./...
	cd backend/common && go test ./...
	cd backend/pkg && go test ./...

# Build all services
build:
	@echo "Building services..."
	cd backend/shared && go build -o bin/shared cmd/main.go
	cd backend/tasks && go build -o bin/tasks cmd/main.go
	cd backend/projects && go build -o bin/projects cmd/main.go

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf backend/shared/bin
	rm -rf backend/tasks/bin
	rm -rf backend/projects/bin

# Check service health
health:
	@echo "Checking service health..."
	@curl -s http://localhost:8080/health | jq . || echo "Shared service not running"
	@curl -s http://localhost:8081/health | jq . || echo "Tasks service not running"
	@curl -s http://localhost:8082/health | jq . || echo "Projects service not running"
