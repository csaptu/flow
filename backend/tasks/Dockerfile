FROM golang:1.22-alpine AS builder

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git

# Copy go workspace and modules
COPY go.work go.work
COPY common/go.mod common/go.sum* ./common/
COPY pkg/go.mod pkg/go.sum* ./pkg/
COPY tasks/go.mod tasks/go.sum* ./tasks/

# Download dependencies
RUN cd common && go mod download
RUN cd pkg && go mod download
RUN cd tasks && go mod download

# Copy source code
COPY common/ ./common/
COPY pkg/ ./pkg/
COPY tasks/ ./tasks/

# Build
WORKDIR /app/tasks
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/bin/tasks-service ./cmd

# Final stage
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/bin/tasks-service .

EXPOSE 8081

CMD ["./tasks-service"]
