package com.garden.bolivia.widget

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
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
import androidx.glance.unit.ColorProvider
import com.garden.bolivia.MainActivity
import java.util.concurrent.TimeUnit

// ── Marca Garden — mismos tonos que el Live Activity de iOS ────────────────
private val GardenSurface = Color(0xFF1C1C1C)
private val GardenGreen = Color(0xFF778C43)
private val GardenGreenDim = Color(0x33778C43)
private val GardenTrack = Color(0x24FFFFFF)
private val GardenOvertime = Color(0xFFE29A3E)
private val TextSecondary = Color(0xFFA6A6A6)

/**
 * Widget del home screen para el servicio activo (PASEO/GUARDERÍA/HOSPEDAJE)
 * — equivalente Android del Live Activity de iOS (ver
 * ios/GardenActivityWidget/GardenActivityWidget.swift, mismo lenguaje visual:
 * tarjeta oscura, círculo con emoji, cronómetro, barra de progreso).
 *
 * A diferencia de iOS (ActivityKit empuja actualizaciones nativas cada pocos
 * segundos), Android no tiene un mecanismo de "reloj vivo" para widgets — el
 * texto del tiempo transcurrido se recalcula cada vez que Dart llama al
 * MethodChannel `com.gardenbo.app/android_widget` (cada ~10s mientras la
 * pantalla de servicio está corriendo, ver garden_live_activity.dart), no en
 * tiempo real como en el lock screen de iOS.
 */
class GardenActiveServiceWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            Content(context)
        }
    }

    @Composable
    private fun Content(context: Context) {
        val data = GardenWidgetData.load(context)
        if (data == null) {
            EmptyState()
            return
        }

        val bookingId = data.bookingId
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("deepLinkRoute", "/service/$bookingId")
            putExtra("deepLinkRole", data.role)
        }

        val elapsedMs = (System.currentTimeMillis() - data.startedAtMs).coerceAtLeast(0)
        val elapsedSeconds = elapsedMs / 1000
        val progress = if (data.totalPaidSeconds > 0) {
            (elapsedSeconds.toFloat() / data.totalPaidSeconds).coerceIn(0f, 1f)
        } else 0f
        val isOvertime = elapsedSeconds > data.totalPaidSeconds
        val isCompleted = data.status == "COMPLETED"

        val emoji = when (data.serviceType) {
            "PASEO", "GUARDERIA" -> "🐕"
            else -> "😴" // HOSPEDAJE
        }
        val title = if (isCompleted) "Servicio completado 🎉" else data.petName

        Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(GardenSurface)
                .cornerRadius(20.dp)
                .padding(16.dp)
                .clickable(actionStartActivity(launchIntent))
        ) {
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                Row(
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                    modifier = GlanceModifier.fillMaxWidth(),
                ) {
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = GlanceModifier
                            .width(48.dp)
                            .height(48.dp)
                            .background(GardenGreenDim)
                            .cornerRadius(24.dp),
                    ) {
                        Text(emoji, style = TextStyle(fontSize = 22.sp))
                    }
                    Spacer(modifier = GlanceModifier.width(12.dp))
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        Text(
                            title,
                            maxLines = 1,
                            style = TextStyle(color = ColorProvider(Color.White), fontWeight = FontWeight.Bold, fontSize = 14.sp),
                        )
                        Text(
                            data.subtitle,
                            maxLines = 1,
                            style = TextStyle(color = ColorProvider(TextSecondary), fontSize = 12.sp),
                        )
                    }
                    if (!isCompleted) {
                        Column(horizontalAlignment = Alignment.Horizontal.End) {
                            Text(
                                formatElapsed(elapsedSeconds),
                                style = TextStyle(
                                    color = ColorProvider(if (isOvertime) GardenOvertime else GardenGreen),
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 18.sp,
                                ),
                            )
                            Text("transcurrido", style = TextStyle(color = ColorProvider(TextSecondary), fontSize = 10.sp))
                        }
                    } else {
                        Text("✅", style = TextStyle(fontSize = 24.sp))
                    }
                }

                if (!isCompleted) {
                    Spacer(modifier = GlanceModifier.height(12.dp))
                    ProgressTrack(progress = progress, overtime = isOvertime)
                }

                // Mini-mapa — solo PASEO (los otros servicios no se mueven).
                // El bitmap lo deja MainActivity.kt (handler "updateMapSnapshot")
                // cada ~30s mientras el paseo está en curso; si todavía no llegó
                // ninguno (primeros segundos del servicio) se omite en silencio,
                // sin placeholder — el resto de la tarjeta ya es útil sin él.
                if (!isCompleted && data.serviceType == "PASEO") {
                    val mapBitmap = GardenWidgetData.loadMapSnapshot(context)
                    if (mapBitmap != null) {
                        Spacer(modifier = GlanceModifier.height(10.dp))
                        Image(
                            provider = ImageProvider(mapBitmap),
                            contentDescription = "Ubicación en vivo del paseo",
                            modifier = GlanceModifier
                                .fillMaxWidth()
                                .height(90.dp)
                                .cornerRadius(14.dp),
                            contentScale = ContentScale.Crop,
                        )
                    }
                }
            }
        }
    }

    // Ancho fijo asumido para la tarjeta (widget mediano/grande típico, menos
    // el padding de 16dp de cada lado) — Glance no soporta un fillMaxWidth
    // fraccional como Compose normal, así que el relleno se calcula en dp
    // directamente. No es exacto en todos los tamaños de celda del launcher,
    // pero da una barra de progreso correcta y liviana sin depender de una
    // API que no existe en Glance.
    private val trackWidth = 260.dp

    @Composable
    private fun ProgressTrack(progress: Float, overtime: Boolean) {
        val filledWidth = trackWidth * progress.coerceIn(0.04f, 1f)
        Box(
            modifier = GlanceModifier
                .width(trackWidth)
                .height(6.dp)
                .background(GardenTrack)
                .cornerRadius(3.dp)
        ) {
            Box(
                modifier = GlanceModifier
                    .width(filledWidth)
                    .height(6.dp)
                    .background(if (overtime) GardenOvertime else GardenGreen)
                    .cornerRadius(3.dp)
            ) {}
        }
    }

    @Composable
    private fun EmptyState() {
        // Sin servicio activo — el widget queda casi invisible en vez de mostrar
        // una tarjeta vacía confusa. Se reemplaza por contenido real apenas
        // arranca el próximo servicio (GardenLiveActivity.startActivity).
        Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(GardenSurface)
                .cornerRadius(20.dp)
                .padding(16.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.Horizontal.CenterHorizontally) {
                Text("🐾", style = TextStyle(fontSize = 22.sp))
                Spacer(modifier = GlanceModifier.height(4.dp))
                Text(
                    "Sin servicio activo",
                    style = TextStyle(color = ColorProvider(TextSecondary), fontSize = 12.sp),
                )
            }
        }
    }

    private fun formatElapsed(totalSeconds: Long): String {
        val h = TimeUnit.SECONDS.toHours(totalSeconds)
        val m = TimeUnit.SECONDS.toMinutes(totalSeconds) % 60
        return if (h > 0) "${h}h ${m}m" else "$m min"
    }
}

/** AppWidgetProvider real que el sistema Android referencia — ver
 * res/xml/garden_active_service_widget_info.xml y el <receiver> en
 * AndroidManifest.xml. Todo el contenido vive en [GardenActiveServiceWidget]. */
class GardenActiveServiceWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = GardenActiveServiceWidget()
}
