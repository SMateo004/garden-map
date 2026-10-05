/**
 * Analítica de producto propia (ver comentario del schema "ANALÍTICA DE PRODUCTO").
 *
 * - ingestBatch:   recibe el lote que manda la app (sesión + eventos).
 * - rollupDay:     agrega los eventos crudos de un día a AnalyticsDaily (permanente).
 * - purgeOld:      poda eventos (90d) y sesiones (400d).
 * - getAdminSummary: arma todo lo que ve el panel admin. Lo de negocio sale de
 *   las tablas reales (Booking, User…) sin duplicar datos; lo de uso sale de
 *   sesiones + agregados diarios.
 */
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import prisma from '../../config/database.js';

const TZ = 'America/La_Paz';
export const EVENT_RETENTION_DAYS = 90;
export const SESSION_RETENTION_DAYS = 400;

/** Hora local de Bolivia a partir de una columna timestamp (guardada en UTC). */
const local = (col: string) => Prisma.raw(`((${col} AT TIME ZONE 'UTC') AT TIME ZONE '${TZ}')`);

// ─────────────────────────────── Ingesta ───────────────────────────────

const eventSchema = z.object({
  name: z.string().regex(/^[a-z0-9_]{2,40}$/),
  screen: z.string().max(60).optional(),
  durationMs: z.number().int().min(0).max(6 * 3600 * 1000).optional(),
  /** milisegundos transcurridos desde el evento hasta el envío */
  ago: z.number().int().min(0).max(24 * 3600 * 1000).optional(),
  props: z.record(z.union([z.string().max(60), z.number(), z.boolean()])).optional(),
});

const batchSchema = z.object({
  deviceId: z.string().min(8).max(36),
  session: z.object({
    id: z.string().min(8).max(36),
    platform: z.enum(['android', 'ios', 'web']),
    appVersion: z.string().max(20).optional(),
    locale: z.string().max(10).optional(),
    role: z.string().max(10).optional(),
    durationSec: z.number().int().min(0).max(4 * 3600),
    screenCount: z.number().int().min(0).max(5000),
  }),
  events: z.array(eventSchema).max(60),
});

export type AnalyticsBatch = z.infer<typeof batchSchema>;

export async function ingestBatch(raw: unknown, userId: string | null): Promise<void> {
  const parsed = batchSchema.safeParse(raw);
  if (!parsed.success) return; // analítica nunca devuelve error a la app
  const { deviceId, session, events } = parsed.data;
  const now = Date.now();

  await prisma.analyticsSession.upsert({
    where: { id: session.id },
    create: {
      id: session.id,
      userId,
      deviceId,
      platform: session.platform,
      appVersion: session.appVersion,
      locale: session.locale,
      role: userId ? session.role : 'GUEST',
      endedAt: new Date(now),
      durationSec: session.durationSec,
      screenCount: session.screenCount,
    },
    // userId solo se completa si la sesión empezó como invitado y luego hizo login.
    update: {
      endedAt: new Date(now),
      durationSec: session.durationSec,
      screenCount: session.screenCount,
      ...(userId ? { userId, role: session.role } : {}),
    },
  });

  if (events.length === 0) return;
  await prisma.analyticsEvent.createMany({
    data: events.map((e) => {
      const props = e.props && JSON.stringify(e.props).length <= 512 ? e.props : undefined;
      return {
        createdAt: new Date(now - (e.ago ?? 0)),
        userId,
        deviceId,
        sessionId: session.id,
        name: e.name,
        screen: e.screen,
        durationMs: e.durationMs,
        props,
      };
    }),
  });
}

// ─────────────────────────────── Rollup / poda ───────────────────────────────

