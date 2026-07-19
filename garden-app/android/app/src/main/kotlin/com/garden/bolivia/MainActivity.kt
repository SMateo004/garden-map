package com.garden.bolivia

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// face_liveness_detector (AWS Amplify Face Liveness) requiere que la Activity
// host sea FlutterFragmentActivity, no FlutterActivity — el flujo de cámara
// nativo de Amplify se monta como Fragment/ComponentActivity. Con
// FlutterActivity el intento de abrir la verificación de identidad revienta
// el proceso nativo por debajo de Flutter (la app "se cierra sola", sin
// ningún error de Dart visible).
class MainActivity : FlutterFragmentActivity() {

    private val ICON_SWITCHER_CHANNEL = "com.gardenbo.app/icon_switcher"

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
