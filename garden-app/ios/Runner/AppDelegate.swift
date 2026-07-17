import Amplify
import AWSCognitoAuthPlugin
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
        _configureAmplify()
        GeneratedPluginRegistrant.register(with: self)
        _registerLiveActivityChannel()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
}
