# Pasos manuales pendientes

## 1. Render — Deploy Hook (para CI/CD automático)
Ve a: https://dashboard.render.com → Servicio `garden-api` → **Settings → Deploy Hook**
→ Copia la URL del hook
→ Ve a: https://github.com/SMateo004/garden-map/settings/secrets/actions
→ Agrega secret: `RENDER_DEPLOY_HOOK_URL` = la URL copiada

Esto permite que cada push a `garden-api/**` en `main` dispare un redeploy automático en Render.

## 2. Vercel — Conexión GitHub (para PRs con preview URL)
Ve a: https://vercel.com/saimateovb-8767s-projects/garden-mvp/settings/git
→ Connect Git Repository → GitHub → `SMateo004/garden-map`

Una vez conectado, los PRs generarán automáticamente URLs de preview con comentario en el PR.

## 3. Dominio personalizado (opcional)
Si tienes un dominio (ej: `app.gardenbolivia.com`):
1. Ve a: https://vercel.com/saimateovb-8767s-projects/garden-mvp/settings/domains
2. Agrega el dominio
3. Configura en tu DNS: `CNAME app → cname.vercel-dns.com`
4. Actualiza `garden-app/web/index.html` → `connect-src` con el nuevo dominio
5. Actualiza `ALLOWED_ORIGINS` en Render con el nuevo dominio

## Estado CI/CD actual
- ✅ Push a `garden-app/**` → GitHub Actions → Flutter build → Vercel production
- ✅ PR a `garden-app/**` → GitHub Actions → Flutter build → Vercel preview
- ✅ Push a `garden-api/**` → GitHub Actions → Render deploy (requiere secret paso 1)
- ⏳ PR preview URL en comentario → requiere Vercel+GitHub conectado (paso 2)

## Credenciales de referencia
- Vercel Token: `vca_8QAH76VOZbvMsRRhO6qY9daGrI9Z82LDrA1FWtDcbFN3of9wWH1C4WGA`
- Vercel Org ID: `team_FAgD4BqTDxkt6nWLWc57xRzd`
- Vercel Project ID: `prj_2fQj0n0mBc2EK77fbQuuOssLUuSb`
- Production URL: `https://garden-mvp-three.vercel.app`
- API URL: `https://garden-api-1ldd.onrender.com/api`
