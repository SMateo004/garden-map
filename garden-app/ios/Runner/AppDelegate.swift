import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    // Strong ref — ARC would release a local without this.
    private var _liveActivityHandler: AnyObject?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        _registerLiveActivityChannel()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
}
