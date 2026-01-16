FROM golang:1.22-alpine AS builder

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git

# Copy go modules (not using go.work to avoid missing module errors)
COPY common/go.mod common/go.sum* ./common/
COPY pkg/go.mod pkg/go.sum* ./pkg/
COPY shared/go.mod shared/go.sum* ./shared/

# Download dependencies (disable workspace)
ENV GOWORK=off
RUN cd common && go mod download
RUN cd pkg && go mod download
RUN cd shared && go mod download

# Copy source code
COPY common/ ./common/
COPY pkg/ ./pkg/
COPY shared/ ./shared/

# Build main service and migrate tool
WORKDIR /app/shared
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/bin/shared-service ./cmd
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/bin/migrate ./cmd/migrate

# Final stage
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/bin/shared-service .
COPY --from=builder /app/bin/migrate .
COPY --from=builder /app/shared/database/migrations ./database/migrations

EXPOSE 8080

# Run migrations then start server
CMD ["sh", "-c", "./migrate up && ./shared-service"]
