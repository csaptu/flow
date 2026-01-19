FROM golang:1.22-alpine AS builder

# Cache bust: 2025-01-19-v2
ARG CACHEBUST=1

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git

# Copy go modules (not using go.work to avoid missing module errors)
COPY common/go.mod common/go.sum* ./common/
COPY pkg/go.mod pkg/go.sum* ./pkg/
COPY shared/go.mod shared/go.sum* ./shared/
COPY tasks/go.mod tasks/go.sum* ./tasks/

# Download dependencies (disable workspace)
ENV GOWORK=off
RUN cd common && go mod download
RUN cd pkg && go mod download
RUN cd shared && go mod download
RUN cd tasks && go mod download

# Copy source code
COPY common/ ./common/
COPY pkg/ ./pkg/
COPY shared/ ./shared/
COPY tasks/ ./tasks/

# Build main service and migrate tool
WORKDIR /app/tasks
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/bin/tasks-service ./cmd
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/bin/migrate ./cmd/migrate

# Final stage
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/bin/tasks-service .
COPY --from=builder /app/bin/migrate .
COPY --from=builder /app/tasks/database/migrations ./database/migrations

EXPOSE 8081

# Skip migrations (already at v14) and start server directly
# Migrations can be run manually if needed
CMD ["./tasks-service"]
