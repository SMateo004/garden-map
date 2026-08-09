package com.garden.bolivia

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Base64
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.glance.appwidget.updateAll
import com.garden.bolivia.widget.GardenActiveServiceWidget
import com.garden.bolivia.widget.GardenWidgetData
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// face_liveness_detector (AWS Amplify Face Liveness) requiere que la Activity
// host sea FlutterFragmentActivity, no FlutterActivity — el flujo de cámara
// nativo de Amplify se monta como Fragment/ComponentActivity. Con
// FlutterActivity el intento de abrir la verificación de identidad revienta
// el proceso nativo por debajo de Flutter (la app "se cierra sola", sin
// ningún error de Dart visible).
class MainActivity : FlutterFragmentActivity() {

    private val ICON_SWITCHER_CHANNEL = "com.gardenbo.app/icon_switcher"
    private val WIDGET_CHANNEL = "com.gardenbo.app/android_widget"
    private val DEEP_LINK_CHANNEL = "com.gardenbo.app/deep_link"

    // Corutinas para actualizar el estado del widget (Glance es suspend) sin
    // bloquear el hilo del MethodChannel.
    private val widgetScope = CoroutineScope(Dispatchers.Main)

    // Ruta pendiente capturada de un Intent (toque en el widget) antes de que
    // Dart esté listo para recibirla — se manda apenas Dart la pide
    // (getInitialRoute) o, si la app ya estaba corriendo, se empuja directo
    // (onNewIntent → onDeepLink).
    private var pendingDeepLinkRoute: String? = null
    private var pendingDeepLinkRole: String? = null
    private var deepLinkChannel: MethodChannel? = null

    // Debe coincidir 1:1 con los activity-alias declarados en AndroidManifest.xml.
    // "variantB" ahora mismo es un PLACEHOLDER (mismo arte que el ícono default,
    // ver ic_launcher_variant_b.xml) — solo prueba que el mecanismo funciona de
    // punta a punta. Agregar una variante real de temporada requiere: 1) diseñar
    // el arte, 2) agregar su mipmap + activity-alias en el manifest, 3) agregarla
    // acá, 4) publicar un AAB nuevo en Play Store. No hay forma de saltarse el
    // build nuevo — Android no permite instalar un ícono de app en runtime.
    private val aliasForVariant = mapOf(
        "default" to ".IconDefault",
        "variantB" to ".IconVariantB",
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureDeepLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureDeepLink(intent)
        // App ya corriendo (launchMode singleTop) — empujar directo a Dart en
        // vez de esperar a que alguien llame getInitialRoute.
        val route = pendingDeepLinkRoute
        if (route != null) {
            pendingDeepLinkRoute = null
            val args = mapOf("route" to route, "role" to pendingDeepLinkRole)
            pendingDeepLinkRole = null
            deepLinkChannel?.invokeMethod("onDeepLink", args)
        }
    }

    private fun captureDeepLink(intent: Intent) {
        val route = intent.getStringExtra("deepLinkRoute") ?: return
        pendingDeepLinkRoute = route
        pendingDeepLinkRole = intent.getStringExtra("deepLinkRole")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ICON_SWITCHER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> {
                        val variant = call.argument<String>("variant") ?: "default"
                        val ok = setActiveIconAlias(variant)
                        if (ok) result.success(true)
                        else result.error("UNKNOWN_VARIANT", "No hay activity-alias para '$variant'", null)
                    }
                    "getCurrentIcon" -> result.success(getActiveIconVariant())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateActiveService" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args == null) {
                            result.error("ARGS", "Argumentos inválidos", null)
                            return@setMethodCallHandler
                        }
                        GardenWidgetData.save(
                            applicationContext,
                            GardenWidgetData.ActiveService(
                                petName = args["petName"] as? String ?: "",
                                subtitle = args["subtitle"] as? String ?: "",
                                serviceType = args["serviceType"] as? String ?: "PASEO",
                                status = args["status"] as? String ?: "IN_PROGRESS",
                                startedAtMs = (args["startedAtMs"] as? Number)?.toLong() ?: 0L,
                                totalPaidSeconds = (args["totalPaidSeconds"] as? Number)?.toInt() ?: 3600,
                                bookingId = args["bookingId"] as? String ?: "",
                                role = args["role"] as? String ?: "CLIENT",
                            ),
                        )
                        widgetScope.launch { GardenActiveServiceWidget().updateAll(applicationContext) }
                        result.success(null)
                    }
                    "endActiveService" -> {
                        GardenWidgetData.clear(applicationContext)
                        widgetScope.launch { GardenActiveServiceWidget().updateAll(applicationContext) }
                        result.success(null)
                    }
                    "updateMapSnapshot" -> {
                        val b64 = call.argument<String>("mapSnapshotBase64")
                        if (b64 == null) {
                            result.error("ARGS", "Falta mapSnapshotBase64", null)
                            return@setMethodCallHandler
                        }
                        widgetScope.launch {
                            try {
                                val bytes = withContext(Dispatchers.IO) { Base64.decode(b64, Base64.DEFAULT) }
                                withContext(Dispatchers.IO) { GardenWidgetData.saveMapSnapshot(applicationContext, bytes) }
                                GardenActiveServiceWidget().updateAll(applicationContext)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("MAP_SNAPSHOT", "No se pudo guardar el snapshot", e.message)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        val dlChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEEP_LINK_CHANNEL)
        deepLinkChannel = dlChannel
        dlChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialRoute" -> {
                    val route = pendingDeepLinkRoute
                    val role = pendingDeepLinkRole
                    pendingDeepLinkRoute = null
                    pendingDeepLinkRole = null
                    if (route != null) {
                        result.success(mapOf("route" to route, "role" to role))
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Activa el activity-alias de [variant] y desactiva todos los demás.
     * IMPORTANTE: exactamente un alias debe quedar enabled a la vez — dejar más de
     * uno (o ninguno) enabled hace que el launcher del usuario muestre íconos
     * duplicados o ninguno. Algunos launchers no refrescan el ícono hasta que el
     * usuario reabre la app o reinicia el launcher — no es instantáneo garantizado
     * como en iOS.
     */
    private fun setActiveIconAlias(variant: String): Boolean {
        val targetAlias = aliasForVariant[variant] ?: return false
        val pm = packageManager
        for ((v, alias) in aliasForVariant) {
            val state = if (alias == targetAlias) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            pm.setComponentEnabledSetting(
                ComponentName(packageName, "$packageName$alias"),
                state,
                PackageManager.DONT_KILL_APP,
            )
        }
        return true
    }

    private fun getActiveIconVariant(): String {
        val pm = packageManager
        for ((variant, alias) in aliasForVariant) {
            val state = pm.getComponentEnabledSetting(ComponentName(packageName, "$packageName$alias"))
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && variant == "default")
            ) {
                return variant
            }
        }
        return "default"
    }
}
