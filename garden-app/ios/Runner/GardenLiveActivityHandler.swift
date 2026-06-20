import ActivityKit
import Flutter
import Foundation

/// Handles MethodChannel calls from Flutter to start / update / end Live Activities.
/// Only instantiated on iOS 16.2+.
@available(iOS 16.2, *)
final class GardenLiveActivityHandler {

    // Keeps strong references so updates work across multiple calls.
    private var activities: [String: Activity<GardenServiceAttributes>] = [:]

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startActivity":  startActivity(call: call, result: result)
        case "updateActivity": updateActivity(call: call, result: result)
        case "endActivity":    endActivity(call: call, result: result)
        default:               result(FlutterMethodNotImplemented)
        }
    }

    // MARK: – Start

    private func startActivity(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "ARGS", message: "Invalid arguments", details: nil))
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            result(FlutterError(code: "DISABLED", message: "Live Activities disabled by user", details: nil))
            return
        }

        let attributes = GardenServiceAttributes(
            petName:       args["petName"]       as? String ?? "",
            caregiverName: args["caregiverName"] as? String ?? "",
            ownerName:     args["ownerName"]     as? String ?? "",
            serviceType:   args["serviceType"]   as? String ?? "PASEO",
            role:          args["role"]          as? String ?? "CLIENT",
            bookingId:     args["bookingId"]     as? String ?? ""
        )
        let initialState = GardenServiceAttributes.ContentState(
            timerValue: args["timerValue"] as? String ?? "00:00",
            status: "IN_PROGRESS"
        )

        do {
            let activity = try Activity<GardenServiceAttributes>.request(
                attributes: attributes,
                contentState: initialState,
                pushType: nil
            )
            activities[activity.id] = activity
            result(activity.id)
        } catch {
            result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: – Update

    private func updateActivity(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String,
              let activity = activities[id] else {
            result(nil)
            return
        }
        let newState = GardenServiceAttributes.ContentState(
            timerValue: args["timerValue"] as? String ?? "00:00",
            status: "IN_PROGRESS"
        )
        Task {
            await activity.update(using: newState)
        }
        result(nil)
    }

    // MARK: – End

    private func endActivity(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String,
              let activity = activities[id] else {
            result(nil)
            return
        }
        let finalState = GardenServiceAttributes.ContentState(
            timerValue: activity.contentState.timerValue,
            status: "COMPLETED"
        )
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 10)   // keeps on screen 10 s then auto-dismisses
            )
            self.activities.removeValue(forKey: id)
        }
        result(nil)
    }
}
