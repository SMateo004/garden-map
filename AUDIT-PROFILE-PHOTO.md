# GARDEN — Technical Audit: Profile Photo Upload System

**Date:** 2026-02-05  
**Scope:** Complete flow trace, current state, failures, missing pieces, data consistency, execution simulation, codebase health.

---

## 1. SYSTEM FLOW TRACE

### End-to-end flow: User selects image → Upload → Cloudinary → DB → UI update

| Step | Layer | File(s) | Function(s) | Data In | Data Out |
|------|-------|---------|-------------|---------|----------|
| 1 | Frontend | `CaregiverDashboard.tsx` | `handleProfilePhotoChange` | `e.target.files[0]` (File) | — |
| 2 | Frontend | `caregiverProfile.ts` | `uploadProfilePhoto(file)` | File | FormData with field `profilePhoto` |
| 3 | Frontend | `api/client.ts` | `api.post` | FormData, headers `Content-Type: multipart/form-data` | — |
| 4 | Network | HTTP | POST `/api/upload/profile-photo` | multipart body, Bearer token | — |
| 5 | Backend | `upload.routes.ts` | Route handler | — | chains to controller |
| 6 | Backend | `upload.controller.ts` | `upload.single('profilePhoto')` (multer) | req (raw multipart) | `req.file` (buffer in memory) |
| 7 | Backend | `upload.controller.ts` | `uploadProfilePhotoToCloudinary(buffer, userId)` | Buffer, userId | `secure_url` (string) |
| 8 | Backend | `upload.controller.ts` | `prisma.caregiverProfile.update` | `{ where: { userId }, data: { profilePhoto: url } }` | — |
| 9 | Backend | `upload.controller.ts` | `res.json({ success: true, data: { profilePhoto: url } })` | — | JSON response |
| 10 | Frontend | `caregiverProfile.ts` | `uploadProfilePhoto` returns | `res.data.data.profilePhoto` | string URL |
| 11 | Frontend | `CaregiverDashboard.tsx` | `refetchProfile()` | — | — |
| 12 | Frontend | `caregiverProfile.ts` | `getMyProfile()` | — | GET `/api/caregiver/my-profile` |
| 13 | Backend | `caregiver-profile.service.ts` | `getMyProfile(userId)` | — | Full Prisma `caregiverProfile` (includes `profilePhoto`) |
| 14 | Frontend | `CaregiverDashboard.tsx` | `setProfile(data)` | MyProfileResponse | — |
| 15 | Frontend | `CaregiverDashboard.tsx` | Render | `profile?.profilePhoto` | `getImageUrl(profile?.profilePhoto ?? null)` → `<img src="..." />` |

### Public list/detail flow (where profilePhoto is consumed)

| Step | Layer | File | Function | Field mapping |
|------|-------|------|----------|---------------|
| 1 | Backend | `caregiver.service.ts` | `listCaregivers` | `c.profilePhoto ?? c.user?.profilePicture` → `profilePicture` |
| 2 | Backend | `caregiver.service.ts` | `getCaregiverById` (detail) | `profile.profilePhoto ?? profile.user.profilePicture` → `profilePicture` |
| 3 | Frontend | `ProfileCard.tsx` | Render | `caregiver.profilePicture ?? caregiver.photos?.[0]` |
| 4 | Frontend | `ProfileDetail.tsx` | Render | `caregiver.profilePicture` (first carousel slide) |

---

## 2. CURRENT STATE (WHAT EXISTS)

### Frontend

| Item | Status | Location |
|------|--------|----------|
| Upload triggered | ✅ | `CaregiverDashboard.tsx:26-43` — `handleProfilePhotoChange` on `<input type="file">` change |
| FormData used | ✅ | `caregiverProfile.ts:68-69` — `formData.append('profilePhoto', file)` |
| Field name | ✅ | Matches backend: `profilePhoto` |
| File actually sent | ⚠️ | See "Content-Type" issue below |
| State update after upload | ✅ | `refetchProfile()` called after success; `setProfile(data)` updates local state |
| Rendering | ✅ | `getImageUrl(profile?.profilePhoto ?? null)` — `images.ts` returns placeholder if null |
| Error handling | ✅ | `setPhotoError`, `setUploadingPhoto` |

### Backend

