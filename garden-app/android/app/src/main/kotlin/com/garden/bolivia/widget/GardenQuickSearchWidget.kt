package com.garden.bolivia.widget

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.garden.bolivia.MainActivity
import com.garden.bolivia.widget.GardenWidgetUi.ServiceBadge

/**
 * Widget de acceso rápido (cuando no hay servicio en curso). Una sola acción
 * clara, siempre a mano. Precedencia: próxima reserva > resumen del mes >
 * buscar cuidador.
 *
 * Mismo lenguaje que la app: tú (antes "Buscá… cerca tuyo… ¡Seguí así!"),
 * íconos propios de cada servicio en vez de emojis, y la próxima reserva con
 * día y hora ("Mañana a las 9:00"), que no se vence entre refrescos como
 * "En 3h 20m".
 */
class GardenQuickSearchWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { Content(context) }
    }

    @Composable
    private fun Content(context: Context) {
        val next = GardenWidgetData.loadNextBooking(context)
        val monthly = GardenWidgetData.loadMonthlyStats(context)
        when {
            next != null -> NextBookingCard(next)
            monthly != null -> MonthlyCard(monthly)
            else -> SearchCard()
        }
    }

    private fun open(ctx: Context, route: String) = actionStartActivity(
        Intent(ctx, MainActivity::class.java).apply { putExtra("deepLinkRoute", route) },
    )

    private val card
        @Composable get() = GlanceModifier
            .fillMaxWidth()
            .background(GardenWidgetUi.surface)
            .cornerRadius(24.dp)
            .padding(horizontal = 16.dp, vertical = 14.dp)

    @Composable
    private fun SearchCard() {
        val ctx = LocalContext.current
        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = card.clickable(open(ctx, "/marketplace")),
        ) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    "Busca un cuidador",
                    maxLines = 1,
                    style = TextStyle(color = GardenWidgetUi.text, fontWeight = FontWeight.Bold, fontSize = 16.sp),
                )
                Text(
                    "Verificados y cerca de ti",
                    maxLines = 1,
                    style = TextStyle(color = GardenWidgetUi.subtext, fontSize = 12.sp),
                )
            }
            // Los tres servicios, como los mosaicos del inicio de la app.
            for (s in listOf("PASEO", "GUARDERIA", "HOSPEDAJE")) {
                Spacer(GlanceModifier.width(6.dp))
                ServiceBadge(s, 38)
            }
        }
    }

    @Composable
    private fun NextBookingCard(data: GardenWidgetData.NextBooking) {
        val ctx = LocalContext.current
        val pet = data.petName.ifEmpty { "tu mascota" }
        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = card.clickable(open(ctx, "/my-bookings-tab")),
        ) {
            ServiceBadge(data.serviceType, 46)
            Spacer(GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    "${GardenWidgetUi.label(data.serviceType)} de $pet",
                    maxLines = 1,
                    style = TextStyle(color = GardenWidgetUi.text, fontWeight = FontWeight.Bold, fontSize = 15.sp),
                )
                Text(
                    GardenWidgetUi.whenLabel(data.startsAtMs) +
                        (data.counterpartName.takeIf { it.isNotEmpty() }?.let { " · con $it" } ?: ""),
                    maxLines = 1,
                    style = TextStyle(color = GardenWidgetUi.ink(data.serviceType), fontWeight = FontWeight.Bold, fontSize = 12.sp),
                )
            }
            Text("›", style = TextStyle(color = GardenWidgetUi.subtext, fontSize = 22.sp))
        }
    }

    @Composable
    private fun MonthlyCard(completed: Int) {
        val ctx = LocalContext.current
        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = card.clickable(open(ctx, "/marketplace")),
        ) {
            Text(
                "$completed",
                style = TextStyle(color = GardenWidgetUi.primary, fontWeight = FontWeight.Bold, fontSize = 32.sp),
            )
            Spacer(GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    if (completed == 1) "servicio este mes" else "servicios este mes",
                    maxLines = 1,
                    style = TextStyle(color = GardenWidgetUi.text, fontWeight = FontWeight.Bold, fontSize = 15.sp),
                )
                Text(
                    "Toca para reservar el próximo",
                    maxLines = 1,
                    style = TextStyle(color = GardenWidgetUi.subtext, fontSize = 12.sp),
                )
            }
            Text("›", style = TextStyle(color = GardenWidgetUi.subtext, fontSize = 22.sp))
        }
    }
}

/** AppWidgetProvider real — ver res/xml/garden_quick_search_widget_info.xml y
 * el <receiver> en AndroidManifest.xml. */
class GardenQuickSearchWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = GardenQuickSearchWidget()
}
