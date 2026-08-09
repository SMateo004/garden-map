package com.garden.bolivia.widget

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File

/**
 * Estado global del widget de "servicio activo" — un único servicio a la vez
 * (igual que el Live Activity de iOS: no hay concepto de varios en simultáneo
 * para el mismo usuario), así que se guarda en SharedPreferences simple en
 * vez del sistema de estado por-instancia de Glance (pensado para widgets
 * configurables con datos distintos por instancia, que no es nuestro caso).
 *
 * Lo escribe [com.garden.bolivia.MainActivity] cuando Dart llama al
 * MethodChannel `com.gardenbo.app/android_widget` (ver GardenLiveActivity en
 * garden_live_activity.dart), y lo lee la Composable de
 * [GardenActiveServiceWidget] cada vez que Android la redibuja.
 */
object GardenWidgetData {
    private const val PREFS_NAME = "garden_active_service_widget"

    private const val KEY_ACTIVE = "active"
    private const val KEY_PET_NAME = "petName"
    private const val KEY_SUBTITLE = "subtitle"
    private const val KEY_SERVICE_TYPE = "serviceType"
    private const val KEY_STATUS = "status"
    private const val KEY_STARTED_AT_MS = "startedAtMs"
    private const val KEY_TOTAL_PAID_SECONDS = "totalPaidSeconds"
    private const val KEY_BOOKING_ID = "bookingId"
    private const val KEY_ROLE = "role"

    data class ActiveService(
        val petName: String,
        val subtitle: String,
        val serviceType: String,
        val status: String,
        val startedAtMs: Long,
        val totalPaidSeconds: Int,
        val bookingId: String,
        val role: String,
    )

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(context: Context, data: ActiveService) {
        prefs(context).edit()
            .putBoolean(KEY_ACTIVE, true)
            .putString(KEY_PET_NAME, data.petName)
            .putString(KEY_SUBTITLE, data.subtitle)
            .putString(KEY_SERVICE_TYPE, data.serviceType)
            .putString(KEY_STATUS, data.status)
            .putLong(KEY_STARTED_AT_MS, data.startedAtMs)
            .putInt(KEY_TOTAL_PAID_SECONDS, data.totalPaidSeconds)
            .putString(KEY_BOOKING_ID, data.bookingId)
            .putString(KEY_ROLE, data.role)
            .apply()
    }

    fun clear(context: Context) {
        prefs(context).edit().putBoolean(KEY_ACTIVE, false).apply()
        clearMapSnapshot(context)
    }

    // ── Mini-mapa (idea #1) ──────────────────────────────────────────────
    // Se guarda como archivo aparte (no SharedPreferences — no es para datos
    // binarios) en el almacenamiento interno de la app, privado por
    // definición: ningún otro proceso puede leerlo. Sobrescrito cada ~30s
    // mientras haya un PASEO en curso (ver _updateMapSnapshot en
    // service_execution_screen.dart), y borrado junto con el resto del
    // estado cuando el servicio termina.
    private const val MAP_SNAPSHOT_FILENAME = "widget_map_snapshot.png"

    fun saveMapSnapshot(context: Context, pngBytes: ByteArray) {
        File(context.filesDir, MAP_SNAPSHOT_FILENAME).writeBytes(pngBytes)
    }

    fun loadMapSnapshot(context: Context): Bitmap? {
        val file = File(context.filesDir, MAP_SNAPSHOT_FILENAME)
        if (!file.exists()) return null
        return try {
            BitmapFactory.decodeFile(file.absolutePath)
        } catch (e: Exception) {
            null
        }
    }

    private fun clearMapSnapshot(context: Context) {
        File(context.filesDir, MAP_SNAPSHOT_FILENAME).delete()
    }

    // ── Countdown de próxima reserva (idea #3) ───────────────────────────
    // Estado independiente del servicio activo de arriba — vive en el mismo
    // archivo de SharedPreferences pero con sus propias keys porque ambos
    // widgets (servicio activo / búsqueda rápida) pueden tener datos a la
    // vez sin relación entre sí (ej.: un PASEO en curso Y una reserva de
    // HOSPEDAJE confirmada para la semana que viene).
    private const val KEY_NEXT_BOOKING_ACTIVE = "nextBookingActive"
    private const val KEY_NEXT_PET_NAME = "nextBookingPetName"
    private const val KEY_NEXT_SERVICE_TYPE = "nextBookingServiceType"
    private const val KEY_NEXT_STARTS_AT_MS = "nextBookingStartsAtMs"
    private const val KEY_NEXT_COUNTERPART_NAME = "nextBookingCounterpartName"

