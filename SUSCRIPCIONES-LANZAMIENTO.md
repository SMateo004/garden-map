# Suscripciones de Lanzamiento — Garden
> Objetivo: sostener la app hasta ~100 usuarios activos

---

## Render (Infraestructura)

| Servicio | Plan | Costo/mes | Notas |
|---|---|---|---|
| `garden-api` | Starter | $7.00 | Siempre activo, sin cold starts |
| `garden-pricing` | Starter | $7.00 | Solo si es user-facing (calcular precios al reservar) |
| `garden-db` | Basic 256MB | ~$6.02 | Suficiente hasta ~1,000 usuarios |
| **Subtotal Render** | | **$13–$20/mo** | |

**Cuándo subir de plan en Render:**
- `garden-db` → subir a Basic 512MB ($17/mo) cuando superes 500 usuarios o notes lentitud en queries

---

## Por confirmar

| Servicio | Plan actual | Costo estimado | Estado |
|---|---|---|---|
| Cloudinary | Free | $0 | 0.21/25 créditos usados (0.84%). Suficiente para 100+ usuarios. Subir cuando llegue a 20+ créditos/mes |
| Firebase | Blaze (pay-as-you-go) | ~$0 | FCM + Auth dentro del free tier a 100 usuarios. Configurar budget alert a $10/mes |
| AWS (S3 + IAM) | Free Tier + Créditos | $0 | $99.55 de créditos restantes ($100 total, usado $0.45). Vence 27/02/2027. S3 no activo en prod aún |
| Anthropic Claude API | Pay-per-token (créditos prepagos) | ~$5–20/mo est. | Saldo actual: $2.24 ⚠️ RECARGAR. Gasto mayo: $0.16. Activar Prompt Caching y Auto-reload |
| Dominio `gardenbo.com` | Año 1 pagado | $35 (1er año) | Renovación año 2 por confirmar — puede subir |
| Sentry | Developer (Free) | $0 | 5K errores/mes incluidos. Suficiente para 100 usuarios |
| PostHog | Free | $0 | 1M eventos/mes incluidos. Más que suficiente para 100 usuarios |
| Redis Cloud | Free (Essentials) | $0 | 30MB incluidos. Suficiente para caché/sesiones a 100 usuarios. Subir si superas 25MB usados |
| Vercel | Hobby (Free) | $0 | Frontend. 2.11/100 GB transfer, 11K/1M requests. Muy lejos de límites |
| Google Cloud (Maps API) | Pay-as-you-go | $0 | $200/mes crédito gratuito incluido. Gasto mayo: $0. Crear budget alert a $10/mes |
| Cloudflare | Free | $0 | DNS + CDN + DDoS básico incluidos. Suficiente para 100 usuarios |
| Resend | Free | $0 | 3,000 emails/mes incluidos. Suficiente para 100 usuarios |
| GitHub | Free | $0 | Repos privados ilimitados incluidos |
| Apple Developer Program | ⚠️ PENDIENTE | $99/año | Obligatorio para publicar en App Store. Pago anual |
| Google Play Console | ⚠️ PENDIENTE | $25 (único) | Obligatorio para publicar en Play Store. Pago único |
| Stripe / pagos | ? | 2.9% + $0.30 por tx | No fijo, va con volumen |

---

## Total estimado al lanzamiento

| Categoría | Costo/mes |
|---|---|
| Render | $13–$20 |
| Cloudinary | TBD |
| Firebase | TBD |
| AWS | TBD |
| Claude API | TBD |
| **TOTAL** | **$13–$20+ TBD** |

---

_Última actualización: 2026-05-31_
