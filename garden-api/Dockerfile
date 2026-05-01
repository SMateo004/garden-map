FROM node:22-alpine

WORKDIR /app

# Install OpenSSL for Prisma
RUN apk add --no-cache openssl bash

# Install dependencies
COPY package*.json ./
RUN npm ci

# Copy source
COPY . .

# Generate Prisma client BEFORE building TypeScript
RUN npx prisma generate

# Build TypeScript with relaxed config (production build)
RUN npx tsc -p tsconfig.build.json || true

COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

# Start: resolve legacy migrations, deploy pending ones, then start server
CMD ["./docker-entrypoint.sh"]
