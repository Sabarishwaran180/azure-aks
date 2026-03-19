FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev

FROM node:20-alpine AS runtime
RUN addgroup -g 1001 -S nodejs && adduser -S nodeuser -u 1001 -G nodejs
RUN apk add --no-cache tini
WORKDIR /app
COPY --from=builder --chown=nodeuser:nodejs /app/node_modules ./node_modules
COPY --chown=nodeuser:nodejs src ./src
COPY --chown=nodeuser:nodejs package.json ./
USER nodeuser
EXPOSE 3002
ENTRYPOINT ["/sbin/tini", "--"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3002/healthz || exit 1
CMD ["node", "src/index.js"]
