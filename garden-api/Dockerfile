FROM node:22-alpine

WORKDIR /app

# Install OpenSSL for Prisma
RUN apk add --no-cache openssl

# Install dependencies
COPY package*.json ./
RUN npm ci --omit=dev=false

# Copy source and build
COPY . .
RUN npm run build
RUN npx prisma generate

# Expose port
EXPOSE 3000

# Start: run migrations then start server
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/server.js"]
