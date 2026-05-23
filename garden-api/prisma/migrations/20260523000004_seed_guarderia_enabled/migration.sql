-- Ensure guarderiaEnabled exists in AppSettings and is set to true.
-- Uses INSERT ... ON CONFLICT DO UPDATE so it's safe to run multiple times.
INSERT INTO "AppSettings" ("key", "value", "updatedAt")
VALUES ('guarderiaEnabled', 'true', NOW())
ON CONFLICT ("key") DO UPDATE
  SET "value" = CASE
    WHEN "AppSettings"."value" = 'false' THEN 'true'
    ELSE "AppSettings"."value"
  END,
  "updatedAt" = NOW();
