# Simple static file server for pre-built Flutter web app
# Use this when full build times out on Railway

FROM nginx:alpine

# Copy pre-built web files (build locally first with: flutter build web --release)
COPY build/web /usr/share/nginx/html

# Configure nginx for SPA routing
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
