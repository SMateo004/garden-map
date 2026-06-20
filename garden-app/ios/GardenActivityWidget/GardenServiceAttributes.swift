import ActivityKit
import Foundation

// ⚠️ Keep in sync with ios/Runner/GardenServiceAttributes.swift

@available(iOS 16.2, *)
struct GardenServiceAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        var timerValue: String   // "23:14"
        var status: String       // "IN_PROGRESS" | "COMPLETED"
    }

    var petName: String
    var caregiverName: String
    var ownerName: String
    var serviceType: String      // "PASEO" | "HOSPEDAJE"
    var role: String             // "CLIENT" | "CAREGIVER"
    var bookingId: String
}
