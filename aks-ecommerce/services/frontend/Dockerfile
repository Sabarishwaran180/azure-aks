FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage: serve with nginx
FROM nginx:1.25-alpine AS runtime

# Security: run nginx as non-root
RUN addgroup -g 1001 -S nginxgroup && adduser -S nginxuser -u 1001 -G nginxgroup

# Copy build artifacts
COPY --from=builder /app/build /usr/share/nginx/html
# nginx config will be mounted from ConfigMap
COPY nginx.conf /etc/nginx/nginx.conf

# Fix permissions
RUN chown -R nginxuser:nginxgroup /usr/share/nginx/html /var/cache/nginx /var/log/nginx \
    && chmod -R 755 /usr/share/nginx/html \
    && touch /var/run/nginx.pid \
    && chown nginxuser:nginxgroup /var/run/nginx.pid

USER nginxuser
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
