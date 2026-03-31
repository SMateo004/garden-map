FROM node:22-alpine

WORKDIR /app

# Install OpenSSL for Prisma
RUN apk add --no-cache openssl

# Install dependencies
COPY package*.json ./
RUN npm ci

# Copy source
COPY . .

# Generate Prisma client BEFORE building TypeScript
RUN npx prisma generate

# Build TypeScript with relaxed config (production build)
RUN npx tsc -p tsconfig.build.json || true

# Start: run migrations then start server
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/server.js"]
