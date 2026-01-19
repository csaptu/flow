# Stage 1: Build Flutter web app
# This Dockerfile is built when Railway root is set to repo root
FROM ghcr.io/cirruslabs/flutter:3.27.1 AS builder

WORKDIR /app

# Copy the entire monorepo structure needed for dependencies
COPY packages/ /app/packages/
COPY apps/flow_tasks/ /app/apps/flow_tasks/

WORKDIR /app/apps/flow_tasks

# Initialize Flutter web support if not present
RUN flutter create . --platforms=web --project-name=flow_tasks 2>/dev/null || true

# Get dependencies
RUN flutter pub get

# Build for web
ARG API_BASE_URL=https://shared-api-production.up.railway.app
ENV API_BASE_URL=$API_BASE_URL

RUN flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL

# Stage 2: Serve with nginx
FROM nginx:alpine

# Copy built web app
COPY --from=builder /app/apps/flow_tasks/build/web /usr/share/nginx/html

# Copy nginx config for SPA routing
RUN echo 'server { \
    listen 8080; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
