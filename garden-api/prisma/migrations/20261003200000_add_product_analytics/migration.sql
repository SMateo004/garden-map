-- CreateTable
CREATE TABLE "analytics_events" (
    "id" BIGSERIAL NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "userId" VARCHAR(36),
    "deviceId" VARCHAR(36) NOT NULL,
    "sessionId" VARCHAR(36) NOT NULL,
    "name" VARCHAR(40) NOT NULL,
    "screen" VARCHAR(60),
    "durationMs" INTEGER,
    "props" JSONB,
    CONSTRAINT "analytics_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "analytics_sessions" (
    "id" VARCHAR(36) NOT NULL,
    "userId" VARCHAR(36),
    "deviceId" VARCHAR(36) NOT NULL,
    "platform" VARCHAR(10) NOT NULL,
    "appVersion" VARCHAR(20),
    "locale" VARCHAR(10),
    "role" VARCHAR(10),
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMP(3),
    "durationSec" INTEGER NOT NULL DEFAULT 0,
    "screenCount" INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT "analytics_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "analytics_daily" (
    "day" DATE NOT NULL,
    "metric" VARCHAR(60) NOT NULL,
    "dim" VARCHAR(60) NOT NULL DEFAULT '',
    "count" INTEGER NOT NULL DEFAULT 0,
    "sum" BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT "analytics_daily_pkey" PRIMARY KEY ("day","metric","dim")
);

CREATE INDEX "analytics_events_createdAt_idx" ON "analytics_events"("createdAt");
CREATE INDEX "analytics_events_name_createdAt_idx" ON "analytics_events"("name", "createdAt");
CREATE INDEX "analytics_events_userId_createdAt_idx" ON "analytics_events"("userId", "createdAt");
CREATE INDEX "analytics_sessions_startedAt_idx" ON "analytics_sessions"("startedAt");
CREATE INDEX "analytics_sessions_userId_startedAt_idx" ON "analytics_sessions"("userId", "startedAt");
CREATE INDEX "analytics_sessions_deviceId_idx" ON "analytics_sessions"("deviceId");
CREATE INDEX "analytics_daily_metric_day_idx" ON "analytics_daily"("metric", "day");