| Item | Status | Location |
|------|--------|----------|
| Multer configured | ✅ | `upload.controller.ts:15-18` — `multer.memoryStorage()`, 5MB limit |
| Field name | ✅ | `upload.single('profilePhoto')` — matches frontend |
| Cloudinary upload | ✅ | `uploadProfilePhotoToCloudinary` — sharp resize, upload_stream, `secure_url` |
| DB update | ✅ | `prisma.caregiverProfile.update({ where: { userId }, data: { profilePhoto: url } })` |
| Dev fallback | ✅ | When Cloudinary not configured: placeholder URL + DB update |
| Auth | ✅ | `authMiddleware`, `requireRole('CAREGIVER')` |
| Profile existence check | ✅ | Fails with clear error if no caregiver profile |

### Database (Prisma + DB)

| Item | Status | Evidence |
|------|--------|----------|
| Prisma model has profilePhoto | ✅ | `schema.prisma:181` — `profilePhoto String? @db.Text` |
| Prisma client generated | ✅ | `node_modules/.prisma/client` includes `profilePhoto` |
| DB table has column | ❌ **UNKNOWN** | Logs show: "The column `caregiver_profiles.profilePhoto` does not exist in the current database" |
| Schema sync | ⚠️ | Requires `npx prisma db push` (or migrate); server exits at startup if column/table missing |

### Storage (Cloudinary)

| Item | Status |
|------|--------|
| Config check | ✅ `isCloudinaryConfigured()` — CLOUDINARY_CLOUD_NAME, API_KEY, API_SECRET |
| Upload folder | `garden/caregivers/{userId}/profile_{timestamp}.jpg` |
| Image processing | sharp resize 1024×1024, JPEG 85% |
| URL returned | `secure_url` from Cloudinary response |
| Dev without Cloudinary | Placeholder `https://placehold.co/400x400?text=Foto+perfil` persisted to DB |

---

## 3. DETECTED FAILURES

### Blocking (breaks system)

| ID | Issue | Location | Impact |
|----|-------|----------|--------|
| B1 | **DB column `profilePhoto` may not exist** | PostgreSQL `caregiver_profiles` | `listCaregivers`, `getCaregiverById`, `getMyProfile`, upload `update` all fail with P2022. Server exits at startup if startup check runs. |
| B2 | **Content-Type without boundary** | `caregiverProfile.ts:72` | Frontend sends `Content-Type: multipart/form-data` without boundary. Multer requires boundary to parse parts. Can cause `req.file` to be `undefined` → "Se requiere una foto (campo profilePhoto)". |

### Risky (can break later)

| ID | Issue | Location | Impact |
|----|-------|----------|--------|
| R1 | **Default axios Content-Type** | `api/client.ts:7` | `Content-Type: application/json` is default. For FormData, axios should NOT set Content-Type (browser adds boundary). Override to `multipart/form-data` strips boundary. |
| R2 | **No cache invalidation on profile photo update** | `caregiver.service.ts` | List/detail use `caregiverListCacheKey`, `caregiverDetailCacheKey`. After upload, cache is stale until TTL expires. |

### Incorrect implementation

| ID | Issue | Details |
|----|-------|---------|
| I1 | **FormData Content-Type** | Explicit `headers: { 'Content-Type': 'multipart/form-data' }` when body is FormData. Correct: omit Content-Type so axios/browser sets `multipart/form-data; boundary=----WebKitFormBoundary...`. |

### Missing pieces

| ID | Item | Notes |
|----|------|-------|
| M1 | DB schema applied | `prisma db push` or migrate must be run; column may be missing. |
| M2 | Cloudinary env vars | CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET required for production. |
| M3 | Cache invalidation on profile photo change | Upload updates DB but list/detail cache is not invalidated. |

---

## 4. WHAT IS MISSING

| Priority | Missing item | Required for |
|----------|--------------|--------------|
| P0 | Run `npx prisma db push` (or apply migration) | Any profile photo functionality |
| P0 | Remove or fix Content-Type header for FormData upload | Upload to succeed (multer parsing) |
| P1 | Cache invalidation when profilePhoto changes | List/detail to show new photo immediately |
| P2 | Cloudinary credentials in production | Real image storage |
| P2 | Error feedback if profile doesn't exist | Clear UX when user has no caregiver profile |

---

## 5. DATA CONSISTENCY CHECK

