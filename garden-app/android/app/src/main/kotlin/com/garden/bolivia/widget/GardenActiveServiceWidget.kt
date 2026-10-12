package com.garden.bolivia.widget

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.garden.bolivia.MainActivity
import com.garden.bolivia.widget.GardenWidgetUi.ServiceBadge

/**
 * Widget del servicio en curso (PASEO / GUARDERÍA / HOSPEDAJE) — equivalente
 * Android del Live Activity de iOS (ios/GardenActivityWidget/).
 *
 * Responde lo mismo que la pantalla del servicio en la app: quién, con quién
 * y CUÁNDO TERMINA ("vuelve a las 10:05"), con la barra de avance en el color
 * del servicio. La hora de fin es fija, así que nunca queda vieja entre
 * refrescos; antes mostraba "12 min transcurrido", que se congelaba si la app
 * no estaba abierta (Glance no tiene reloj propio).
 */
class GardenActiveServiceWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { Content(context) }
    }

    @Composable
    private fun Content(context: Context) {
        val data = GardenWidgetData.load(context)
        if (data == null) {
            Idle(context)
            return
        }
        val launch = Intent(context, MainActivity::class.java).apply {
            putExtra("deepLinkRoute", "/service/${data.bookingId}")
            putExtra("deepLinkRole", data.role)
        }
        if (data.status == "COMPLETED") Completed(data, launch) else Live(context, data, launch)
    }

    private fun title(d: GardenWidgetData.ActiveService): String {
        val pet = d.petName.ifEmpty { "Tu mascota" }
        return if (d.role == "CLIENT") {
            when (d.serviceType) {
                "GUARDERIA" -> "$pet está en guardería"
                "HOSPEDAJE" -> "$pet está en hospedaje"
                else -> "$pet está de paseo"
            }
        } else {
            "${GardenWidgetUi.label(d.serviceType)} con $pet"
        }
    }

    @Composable
    private fun Live(context: Context, d: GardenWidgetData.ActiveService, launch: Intent) {
        val now = System.currentTimeMillis()
        val endMs = d.startedAtMs + d.totalPaidSeconds * 1000L
        val total = (endMs - d.startedAtMs).coerceAtLeast(1)
        val progress = ((now - d.startedAtMs).toFloat() / total).coerceIn(0f, 1f)
        val overtime = now > endMs
        val ink = if (overtime) GardenWidgetUi.overtime else GardenWidgetUi.ink(d.serviceType)

        // Hospedaje dura días: "hasta el sáb 18"; paseo y guardería, la hora.
        val (big, small) = when {
            d.serviceType == "HOSPEDAJE" -> GardenWidgetUi.day(endMs).replaceFirstChar { it.uppercase() } to "hasta el"
            overtime -> GardenWidgetUi.clock(endMs) to "pasó la hora"
            d.serviceType == "PASEO" && d.role == "CLIENT" -> GardenWidgetUi.clock(endMs) to "vuelve a las"
            else -> GardenWidgetUi.clock(endMs) to "termina a las"
        }

        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(GardenWidgetUi.surface)
                .cornerRadius(24.dp)
                .padding(16.dp)
                .clickable(actionStartActivity(launch)),
        ) {
            Row(verticalAlignment = Alignment.Vertical.CenterVertically, modifier = GlanceModifier.fillMaxWidth()) {
                ServiceBadge(d.serviceType, 48)
                Spacer(GlanceModifier.width(12.dp))
                Column(modifier = GlanceModifier.defaultWeight()) {
                    Text(
                        title(d),
                        maxLines = 1,
                        style = TextStyle(color = GardenWidgetUi.text, fontWeight = FontWeight.Bold, fontSize = 15.sp),
                    )
                    Text(d.subtitle, maxLines = 1, style = TextStyle(color = GardenWidgetUi.subtext, fontSize = 12.sp))
                }
                Spacer(GlanceModifier.width(8.dp))
                Column(horizontalAlignment = Alignment.Horizontal.End) {
                    Text(small, style = TextStyle(color = GardenWidgetUi.subtext, fontSize = 10.sp))
                    Text(big, style = TextStyle(color = ink, fontWeight = FontWeight.Bold, fontSize = 22.sp))
                }
            }
            Spacer(GlanceModifier.height(12.dp))
            // Barra nativa: ocupa el ancho real del widget (antes 260 dp fijos,
            // que se salían o quedaban cortos al cambiar el tamaño).
            LinearProgressIndicator(
                progress = progress,
                color = ink,
                backgroundColor = GardenWidgetUi.track,
                modifier = GlanceModifier.fillMaxWidth().height(6.dp),
            )
            Spacer(GlanceModifier.height(6.dp))
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                Text(
                    "Empezó a las ${GardenWidgetUi.clock(d.startedAtMs)}",
                    modifier = GlanceModifier.defaultWeight(),
                    style = TextStyle(color = GardenWidgetUi.subtext, fontSize = 11.sp),
                )
                Text(
                    if (d.serviceType == "PASEO") "Ver el mapa ›" else "Ver fotos ›",
                    style = TextStyle(color = GardenWidgetUi.primary, fontWeight = FontWeight.Bold, fontSize = 11.sp),
                )
            }

            // Mini-mapa — solo PASEO. MainActivity.kt deja el bitmap cada ~30 s
            // mientras el paseo está en curso; sin él, la tarjeta ya es útil.
            if (d.serviceType == "PASEO") {
                val map = GardenWidgetData.loadMapSnapshot(context)
                if (map != null) {
                    Spacer(GlanceModifier.height(10.dp))
                    Image(
                        provider = ImageProvider(map),
                        contentDescription = "Ubicación en vivo del paseo",
                        modifier = GlanceModifier.fillMaxWidth().height(92.dp).cornerRadius(16.dp),
                        contentScale = ContentScale.Crop,
                    )
                }
            }
        }
    }

    @Composable
    private fun Completed(d: GardenWidgetData.ActiveService, launch: Intent) {
        val pet = d.petName.ifEmpty { "Tu mascota" }
        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(GardenWidgetUi.surface)
                .cornerRadius(24.dp)
                .padding(16.dp)
                .clickable(actionStartActivity(launch)),
        ) {
            ServiceBadge(d.serviceType, 48)
            Spacer(GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    if (d.role == "CLIENT") "$pet ya volvió" else "Servicio terminado",
                    maxLines = 1,
                    style = TextStyle(color = GardenWidgetUi.text, fontWeight = FontWeight.Bold, fontSize = 15.sp),
                )
                Text(
                    "Toca para ver el resumen",
                    maxLines = 1,
                    style = TextStyle(color = GardenWidgetUi.subtext, fontSize = 12.sp),
                )
            }
            Text("Listo", style = TextStyle(color = GardenWidgetUi.ink(d.serviceType), fontWeight = FontWeight.Bold, fontSize = 13.sp))
        }
    }

    /** Sin servicio en curso: explica qué aparecerá aquí (antes "Sin servicio
     * activo" con un emoji, que parecía un widget roto). */
    @Composable
    private fun Idle(context: Context) {
        val launch = Intent(context, MainActivity::class.java).apply { putExtra("deepLinkRoute", "/marketplace") }
        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(GardenWidgetUi.surface)
                .cornerRadius(24.dp)
                .padding(16.dp)
                .clickable(actionStartActivity(launch)),
        ) {
            ServiceBadge("PASEO", 44)
            Spacer(GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    "Aquí verás a tu mascota en vivo",
                    maxLines = 1,
                    style = TextStyle(color = GardenWidgetUi.text, fontWeight = FontWeight.Bold, fontSize = 14.sp),
                )
                Text(
                    "Cuando empiece un paseo, guardería u hospedaje",
                    maxLines = 1,
                    style = TextStyle(color = GardenWidgetUi.subtext, fontSize = 11.5.sp),
                )
            }
        }
    }
}

/** AppWidgetProvider real — ver res/xml/garden_active_service_widget_info.xml
 * y el <receiver> en AndroidManifest.xml. */
class GardenActiveServiceWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = GardenActiveServiceWidget()
}