/** Recalcula los agregados de un día local ("YYYY-MM-DD"). Idempotente. */
export async function rollupDay(day: string): Promise<void> {
  const ev = local('"createdAt"');
  const ss = local('"startedAt"');
  await prisma.$transaction([
    prisma.$executeRaw`DELETE FROM analytics_daily WHERE day = ${day}::date`,
    prisma.$executeRaw`
      INSERT INTO analytics_daily (day, metric, dim, "count", "sum")
      SELECT ${day}::date, 'event:' || name, '', count(*)::int, coalesce(sum("durationMs"), 0)
        FROM analytics_events WHERE ${ev}::date = ${day}::date GROUP BY name
      UNION ALL
      SELECT ${day}::date, 'event_sessions:' || name, '', count(DISTINCT "sessionId")::int, 0
        FROM analytics_events WHERE ${ev}::date = ${day}::date GROUP BY name
      UNION ALL
      SELECT ${day}::date, 'screen', screen, count(*)::int, coalesce(sum("durationMs"), 0)
        FROM analytics_events
       WHERE ${ev}::date = ${day}::date AND name = 'screen_view' AND screen IS NOT NULL GROUP BY screen
      UNION ALL
      SELECT ${day}::date, 'cg_view', left(props->>'cid', 60), count(*)::int, 0
        FROM analytics_events
       WHERE ${ev}::date = ${day}::date AND name = 'caregiver_open' AND props->>'cid' IS NOT NULL
       GROUP BY props->>'cid'
      UNION ALL
      SELECT ${day}::date, 'pref:' || left(props->>'k', 50), left(props->>'v', 60), count(*)::int, 0
        FROM analytics_events
       WHERE ${ev}::date = ${day}::date AND name = 'filter_applied'
         AND props->>'k' IS NOT NULL AND props->>'v' IS NOT NULL
       GROUP BY props->>'k', props->>'v'
      UNION ALL
      SELECT ${day}::date, 'sessions', '', count(*)::int, coalesce(sum("durationSec"), 0)
        FROM analytics_sessions WHERE ${ss}::date = ${day}::date
      UNION ALL
      SELECT ${day}::date, 'sessions_platform', platform, count(*)::int, 0
        FROM analytics_sessions WHERE ${ss}::date = ${day}::date GROUP BY platform
      UNION ALL
      SELECT ${day}::date, 'dau', '', count(DISTINCT "userId")::int, 0
        FROM analytics_sessions WHERE ${ss}::date = ${day}::date AND "userId" IS NOT NULL
      UNION ALL
      SELECT ${day}::date, 'dau_devices', '', count(DISTINCT "deviceId")::int, 0
        FROM analytics_sessions WHERE ${ss}::date = ${day}::date`,
  ]);
}

export async function purgeOld(): Promise<{ events: number; sessions: number }> {
  const events = await prisma.$executeRaw`
    DELETE FROM analytics_events WHERE "createdAt" < now() - make_interval(days => ${EVENT_RETENTION_DAYS}::int)`;
  const sessions = await prisma.$executeRaw`
    DELETE FROM analytics_sessions WHERE "startedAt" < now() - make_interval(days => ${SESSION_RETENTION_DAYS}::int)`;
  return { events, sessions };
}

// ─────────────────────────────── Resumen para el admin ───────────────────────────────

const RANGES = { '7d': 7, '30d': 30, '90d': 90, '365d': 365 } as const;
export type AnalyticsRange = keyof typeof RANGES;

const num = (v: unknown) => (v === null || v === undefined ? 0 : Number(v));
const round = (v: unknown, d = 1) => {
  const f = 10 ** d;
  return Math.round(num(v) * f) / f;
};

/** Fecha de una columna ::date (Prisma la devuelve como Date en UTC) → 'YYYY-MM-DD'. */
const dayStr = (v: unknown) => (v instanceof Date ? v.toISOString().slice(0, 10) : String(v));

type Row = Record<string, unknown>;
const q = (s: Prisma.Sql) => prisma.$queryRaw<Row[]>(s);

