-- Ensure guarderiaEnabled exists in app_settings and is set to true.
-- Uses INSERT ... ON CONFLICT DO UPDATE so it's safe to run multiple times.
INSERT INTO "app_settings" ("key", "value", "updatedAt")
VALUES ('guarderiaEnabled', 'true', NOW())
ON CONFLICT ("key") DO UPDATE
  SET "value" = CASE
    WHEN "app_settings"."value" = 'false' THEN 'true'
    ELSE "app_settings"."value"
  END,
  "updatedAt" = NOW();
