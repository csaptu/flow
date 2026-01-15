FROM golang:1.22-alpine AS builder

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git

# Copy go modules (not using go.work to avoid missing module errors)
COPY common/go.mod common/go.sum* ./common/
COPY pkg/go.mod pkg/go.sum* ./pkg/
COPY projects/go.mod projects/go.sum* ./projects/

# Download dependencies (disable workspace)
ENV GOWORK=off
RUN cd common && go mod download
RUN cd pkg && go mod download
RUN cd projects && go mod download

# Copy source code
COPY common/ ./common/
COPY pkg/ ./pkg/
COPY projects/ ./projects/

# Build
WORKDIR /app/projects
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/bin/projects-service ./cmd

# Final stage
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/bin/projects-service .

EXPOSE 8082

CMD ["./projects-service"]
