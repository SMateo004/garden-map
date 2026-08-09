package com.garden.bolivia.widget

import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.action.actionStartActivity
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
 * sola acción clara, siempre visible, cero fricción. Reemplaza abrir la app
 * y navegar hasta el buscador con un solo toque directo al marketplace.
 *
 * A diferencia de [GardenActiveServiceWidget], este es contenido estático —
 * no necesita ningún dato de [GardenWidgetData] ni refresco periódico.
 */
class GardenQuickSearchWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: android.content.Context, id: GlanceId) {
        provideContent { Content() }
    }

    @Composable
    private fun Content() {
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
}

/** AppWidgetProvider real — ver res/xml/garden_quick_search_widget_info.xml y
 * el <receiver> en AndroidManifest.xml. */
class GardenQuickSearchWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = GardenQuickSearchWidget()
}