export async function getAdminSummary(rangeKey: string) {
  const key: AnalyticsRange = rangeKey in RANGES ? (rangeKey as AnalyticsRange) : '30d';
  const days = RANGES[key];
  const bucket = days <= 30 ? 'day' : days <= 90 ? 'week' : 'month';
  const B = Prisma.raw(`'${bucket}'`);
  const from = new Date(Date.now() - days * 86_400_000);

  const sStart = local('"startedAt"');
  const bCreated = local('b."createdAt"');
  const uCreated = local('"createdAt"');

  const [
    audienceSeries, audienceTotals, dauRow, mauRow, platform, versions, roles, activityHeat,
    newUsers, retentionRows,
    bizSeries, bizTotals, repeatRow, leadRow,
    byService, byZone, byPetSize, bySlot, byPay, cancelReasons, bookingHeat,
    eventSessions, screens, prefs, topCg, firstBooking, storage,
  ] = await Promise.all([
    q(Prisma.sql`SELECT date_trunc(${B}, ${sStart})::date AS b, count(*)::int AS sessions,
        count(DISTINCT coalesce("userId", "deviceId"))::int AS users,
        coalesce(avg("durationSec"), 0)::float8 AS avg_sec
      FROM analytics_sessions WHERE "startedAt" >= ${from} GROUP BY 1 ORDER BY 1`),
    q(Prisma.sql`SELECT count(*)::int AS sessions,
        count(DISTINCT coalesce("userId", "deviceId"))::int AS users,
        count(DISTINCT "deviceId")::int AS devices,
        coalesce(avg("durationSec"), 0)::float8 AS avg_sec,
        coalesce(percentile_cont(0.5) WITHIN GROUP (ORDER BY "durationSec"), 0)::float8 AS median_sec,
        coalesce(avg("screenCount"), 0)::float8 AS avg_screens,
        count(*) FILTER (WHERE "screenCount" <= 1)::int AS bounces
      FROM analytics_sessions WHERE "startedAt" >= ${from}`),
    q(Prisma.sql`SELECT coalesce(avg(n), 0)::float8 AS dau FROM (
        SELECT count(DISTINCT "userId") AS n FROM analytics_sessions
         WHERE "startedAt" >= now() - make_interval(days => ${Math.min(days, 30)}::int) AND "userId" IS NOT NULL
         GROUP BY ${sStart}::date) d`),
    q(Prisma.sql`SELECT count(DISTINCT "userId")::int AS mau FROM analytics_sessions
       WHERE "startedAt" >= now() - interval '30 days' AND "userId" IS NOT NULL`),
    q(Prisma.sql`SELECT platform AS k, count(*)::int AS n FROM analytics_sessions
       WHERE "startedAt" >= ${from} GROUP BY 1 ORDER BY 2 DESC`),
    q(Prisma.sql`SELECT coalesce("appVersion", '?') AS k, count(*)::int AS n FROM analytics_sessions
       WHERE "startedAt" >= ${from} GROUP BY 1 ORDER BY 2 DESC LIMIT 6`),
    q(Prisma.sql`SELECT coalesce(role, 'GUEST') AS k, count(*)::int AS n FROM analytics_sessions
       WHERE "startedAt" >= ${from} GROUP BY 1 ORDER BY 2 DESC`),
    q(Prisma.sql`SELECT extract(dow FROM ${sStart})::int AS dow, extract(hour FROM ${sStart})::int AS hr,
        count(*)::int AS n FROM analytics_sessions WHERE "startedAt" >= ${from} GROUP BY 1, 2`),

    q(Prisma.sql`SELECT date_trunc(${B}, ${uCreated})::date AS b, role::text AS role, count(*)::int AS n
      FROM users WHERE "createdAt" >= ${from} AND "isDeleted" = false GROUP BY 1, 2 ORDER BY 1`),
    // Retención "volvió en o después del día N" sobre usuarios registrados en el rango
    // y con edad suficiente para poder medirla.
    q(Prisma.sql`SELECT n.d AS day,
        count(*)::int AS base,
        count(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM analytics_sessions s
           WHERE s."userId" = u.id AND s."startedAt" >= u."createdAt" + make_interval(days => n.d)))::int AS returned
      FROM users u CROSS JOIN (VALUES (1), (7), (30)) AS n(d)
      WHERE u."createdAt" >= ${from} AND u."createdAt" <= now() - make_interval(days => n.d)
        AND u."isDeleted" = false AND u.role::text <> 'ADMIN'
      GROUP BY n.d ORDER BY n.d`),

    q(Prisma.sql`SELECT date_trunc(${B}, ${bCreated})::date AS b,
        count(*)::int AS created,
        count(*) FILTER (WHERE b."paidAt" IS NOT NULL)::int AS paid,
        coalesce(sum(b."totalAmount") FILTER (WHERE b."paidAt" IS NOT NULL), 0)::float8 AS gmv,
        coalesce(sum(b."commissionAmount") FILTER (WHERE b."paidAt" IS NOT NULL), 0)::float8 AS commission,
        count(*) FILTER (WHERE b.status::text IN ('CANCELLED', 'REJECTED_BY_CAREGIVER'))::int AS cancelled
      FROM bookings b WHERE b."createdAt" >= ${from} AND b."createdByAdmin" = false GROUP BY 1 ORDER BY 1`),
    q(Prisma.sql`SELECT count(*)::int AS created,
        count(*) FILTER (WHERE "paidAt" IS NOT NULL)::int AS paid,
        count(*) FILTER (WHERE status::text = 'COMPLETED')::int AS completed,
        count(*) FILTER (WHERE status::text IN ('CANCELLED', 'REJECTED_BY_CAREGIVER'))::int AS cancelled,
        coalesce(sum("totalAmount") FILTER (WHERE "paidAt" IS NOT NULL), 0)::float8 AS gmv,
        coalesce(sum("commissionAmount") FILTER (WHERE "paidAt" IS NOT NULL), 0)::float8 AS commission,
        coalesce(avg("totalAmount") FILTER (WHERE "paidAt" IS NOT NULL), 0)::float8 AS avg_ticket,
        count(*) FILTER (WHERE "promoCode" IS NOT NULL AND "paidAt" IS NOT NULL)::int AS promo_used,
        count(*) FILTER (WHERE "tipAmount" IS NOT NULL)::int AS tipped,
        coalesce(avg("ownerRating") FILTER (WHERE "ownerRating" IS NOT NULL), 0)::float8 AS avg_rating,
        coalesce(percentile_cont(0.5) WITHIN GROUP (
          ORDER BY extract(epoch FROM ("paidAt" - "createdAt")) / 60) FILTER (WHERE "paidAt" IS NOT NULL), 0)::float8 AS median_min_to_pay
      FROM bookings WHERE "createdAt" >= ${from} AND "createdByAdmin" = false`),
    q(Prisma.sql`SELECT count(*)::int AS payers,
        count(*) FILTER (WHERE n >= 2)::int AS repeaters FROM (
          SELECT "clientId", count(*) AS n FROM bookings
           WHERE "paidAt" IS NOT NULL AND "createdByAdmin" = false GROUP BY 1) t`),
    q(Prisma.sql`SELECT coalesce(percentile_cont(0.5) WITHIN GROUP (
        ORDER BY (b."startDate"::date - ${bCreated}::date)), 0)::float8 AS median_lead_days
      FROM bookings b WHERE b."createdAt" >= ${from} AND b."startDate" IS NOT NULL AND b."createdByAdmin" = false`),

    q(Prisma.sql`SELECT "serviceType"::text AS k, count(*)::int AS n, coalesce(sum("totalAmount"), 0)::float8 AS gmv
      FROM bookings WHERE "createdAt" >= ${from} AND "paidAt" IS NOT NULL AND "createdByAdmin" = false
      GROUP BY 1 ORDER BY 2 DESC`),
    q(Prisma.sql`SELECT coalesce(c.zone::text, 'SIN_ZONA') AS k, count(*)::int AS n
      FROM bookings b JOIN caregiver_profiles c ON c.id = b."caregiverId"
      WHERE b."createdAt" >= ${from} AND b."paidAt" IS NOT NULL AND b."createdByAdmin" = false
      GROUP BY 1 ORDER BY 2 DESC LIMIT 10`),
    q(Prisma.sql`SELECT coalesce("petSize"::text, 'N/D') AS k, count(*)::int AS n FROM bookings
      WHERE "createdAt" >= ${from} AND "paidAt" IS NOT NULL AND "createdByAdmin" = false GROUP BY 1 ORDER BY 2 DESC`),
    q(Prisma.sql`SELECT coalesce("timeSlot"::text, 'N/D') AS k, count(*)::int AS n FROM bookings
      WHERE "createdAt" >= ${from} AND "paidAt" IS NOT NULL AND "createdByAdmin" = false AND "serviceType"::text = 'PASEO'
      GROUP BY 1 ORDER BY 2 DESC`),
    q(Prisma.sql`SELECT CASE WHEN "stripePaymentIntentId" IS NOT NULL OR "stripeCheckoutSessionId" IS NOT NULL THEN 'TARJETA'
                         WHEN "walletPaymentAmount" >= "totalAmount" THEN 'BILLETERA'
                         WHEN "walletPaymentAmount" > 0 THEN 'QR + BILLETERA'
                         ELSE 'QR' END AS k, count(*)::int AS n FROM bookings
      WHERE "createdAt" >= ${from} AND "paidAt" IS NOT NULL AND "createdByAdmin" = false GROUP BY 1 ORDER BY 2 DESC`),
    q(Prisma.sql`SELECT coalesce("cancellationReasonCode", 'SIN_MOTIVO') AS k, count(*)::int AS n FROM bookings
      WHERE "createdAt" >= ${from} AND status::text = 'CANCELLED' AND "createdByAdmin" = false GROUP BY 1 ORDER BY 2 DESC`),
    q(Prisma.sql`SELECT extract(dow FROM ${bCreated})::int AS dow, extract(hour FROM ${bCreated})::int AS hr,
        count(*)::int AS n FROM bookings b
      WHERE b."createdAt" >= ${from} AND b."createdByAdmin" = false GROUP BY 1, 2`),

    q(Prisma.sql`SELECT replace(metric, 'event_sessions:', '') AS k, sum("count")::int AS n FROM analytics_daily
      WHERE day >= ${from}::date AND metric LIKE 'event_sessions:%' GROUP BY 1`),
    q(Prisma.sql`SELECT dim AS k, sum("count")::int AS views, coalesce(sum("sum"), 0)::float8 AS ms FROM analytics_daily
      WHERE day >= ${from}::date AND metric = 'screen' GROUP BY 1 ORDER BY 2 DESC LIMIT 20`),
    q(Prisma.sql`SELECT replace(metric, 'pref:', '') AS pref, dim AS v, sum("count")::int AS n FROM analytics_daily
      WHERE day >= ${from}::date AND metric LIKE 'pref:%' GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 60`),
    q(Prisma.sql`SELECT v.cid, v.views,
        u."firstName" || ' ' || left(u."lastName", 1) || '.' AS name,
        (SELECT count(*)::int FROM bookings b WHERE b."caregiverId" = v.cid
            AND b."createdAt" >= ${from} AND b."paidAt" IS NOT NULL) AS booked
      FROM (SELECT dim AS cid, sum("count")::int AS views FROM analytics_daily
             WHERE day >= ${from}::date AND metric = 'cg_view' GROUP BY 1 ORDER BY 2 DESC LIMIT 10) v
      LEFT JOIN caregiver_profiles c ON c.id = v.cid LEFT JOIN users u ON u.id = c."userId"`),
    q(Prisma.sql`SELECT coalesce(percentile_cont(0.5) WITHIN GROUP (
        ORDER BY extract(epoch FROM (f.first_at - u."createdAt")) / 3600), 0)::float8 AS median_hours
      FROM users u JOIN (SELECT "clientId", min("createdAt") AS first_at FROM bookings
                          WHERE "paidAt" IS NOT NULL GROUP BY 1) f ON f."clientId" = u.id
      WHERE u."createdAt" >= ${from}`),
    q(Prisma.sql`SELECT 'analytics_events' AS t, pg_total_relation_size('analytics_events')::float8 AS bytes,
        (SELECT count(*) FROM analytics_events)::int AS n
      UNION ALL SELECT 'analytics_sessions', pg_total_relation_size('analytics_sessions')::float8,
        (SELECT count(*) FROM analytics_sessions)::int
      UNION ALL SELECT 'analytics_daily', pg_total_relation_size('analytics_daily')::float8,
        (SELECT count(*) FROM analytics_daily)::int`),
  ]);

  const a = audienceTotals[0] ?? {};
  const biz = bizTotals[0] ?? {};
  const created = num(biz.created);
  const paid = num(biz.paid);
  const evMap = Object.fromEntries(eventSessions.map((r) => [String(r.k), num(r.n)]));
  const mau = num(mauRow[0]?.mau);
  const dau = num(dauRow[0]?.dau);

  const newUsersByBucket = new Map<string, { clients: number; caregivers: number }>();
  for (const r of newUsers) {
    const k = dayStr(r.b);
    const cur = newUsersByBucket.get(k) ?? { clients: 0, caregivers: 0 };
    if (r.role === 'CLIENT') cur.clients += num(r.n);
    else if (r.role === 'CAREGIVER') cur.caregivers += num(r.n);
    newUsersByBucket.set(k, cur);
  }

  const kv = (rows: Row[]) => rows.map((r) => ({ key: String(r.k), n: num(r.n) }));
  const heat = (rows: Row[]) => rows.map((r) => ({ dow: num(r.dow), hour: num(r.hr), n: num(r.n) }));

  return {
    range: key,
    bucket,
    generatedAt: new Date().toISOString(),
    audience: {
      sessions: num(a.sessions),
      activeUsers: num(a.users),
      devices: num(a.devices),
      avgSessionSec: round(a.avg_sec, 0),
      medianSessionSec: round(a.median_sec, 0),
      avgScreensPerSession: round(a.avg_screens, 1),
      bounceRate: num(a.sessions) ? round((num(a.bounces) / num(a.sessions)) * 100) : 0,
      dauAvg: round(dau, 1),
      mau,
      stickinessPct: mau ? round((dau / mau) * 100) : 0,
      series: audienceSeries.map((r) => ({
        bucket: dayStr(r.b), sessions: num(r.sessions), users: num(r.users), avgSec: round(r.avg_sec, 0),
      })),
      platform: kv(platform),
      versions: kv(versions),
      roles: kv(roles),
      activityHeat: heat(activityHeat),
    },
    users: {
      newSeries: [...newUsersByBucket.entries()].map(([bucketKey, v]) => ({ bucket: bucketKey, ...v })),
      retention: retentionRows.map((r) => ({
        day: num(r.day), base: num(r.base), returned: num(r.returned),
        pct: num(r.base) ? round((num(r.returned) / num(r.base)) * 100) : 0,
      })),
      medianHoursSignupToFirstPaidBooking: round(firstBooking[0]?.median_hours, 1),
    },
    business: {
      bookingsCreated: created,
      bookingsPaid: paid,
      bookingsCompleted: num(biz.completed),
      paidConversionPct: created ? round((paid / created) * 100) : 0,
      cancelRatePct: created ? round((num(biz.cancelled) / created) * 100) : 0,
      gmv: round(biz.gmv, 2),
      commission: round(biz.commission, 2),
      avgTicket: round(biz.avg_ticket, 2),
      promoUsagePct: paid ? round((num(biz.promo_used) / paid) * 100) : 0,
      tipRatePct: num(biz.completed) ? round((num(biz.tipped) / num(biz.completed)) * 100) : 0,
      avgRating: round(biz.avg_rating, 2),
      medianMinutesToPay: round(biz.median_min_to_pay, 0),
      medianLeadDays: round(leadRow[0]?.median_lead_days, 1),
      repeatRatePct: num(repeatRow[0]?.payers)
        ? round((num(repeatRow[0]?.repeaters) / num(repeatRow[0]?.payers)) * 100) : 0,
      series: bizSeries.map((r) => ({
        bucket: dayStr(r.b), created: num(r.created), paid: num(r.paid), cancelled: num(r.cancelled),
        gmv: round(r.gmv, 2), commission: round(r.commission, 2),
      })),
    },
    preferences: {
      byService: byService.map((r) => ({ key: String(r.k), n: num(r.n), gmv: round(r.gmv, 2) })),
      byZone: kv(byZone),
      byPetSize: kv(byPetSize),
      byWalkSlot: kv(bySlot),
      byPaymentMethod: kv(byPay),
      cancelReasons: kv(cancelReasons),
      bookingHeat: heat(bookingHeat),
      filters: prefs.map((r) => ({ pref: String(r.pref), value: String(r.v), n: num(r.n) })),
    },
    funnel: [
      { step: 'Entraron al marketplace', n: evMap['marketplace_view'] ?? 0 },
      { step: 'Abrieron un cuidador', n: evMap['caregiver_open'] ?? 0 },
      { step: 'Empezaron una reserva', n: evMap['booking_start'] ?? 0 },
      { step: 'Enviaron la reserva', n: evMap['booking_submit'] ?? 0 },
      { step: 'Reservas pagadas', n: paid },
    ],
    screens: screens.map((r) => ({
      screen: String(r.k), views: num(r.views),
      avgSec: num(r.views) ? round(num(r.ms) / num(r.views) / 1000, 1) : 0,
    })),
    topCaregivers: topCg.map((r) => ({
      id: String(r.cid), name: (r.name as string | null) ?? '—', views: num(r.views), booked: num(r.booked),
      conversionPct: num(r.views) ? round((num(r.booked) / num(r.views)) * 100) : 0,
    })),
    storage: {
      retentionDays: { events: EVENT_RETENTION_DAYS, sessions: SESSION_RETENTION_DAYS },
      tables: storage.map((r) => ({ table: String(r.t), mb: round(num(r.bytes) / 1_048_576, 2), rows: num(r.n) })),
    },
  };
}