    data class NextBooking(
        val petName: String,
        val serviceType: String,
        val startsAtMs: Long,
        val counterpartName: String,
    )

    fun saveNextBooking(context: Context, data: NextBooking) {
        prefs(context).edit()
            .putBoolean(KEY_NEXT_BOOKING_ACTIVE, true)
            .putString(KEY_NEXT_PET_NAME, data.petName)
            .putString(KEY_NEXT_SERVICE_TYPE, data.serviceType)
            .putLong(KEY_NEXT_STARTS_AT_MS, data.startsAtMs)
            .putString(KEY_NEXT_COUNTERPART_NAME, data.counterpartName)
            .apply()
    }

    fun clearNextBooking(context: Context) {
        prefs(context).edit().putBoolean(KEY_NEXT_BOOKING_ACTIVE, false).apply()
    }

    fun loadNextBooking(context: Context): NextBooking? {
        val p = prefs(context)
        if (!p.getBoolean(KEY_NEXT_BOOKING_ACTIVE, false)) return null
        val startsAtMs = p.getLong(KEY_NEXT_STARTS_AT_MS, 0L)
        if (startsAtMs <= System.currentTimeMillis()) return null // ya pasó — no mostrar countdown vencido
        return NextBooking(
            petName = p.getString(KEY_NEXT_PET_NAME, "") ?: "",
            serviceType = p.getString(KEY_NEXT_SERVICE_TYPE, "PASEO") ?: "PASEO",
            startsAtMs = startsAtMs,
            counterpartName = p.getString(KEY_NEXT_COUNTERPART_NAME, "") ?: "",
        )
    }

    // ── Estadística mensual (idea #5) ────────────────────────────────────
    // Respaldo del widget idle cuando no hay reserva próxima (ver
    // loadNextBooking arriba) — GardenQuickSearchWidget decide la
    // precedencia entre los dos estados independientes, no esta clase.
    private const val KEY_STATS_ACTIVE = "monthlyStatsActive"
    private const val KEY_STATS_COMPLETED = "monthlyStatsCompletedCount"

    fun saveMonthlyStats(context: Context, completedThisMonth: Int) {
        prefs(context).edit()
            .putBoolean(KEY_STATS_ACTIVE, true)
            .putInt(KEY_STATS_COMPLETED, completedThisMonth)
            .apply()
    }

    fun clearMonthlyStats(context: Context) {
        prefs(context).edit().putBoolean(KEY_STATS_ACTIVE, false).apply()
    }

    /** null si no hay dato guardado o si el completedThisMonth es 0 — cero
     * servicios no es una estadística que valga la pena mostrar, es lo mismo
     * que no tener nada que decir. */
    fun loadMonthlyStats(context: Context): Int? {
        val p = prefs(context)
        if (!p.getBoolean(KEY_STATS_ACTIVE, false)) return null
        val count = p.getInt(KEY_STATS_COMPLETED, 0)
        return if (count > 0) count else null
    }

    fun load(context: Context): ActiveService? {
        val p = prefs(context)
        if (!p.getBoolean(KEY_ACTIVE, false)) return null
        return ActiveService(
            petName = p.getString(KEY_PET_NAME, "") ?: "",
            subtitle = p.getString(KEY_SUBTITLE, "") ?: "",
            serviceType = p.getString(KEY_SERVICE_TYPE, "PASEO") ?: "PASEO",
            status = p.getString(KEY_STATUS, "IN_PROGRESS") ?: "IN_PROGRESS",
            startedAtMs = p.getLong(KEY_STARTED_AT_MS, 0L),
            totalPaidSeconds = p.getInt(KEY_TOTAL_PAID_SECONDS, 3600),
            bookingId = p.getString(KEY_BOOKING_ID, "") ?: "",
            role = p.getString(KEY_ROLE, "CLIENT") ?: "CLIENT",
        )
    }
}
