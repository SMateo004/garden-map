package com.garden.bolivia.widget

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.height
import androidx.glance.layout.width
import androidx.glance.unit.ColorProvider
import com.garden.bolivia.R
import java.util.Calendar

/**
 * Lenguaje visual de los widgets de Android, el mismo de la app (ver
 * lib/theme/garden_theme.dart y lib/design/garden_service.dart): fondo
 * crema / carbón según el modo del teléfono, textos secundarios en gris
 * plomo, y cada servicio con su ícono propio (exportado de
 * GardenServiceIcon, res/drawable-nodpi + drawable-night-nodpi) y su color.
 * Antes: tarjeta gris #1C1C1C fija y emojis 🐕 😴 ✅ (guardería salía como paseo).
 */
internal object GardenWidgetUi {
    val surface = ColorProvider(day = Color(0xFFFAF7F2), night = Color(0xFF1A1D1B))
    val text = ColorProvider(day = Color(0xFF1E2D0F), night = Color(0xFFEEF0EE))
    val subtext = ColorProvider(day = Color(0xFF5F635E), night = Color(0xFFA3A9A4))
    val track = ColorProvider(day = Color(0xFFE6E0D4), night = Color(0xFF333834))
    val overtime = ColorProvider(day = Color(0xFFB87800), night = Color(0xFFFFC24D))
    val primary = ColorProvider(day = Color(0xFF778C43), night = Color(0xFFA3BA62))

    fun ink(service: String): ColorProvider = when (service) {
        "GUARDERIA" -> ColorProvider(day = Color(0xFFC98500), night = Color(0xFFFFC24D))
        "HOSPEDAJE" -> ColorProvider(day = Color(0xFF0F7A3E), night = Color(0xFF4FD18A))
        else -> ColorProvider(day = Color(0xFF2FA83A), night = Color(0xFF58E262))
    }

    fun soft(service: String): ColorProvider = when (service) {
        "GUARDERIA" -> ColorProvider(day = Color(0xFFFFF1D6), night = Color(0xFF33290F))
        "HOSPEDAJE" -> ColorProvider(day = Color(0xFFDCEFE3), night = Color(0xFF12301F))
        else -> ColorProvider(day = Color(0xFFE2F7DF), night = Color(0xFF173A16))
    }

    fun icon(service: String): Int = when (service) {
        "GUARDERIA" -> R.drawable.garden_svc_guarderia
        "HOSPEDAJE" -> R.drawable.garden_svc_hospedaje
        else -> R.drawable.garden_svc_paseo
    }

    fun label(service: String): String = when (service) {
        "GUARDERIA" -> "Guardería"
        "HOSPEDAJE" -> "Hospedaje"
        else -> "Paseo"
    }

    /** Ícono del servicio sobre su círculo suave (como en la app). */
    @Composable
    fun ServiceBadge(service: String, size: Int = 48) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = GlanceModifier
                .width(size.dp)
                .height(size.dp)
                .background(soft(service))
                .cornerRadius((size / 2).dp),
        ) {
            Image(
                provider = ImageProvider(icon(service)),
                contentDescription = label(service),
                modifier = GlanceModifier.width((size * 0.62).dp).height((size * 0.62).dp),
            )
        }
    }

    // ── Fechas en lenguaje simple, sin depender del idioma del teléfono ──
    private val days = arrayOf("dom", "lun", "mar", "mié", "jue", "vie", "sáb")

    fun clock(ms: Long): String {
        val c = Calendar.getInstance().apply { timeInMillis = ms }
        return "${c.get(Calendar.HOUR_OF_DAY)}:${c.get(Calendar.MINUTE).toString().padStart(2, '0')}"
    }

    /** "hoy" / "mañana" / "sáb 18". */
    fun day(ms: Long): String {
        val target = Calendar.getInstance().apply { timeInMillis = ms }
        val today = Calendar.getInstance()
        fun key(c: Calendar) = c.get(Calendar.YEAR) * 1000 + c.get(Calendar.DAY_OF_YEAR)
        val diff = key(target) - key(today)
        return when (diff) {
            0 -> "hoy"
            1 -> "mañana"
            else -> "${days[target.get(Calendar.DAY_OF_WEEK) - 1]} ${target.get(Calendar.DAY_OF_MONTH)}"
        }
    }

    /** "Hoy a las 9:00" — no se vence entre refrescos (a diferencia de "en 12 min"). */
    fun whenLabel(ms: Long): String = day(ms).replaceFirstChar { it.uppercase() } + " a las " + clock(ms)
}