// ─────────────────────────────── Impacto del rediseño ───────────────────────────────

/**
 * Inicio del rediseño de la app (fase 0 en producción): 2 de octubre de 2026,
 * 00:00 en Bolivia. Ver el plan en la sección "Cómo medimos".
 */
export const REDESIGN_LAUNCH = new Date('2026-10-02T04:00:00Z');
/** "Antes" = todo el historial previo al lanzamiento (hay poco uso real todavía). */
const HISTORY_START = new Date('2026-01-01T04:00:00Z');
/** Debajo de esto la comparación es ruido; la app lo marca como muestra chica. */
export const IMPACT_MIN_SAMPLE = 20;

/** Cuentas de prueba (reviewer.*@gardenbo.com): fuera de todas las métricas. */
const TEST_USERS = Prisma.sql`(SELECT id FROM users WHERE email LIKE 'reviewer.%@gardenbo.com')`;

type Window = { from: Date; to: Date };

/** Una métrica del plan medida antes y después del lanzamiento. */
export interface ImpactMetric {
  key: string;
  label: string;
  /** '%' | 'h' | 'x' (promedio) | '/100' */
  unit: string;
  /** Qué dirección es buena; 'none' cuando más no siempre es mejor. */
  better: 'up' | 'down' | 'none';
  before: number | null;
  after: number | null;
  /** Tamaño de la muestra de cada ventana (reservas, usuarios, cuidadores…). */
  nBefore: number;
  nAfter: number;
  note?: string;
}

