package com.garden.bolivia.widget

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.garden.bolivia.MainActivity

private val QuickSearchSurface = Color(0xFF1E2D0F) // forest, tono marca
private val QuickSearchAccent = Color(0xFFB9D28A)  // lime claro sobre fondo oscuro

/**
 * Widget "acceso rápido" para cuando NO hay ningún servicio activo — mismo
 * espíritu que el widget "¿A dónde vamos?" de Uber en el home screen: una
 * sola acción clara, siempre visible, cero fricción.
 *
 * Idea #3: si el usuario tiene una reserva CONFIRMED próxima (ver
 * GardenWidgetData.loadNextBooking, empujado desde main.dart cada vez que la
 * app arranca o vuelve a primer plano — GET /bookings/next-upcoming), la
 * tarjeta muestra el countdown en vez del genérico "buscá un cuidador". Sin
 * reserva próxima, cae en el contenido original.
 */
class GardenQuickSearchWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { Content(context) }
    }

    @Composable
    private fun Content(context: Context) {
        // Precedencia: reserva próxima > estadística del mes > prompt
        // genérico. Los tres estados viven independientes en
        // GardenWidgetData — esta es la única función que decide cuál mostrar.
        val nextBooking = GardenWidgetData.loadNextBooking(context)
        val monthlyCompleted = GardenWidgetData.loadMonthlyStats(context)
        when {
            nextBooking != null -> NextBookingCard(nextBooking)
            monthlyCompleted != null -> MonthlyStatsCard(monthlyCompleted)
            else -> SearchPromptCard()
        }
    }

    @Composable
    private fun SearchPromptCard() {
        val ctx = LocalContext.current
        val launchIntent = Intent(ctx, MainActivity::class.java).apply {
            putExtra("deepLinkRoute", "/marketplace")
        }

        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(QuickSearchSurface)
                .cornerRadius(20.dp)
                .padding(16.dp)
                .clickable(actionStartActivity(launchIntent)),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = GlanceModifier
                    .width(44.dp)
                    .height(44.dp)
                    .background(Color(0x33B9D28A))
                    .cornerRadius(22.dp),
            ) {
                Text("🐾", style = TextStyle(fontSize = 20.sp))
            }
            Spacer(modifier = GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    "Buscá un cuidador",
                    maxLines = 1,
                    style = TextStyle(color = ColorProvider(Color.White), fontWeight = FontWeight.Bold, fontSize = 15.sp),
                )
                Text(
                    "Paseo, guardería u hospedaje cerca tuyo",
                    maxLines = 1,
                    style = TextStyle(color = ColorProvider(QuickSearchAccent), fontSize = 11.sp),
                )
            }
            Text("→", style = TextStyle(color = ColorProvider(Color.White), fontWeight = FontWeight.Bold, fontSize = 18.sp))
        }
    }

    @Composable
    private fun NextBookingCard(data: GardenWidgetData.NextBooking) {
        val ctx = LocalContext.current
        // /my-bookings-tab (no una ruta de detalle por-reserva — no existe una
        // estable para CONFIRMED todavía sin arrancar) está en el whitelist de
        // rutas de deep link ya usado por marketplace_screen.dart.
        val launchIntent = Intent(ctx, MainActivity::class.java).apply {
            putExtra("deepLinkRoute", "/my-bookings-tab")
        }
        val emoji = when (data.serviceType) {
            "HOSPEDAJE" -> "😴"
            else -> "🐕"
        }
        val serviceLabel = when (data.serviceType) {
            "PASEO" -> "Paseo"
            "GUARDERIA" -> "Guardería"
            else -> "Hospedaje"
        }

        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(QuickSearchSurface)
                .cornerRadius(20.dp)
                .padding(16.dp)
                .clickable(actionStartActivity(launchIntent)),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = GlanceModifier
                    .width(44.dp)
                    .height(44.dp)
                    .background(Color(0x33B9D28A))
                    .cornerRadius(22.dp),
            ) {
                Text(emoji, style = TextStyle(fontSize = 20.sp))
            }
            Spacer(modifier = GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    "$serviceLabel de ${data.petName.ifEmpty { "tu mascota" }}",
                    maxLines = 1,
                    style = TextStyle(color = ColorProvider(Color.White), fontWeight = FontWeight.Bold, fontSize = 15.sp),
                )
                Text(
                    formatCountdown(data.startsAtMs) + (data.counterpartName.takeIf { it.isNotEmpty() }?.let { " · $it" } ?: ""),
                    maxLines = 1,
                    style = TextStyle(color = ColorProvider(QuickSearchAccent), fontSize = 11.sp),
                )
            }
        }
    }

    @Composable
    private fun MonthlyStatsCard(completedThisMonth: Int) {
        val ctx = LocalContext.current
        val launchIntent = Intent(ctx, MainActivity::class.java).apply {
            putExtra("deepLinkRoute", "/my-bookings-tab")
        }
        val label = if (completedThisMonth == 1) "servicio completado este mes" else "servicios completados este mes"

        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(QuickSearchSurface)
                .cornerRadius(20.dp)
                .padding(16.dp)
                .clickable(actionStartActivity(launchIntent)),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = GlanceModifier
                    .width(44.dp)
                    .height(44.dp)
                    .background(Color(0x33B9D28A))
                    .cornerRadius(22.dp),
            ) {
                Text("✨", style = TextStyle(fontSize = 20.sp))
            }
            Spacer(modifier = GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    "$completedThisMonth $label",
                    maxLines = 2,
                    style = TextStyle(color = ColorProvider(Color.White), fontWeight = FontWeight.Bold, fontSize = 15.sp),
                )
                Text(
                    "¡Seguí así! 🐾",
                    maxLines = 1,
                    style = TextStyle(color = ColorProvider(QuickSearchAccent), fontSize = 11.sp),
                )
            }
        }
    }

    private fun formatCountdown(startsAtMs: Long): String {
        val diffMs = (startsAtMs - System.currentTimeMillis()).coerceAtLeast(0)
        val diffMin = diffMs / 60000
        return when {
            diffMin < 60 -> "En $diffMin min"
            diffMin < 24 * 60 -> "En ${diffMin / 60}h ${diffMin % 60}m"
            diffMin < 48 * 60 -> "Mañana"
            else -> "En ${diffMin / (24 * 60)} días"
        }
    }
}

/** AppWidgetProvider real — ver res/xml/garden_quick_search_widget_info.xml y
 * el <receiver> en AndroidManifest.xml. */
class GardenQuickSearchWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = GardenQuickSearchWidget()
}
