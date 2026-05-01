#!/bin/sh
set -e

# Migrations that were previously applied via `prisma db push` without tracking.
# `migrate resolve --applied` registers them in _prisma_migrations without
# running their SQL, so `migrate deploy` only runs truly pending migrations.
LEGACY_MIGRATIONS="
  20260223064010_add_verification_review_fields
  20260223064111_add_identity_verified_to_user
  20260223220508_add_identity_verification_cropped_urls
  20260223222246_add_verification_production_fields
  20260319140012_add_chat_messages
  20260417191356_enable_row_level_security
  20260417231505_add_refresh_tokens_and_stripe_event_id
  20260424000001_add_client_bio
  20260425000001_sugerencia_precio_cascade
"

for migration in $LEGACY_MIGRATIONS; do
  npx prisma migrate resolve --applied "$migration" 2>/dev/null || true
done

npx prisma migrate deploy

exec node dist/server.js