const pct = (part: unknown, total: unknown) => (num(total) ? round((num(part) / num(total)) * 100) : null);

async function impactWindow(w: Window) {
  const { from, to } = w;
  const [conv, signup, msgs, mapOpens, support, rated, repeat, cgReg] = await Promise.all([
    // 1. De reserva creada a reserva pagada
    q(Prisma.sql`SELECT count(*)::int AS created, count(*) FILTER (WHERE "paidAt" IS NOT NULL)::int AS paid
      FROM bookings WHERE "createdAt" >= ${from} AND "createdAt" < ${to} AND "createdByAdmin" = false AND "clientId" NOT IN ${TEST_USERS}`),
    // 2. Horas desde el registro hasta la primera reserva pagada (dueños registrados en la ventana)
    q(Prisma.sql`SELECT count(*)::int AS n, coalesce(percentile_cont(0.5) WITHIN GROUP (
        ORDER BY extract(epoch FROM (f.first_at - u."createdAt")) / 3600), 0)::float8 AS median_h
      FROM users u JOIN (SELECT "clientId", min("paidAt") AS first_at FROM bookings
                          WHERE "paidAt" IS NOT NULL AND "createdByAdmin" = false GROUP BY 1) f ON f."clientId" = u.id
      WHERE u."createdAt" >= ${from} AND u."createdAt" < ${to} AND u.id NOT IN ${TEST_USERS}`),
    // 3a. Mensajes de personas por reserva pagada
    q(Prisma.sql`SELECT count(*)::int AS n, coalesce(avg(m.c), 0)::float8 AS avg_msgs FROM (
        SELECT b.id, (SELECT count(*) FROM chat_messages cm WHERE cm."bookingId" = b.id AND cm."isSystem" = false) AS c
          FROM bookings b WHERE b."paidAt" >= ${from} AND b."paidAt" < ${to} AND b."createdByAdmin" = false AND b."clientId" NOT IN ${TEST_USERS}) m`),
    // 3b. Aperturas del mapa por el dueño por paseo iniciado (evento map_open)
    q(Prisma.sql`SELECT
        (SELECT count(*) FROM analytics_events WHERE name = 'map_open' AND props->>'role' = 'CLIENT'
           AND "createdAt" >= ${from} AND "createdAt" < ${to})::int AS opens,
        (SELECT count(*) FROM bookings WHERE "serviceType"::text = 'PASEO' AND "createdByAdmin" = false
           AND "clientId" NOT IN ${TEST_USERS}
           AND "serviceStartedAt" >= ${from} AND "serviceStartedAt" < ${to})::int AS walks,
        (SELECT count(*) FROM analytics_events WHERE name = 'map_open' AND "createdAt" < ${to})::int AS ever`),
    // 4. Conversaciones de soporte de dueños cada 100 reservas pagadas
    q(Prisma.sql`SELECT
        (SELECT count(DISTINCT sm."threadId") FROM support_messages sm
           JOIN support_threads st ON st.id = sm."threadId" JOIN users u ON u.id = st."userId"
          WHERE sm."senderRole" = 'CLIENT' AND u.role::text = 'CLIENT' AND u.id NOT IN ${TEST_USERS}
            AND sm."createdAt" >= ${from} AND sm."createdAt" < ${to})::int AS threads,
        (SELECT count(*) FROM bookings WHERE "paidAt" >= ${from} AND "paidAt" < ${to} AND "createdByAdmin" = false
           AND "clientId" NOT IN ${TEST_USERS})::int AS paid`),
    // 5. Reservas terminadas que el dueño calificó, y la nota media
    q(Prisma.sql`SELECT count(*)::int AS done, count(*) FILTER (WHERE "ownerRating" IS NOT NULL)::int AS rated,
        coalesce(avg("ownerRating"), 0)::float8 AS avg_rating
      FROM bookings WHERE status::text = 'COMPLETED' AND "createdByAdmin" = false
        AND "serviceEndedAt" >= ${from} AND "serviceEndedAt" < ${to} AND "clientId" NOT IN ${TEST_USERS}`),
    // 6. Reservas pagadas que repiten cuidador: el mismo dueño ya le había pagado en los 30 días previos
    q(Prisma.sql`SELECT count(*)::int AS paid, count(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM bookings p WHERE p."clientId" = b."clientId" AND p."caregiverId" = b."caregiverId"
             AND p.id <> b.id AND p."paidAt" IS NOT NULL AND p."createdByAdmin" = false
             AND p."paidAt" < b."paidAt" AND p."paidAt" >= b."paidAt" - interval '30 days'))::int AS repeats
      FROM bookings b WHERE b."paidAt" >= ${from} AND b."paidAt" < ${to} AND b."createdByAdmin" = false AND "clientId" NOT IN ${TEST_USERS}`),
    // 7. Cuidadores que empezaron el registro en la ventana y lo enviaron a revisión
    q(Prisma.sql`SELECT count(*)::int AS started, count(*) FILTER (WHERE status::text <> 'DRAFT')::int AS submitted
      FROM caregiver_profiles WHERE "createdAt" >= ${from} AND "createdAt" < ${to} AND "userId" NOT IN ${TEST_USERS}`),
  ]);
  return {
    conv: conv[0] ?? {}, signup: signup[0] ?? {}, msgs: msgs[0] ?? {}, map: mapOpens[0] ?? {},
    support: support[0] ?? {}, rated: rated[0] ?? {}, repeat: repeat[0] ?? {}, cgReg: cgReg[0] ?? {},
  };
}

