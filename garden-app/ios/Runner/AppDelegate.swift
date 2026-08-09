import Amplify
import AWSCognitoAuthPlugin
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    // Strong ref — ARC would release a local without this.
    private var _liveActivityHandler: AnyObject?

    private var _deepLinkChannel: FlutterMethodChannel?
    // Ruta capturada de un toque en el Live Activity (garden://service/<id>)
    // antes de que Dart esté listo para pedirla — mismo patrón que
    // MainActivity.kt del lado Android (pendingDeepLinkRoute).
    private var _pendingDeepLinkRoute: String?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        _configureAmplify()
        GeneratedPluginRegistrant.register(with: self)
        _registerLiveActivityChannel()
        _registerIconSwitcherChannel()
        _registerDeepLinkChannel()
        // Cold start: la app se abrió directo desde el toque en el widget.
        if let url = launchOptions?[.url] as? URL {
            _pendingDeepLinkRoute = _routeFromDeepLinkURL(url)
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // App ya corriendo (warm start) — este es el callback que iOS invoca
    // cuando se toca un garden:// mientras Garden ya está en memoria.
    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if let route = _routeFromDeepLinkURL(url) {
            _deepLinkChannel?.invokeMethod("onDeepLink", arguments: ["route": route, "role": NSNull()])
            return true
        }
        return false
    }

    /// garden://service/<bookingId> → "/service/<bookingId>" (mismo formato
    /// de ruta que usa deep_link_service.dart del lado Dart, compartido con
    /// el widget de Android). Devuelve nil para cualquier otro host/esquema.
    private func _routeFromDeepLinkURL(_ url: URL) -> String? {
        guard url.scheme == "garden" else { return nil }
        let path = "/\(url.host ?? "")\(url.path)"
        return path == "/" ? nil : path
    }

    private func _registerDeepLinkChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else { return }
        let channel = FlutterMethodChannel(
            name: "com.gardenbo.app/deep_link",
            binaryMessenger: controller.binaryMessenger
        )
        _deepLinkChannel = channel
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "getInitialRoute":
                guard let route = self?._pendingDeepLinkRoute else {
                    result(nil)
                    return
                }
                self?._pendingDeepLinkRoute = nil
                result(["route": route, "role": NSNull()])
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // Required by amplify-ui-swift-liveness (FaceLivenessDetectorView) to obtain
    // Cognito credentials for the Rekognition liveness session — without this,
    // AuthCategory.swift crashes with "Authentication category is not configured"
    // the instant the liveness screen opens.
    private func _configureAmplify() {
        do {
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.configure()
        } catch {
            print("Failed to configure Amplify: \(error)")
        }
    }

    private func _registerLiveActivityChannel() {
        guard #available(iOS 16.2, *) else { return }

        let handler = GardenLiveActivityHandler()
        _liveActivityHandler = handler

        guard let controller = window?.rootViewController as? FlutterViewController else { return }
        let channel = FlutterMethodChannel(
            name: "com.gardenbo.app/live_activity",
            binaryMessenger: controller.binaryMessenger
        )
        channel.setMethodCallHandler { [weak handler] call, result in
            handler?.handle(call, result: result)
        }
    }

    // Icono estacional en runtime — API real de iOS: UIApplication.setAlternateIconName()
    // SOLO puede alternar entre los sets de icono ("AppIcon", "AppIcon-VariantB", ...)
    // que ya están declarados en Info.plist (CFBundleIcons/CFBundleAlternateIcons) y
    // empaquetados en ESTE build. No existe una API para instalar un icono nuevo en
    // runtime — cualquier variante nueva requiere un build nuevo + revisión de tienda.
    //
    // Además, dos límites reales de la API (no de este código):
    //  - Cambiar el icono muestra al usuario un diálogo de confirmación del sistema
    //    ("¿Cambiar a...?") — no es silencioso.
    //  - setAlternateIconName solo funciona con la app en foreground; si se llama
    //    en background falla silenciosamente. Por eso el chequeo se hace al abrir
    //    la app (ver icon_schedule_service.dart), no en background.
    private func _registerIconSwitcherChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else { return }
        let channel = FlutterMethodChannel(
            name: "com.gardenbo.app/icon_switcher",
            binaryMessenger: controller.binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "setIcon":
                guard UIApplication.shared.supportsAlternateIcons else {
                    result(FlutterError(code: "UNSUPPORTED", message: "Alternate icons not supported", details: nil))
                    return
                }
                let args = call.arguments as? [String: Any]
                // variant == "default" (o nil) vuelve al icono primario — Apple requiere pasar nil.
                let variant = args?["variant"] as? String
                let iconName = (variant == nil || variant == "default") ? nil : variant
                UIApplication.shared.setAlternateIconName(iconName) { error in
                    if let error = error {
                        result(FlutterError(code: "SET_ICON_FAILED", message: error.localizedDescription, details: nil))
                    } else {
                        result(true)
                    }
                }
            case "getCurrentIcon":
                result(UIApplication.shared.alternateIconName ?? "default")
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
