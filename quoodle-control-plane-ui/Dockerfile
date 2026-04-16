FROM node:20-alpine AS deps
WORKDIR /app

COPY package.json package-lock.json ./
RUN set -eux; \
    npm config set fetch-retries 6; \
    npm config set fetch-retry-factor 2; \
    npm config set fetch-retry-mintimeout 10000; \
    npm config set fetch-retry-maxtimeout 120000; \
    npm config set registry https://registry.npmjs.org/; \
    for attempt in 1 2 3 4; do \
      npm ci --no-audit --no-fund && break; \
      if [ "$attempt" -eq 4 ]; then exit 1; fi; \
      echo "npm ci failed (attempt $attempt). Retrying in 8s..."; \
      sleep 8; \
    done

FROM node:20-alpine AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

EXPOSE 3000

CMD ["node", "server.js"]