export async function getRedesignImpact() {
  const now = new Date();
  const after: Window = { from: REDESIGN_LAUNCH, to: now };
  const before: Window = { from: HISTORY_START, to: REDESIGN_LAUNCH };
  const [b, a, draftSteps] = await Promise.all([
    impactWindow(before),
    impactWindow(after),
    // Dónde quedan los registros de cuidador sin enviar (empezados después del lanzamiento)
    q(Prisma.sql`SELECT coalesce(("onboardingStatus"->>'step'), '?') AS step, count(*)::int AS n
      FROM caregiver_profiles WHERE status::text = 'DRAFT' AND "createdAt" >= ${REDESIGN_LAUNCH}
        AND "userId" NOT IN ${TEST_USERS}
      GROUP BY 1 ORDER BY 2 DESC LIMIT 10`),
  ]);

  const ratingNote = (w: typeof a) => (num(w.rated.rated) ? String(round(w.rated.avg_rating, 2)) : '—');
  const metrics: ImpactMetric[] = [
    {
      key: 'paid_conversion', label: 'Reservas creadas que se pagan', unit: '%', better: 'up',
      before: pct(b.conv.paid, b.conv.created), after: pct(a.conv.paid, a.conv.created),
      nBefore: num(b.conv.created), nAfter: num(a.conv.created),
      note: 'Si el perfil y la reserva generan confianza suficiente para pagar.',
    },
    {
      key: 'signup_to_first_paid', label: 'Del registro a la primera reserva pagada', unit: 'h', better: 'down',
      before: num(b.signup.n) ? round(b.signup.median_h, 1) : null,
      after: num(a.signup.n) ? round(a.signup.median_h, 1) : null,
      nBefore: num(b.signup.n), nAfter: num(a.signup.n),
      note: 'Mediana, solo dueños que ya pagaron alguna reserva.',
    },
    {
      key: 'messages_per_booking', label: 'Mensajes por reserva pagada', unit: 'x', better: 'none',
      before: num(b.msgs.n) ? round(b.msgs.avg_msgs, 1) : null,
      after: num(a.msgs.n) ? round(a.msgs.avg_msgs, 1) : null,
      nBefore: num(b.msgs.n), nAfter: num(a.msgs.n),
      note: 'Más no siempre es mejor: muchos mensajes pueden ser ansiedad.',
    },
    {
      key: 'map_opens_per_walk', label: 'Veces que el dueño abre el mapa por paseo', unit: 'x', better: 'none',
      before: null,
      after: num(a.map.ever) && num(a.map.walks) ? round(num(a.map.opens) / num(a.map.walks), 1) : null,
      nBefore: num(b.map.walks), nAfter: num(a.map.walks),
      note: 'Se empezó a medir con esta versión; no hay dato anterior.',
    },
    {
      key: 'support_per_100', label: 'Conversaciones de soporte de dueños cada 100 reservas', unit: '/100', better: 'down',
      before: num(b.support.paid) ? round((num(b.support.threads) / num(b.support.paid)) * 100, 1) : null,
      after: num(a.support.paid) ? round((num(a.support.threads) / num(a.support.paid)) * 100, 1) : null,
      nBefore: num(b.support.paid), nAfter: num(a.support.paid),
      note: 'Ansiedad sin resolver: debería bajar.',
    },
    {
      key: 'rated_pct', label: 'Reservas terminadas que el dueño califica', unit: '%', better: 'up',
      before: pct(b.rated.rated, b.rated.done), after: pct(a.rated.rated, a.rated.done),
      nBefore: num(b.rated.done), nAfter: num(a.rated.done),
      note: `Nota media: ${ratingNote(b)} antes, ${ratingNote(a)} después.`,
    },
    {
      key: 'repeat_same_caregiver', label: 'Reservas que repiten cuidador en 30 días', unit: '%', better: 'up',
      before: pct(b.repeat.repeats, b.repeat.paid), after: pct(a.repeat.repeats, a.repeat.paid),
      nBefore: num(b.repeat.paid), nAfter: num(a.repeat.paid),
      note: 'El vínculo que convierte la app en hábito.',
    },
    {
      key: 'caregiver_registration', label: 'Cuidadores que terminan el registro', unit: '%', better: 'up',
      before: pct(b.cgReg.submitted, b.cgReg.started), after: pct(a.cgReg.submitted, a.cgReg.started),
      nBefore: num(b.cgReg.started), nAfter: num(a.cgReg.started),
      note: 'Enviaron el perfil a revisión sobre los que lo empezaron.',
    },
  ];

  return {
    launch: REDESIGN_LAUNCH.toISOString(),
    minSample: IMPACT_MIN_SAMPLE,
    before: { from: before.from.toISOString(), to: before.to.toISOString() },
    after: { from: after.from.toISOString(), to: after.to.toISOString() },
    metrics,
    draftSteps: draftSteps.map((r) => ({ step: String(r.step), n: num(r.n) })),
  };
}
