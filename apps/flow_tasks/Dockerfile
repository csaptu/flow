# Stage 1: Build Flutter web app
# Railway root directory should be set to repo root for this to work
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

# Build for web - API URLs for production
ARG TASKS_API_URL=https://tasks-api-production-0064.up.railway.app/api/v1
ARG SHARED_API_URL=https://shared-api-production.up.railway.app/api/v1
ARG PROJECTS_API_URL=https://projects-api-production-95b7.up.railway.app/api/v1

RUN flutter build web --release \
    --dart-define=TASKS_API_URL=$TASKS_API_URL \
    --dart-define=SHARED_API_URL=$SHARED_API_URL \
    --dart-define=PROJECTS_API_URL=$PROJECTS_API_URL

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
