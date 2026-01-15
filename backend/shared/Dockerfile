FROM golang:1.22-alpine AS builder

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git

# Copy go workspace and modules
COPY go.work go.work
COPY common/go.mod common/go.sum* ./common/
COPY pkg/go.mod pkg/go.sum* ./pkg/
COPY shared/go.mod shared/go.sum* ./shared/

# Download dependencies
RUN cd common && go mod download
RUN cd pkg && go mod download
RUN cd shared && go mod download

# Copy source code
COPY common/ ./common/
COPY pkg/ ./pkg/
COPY shared/ ./shared/

# Build
WORKDIR /app/shared
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/bin/shared-service ./cmd

# Final stage
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/bin/shared-service .

EXPOSE 8080

CMD ["./shared-service"]