| Check | Result |
|-------|--------|
| Same field name everywhere? | **Mixed.** Backend DB/Prisma/upload: `profilePhoto`. Public API (list/detail): `profilePicture`. Frontend `MyProfileResponse`: `profilePhoto`. Frontend `CaregiverListItem`: `profilePicture`. Mapping is intentional and consistent. |
| Data actually persisted? | **Yes**, when DB column exists. `prisma.caregiverProfile.update` writes `profilePhoto`. |
| Frontend reading correct field? | **Yes.** Dashboard uses `profile?.profilePhoto` (my-profile). ProfileCard/ProfileDetail use `profilePicture` (list/detail API). |
| getImageUrl usage | ✅ All `img` src use `getImageUrl(url)`; placeholder when null. |

---

## 6. REAL EXECUTION SIMULATION

### Scenario: User selects image, clicks "Cambiar foto"

1. **User selects image** — ✅ `handleProfilePhotoChange` runs.
2. **Click upload** — ✅ `uploadProfilePhoto(file)` called.
3. **Request sent** — ⚠️ FormData with `profilePhoto`; `Content-Type: multipart/form-data` (no boundary). **May fail** if server requires boundary.
4. **Backend processes** — If multer parses correctly: ✅ `req.file` exists. If not: ❌ `req.file` undefined → 400 "Se requiere una foto (campo profilePhoto)".
5. **Image stored** — ✅ Cloudinary (or placeholder in dev).
6. **DB updated** — ❌ Fails if `profilePhoto` column missing (P2022). ✅ Succeeds if schema is applied.
7. **UI updates** — ✅ `refetchProfile()` → `getMyProfile()` → `setProfile` → re-render. ❌ `getMyProfile` fails if column missing.

**Break points:** (a) Multer parsing (Content-Type); (b) DB column existence.

---

## 7. CODEBASE HEALTH

| Check | Result |
|-------|--------|
| Stale /dist files | Not audited; API uses `tsx` or `ts-node` in dev. Production may use compiled `dist/` — ensure rebuild after schema/code changes. |
| Duplicate configs | `vite.config.ts` exists; no `vite.config.js`. `vite.config.d.ts` is type declaration. ✅ No duplicate. |
| Debug logs | No `fetch(ingest...)` or `#region agent` in source. Previous debug instrumentation removed. |
| Dead code | No obvious dead code in profile photo path. |

---

## 8. FINAL VERDICT

### Is the system functional?

**PARTIAL** — Code path is implemented end-to-end, but two blocking issues prevent reliable operation:

1. **DB schema:** Column `caregiver_profiles.profilePhoto` must exist. Historical logs show it does not. Run `cd garden-api && npx prisma db push`.
2. **Content-Type for FormData:** Explicit `Content-Type: multipart/form-data` without boundary can prevent multer from parsing the file. Omit the header for FormData so the runtime sets it with boundary.

### Main root cause

**Schema drift + FormData header:** The database was not migrated after adding `profilePhoto` to the Prisma schema. Additionally, the frontend overrides Content-Type when sending FormData, which can break multipart parsing.

### Top 3 priorities to fix

1. **Apply schema:** Run `cd garden-api && npx prisma db push` (or equivalent migration). Ensure the `profilePhoto` column exists.
2. **Fix FormData Content-Type:** In `garden-web/src/api/caregiverProfile.ts`, remove `headers: { 'Content-Type': 'multipart/form-data' }` when posting FormData, or use a pattern that lets axios/browser set the correct header with boundary.
3. **Invalidate cache on profile photo update:** After `prisma.caregiverProfile.update` in the upload handler, invalidate `caregiverDetailCacheKey(profileId)` and the list cache (or the relevant caregiver keys) so list/detail show the new photo immediately.

---

## File reference index

| Purpose | Path |
|---------|------|
| Upload trigger | `garden-web/src/pages/caregiver/CaregiverDashboard.tsx` |
| Upload API | `garden-web/src/api/caregiverProfile.ts` |
| API client | `garden-web/src/api/client.ts` |
| Image util | `garden-web/src/utils/images.ts` |
| Upload route | `garden-api/src/modules/upload/upload.routes.ts` |
| Upload controller | `garden-api/src/modules/upload/upload.controller.ts` |
| Prisma schema | `garden-api/prisma/schema.prisma` |
| Caregiver service (list/detail) | `garden-api/src/modules/caregiver-service/caregiver.service.ts` |
| Caregiver profile service | `garden-api/src/modules/caregiver-profile/caregiver-profile.service.ts` |
| Cloudinary config | `garden-api/src/config/cloudinary.js` |
| Server startup | `garden-api/src/server.ts` |
| ProfileCard | `garden-web/src/components/ProfileCard.tsx` |
| ProfileDetail | `garden-web/src/components/ProfileDetail.tsx` |
