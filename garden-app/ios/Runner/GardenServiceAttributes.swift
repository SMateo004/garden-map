import ActivityKit
import Foundation

// Shared Live-Activity attributes.
// ⚠️ This struct is duplicated in the GardenActivityWidget extension target.
// Keep both in sync if you add fields.

@available(iOS 16.2, *)
struct GardenServiceAttributes: ActivityAttributes {

    // MARK: – Dynamic state (updated by the app every ~10 s)
    public struct ContentState: Codable, Hashable {
        /// Formatted elapsed time, e.g. "23:14" or "1:02:45"
        var timerValue: String
        /// "IN_PROGRESS" | "COMPLETED"
        var status: String
    }

    // MARK: – Static metadata (set once at start)
    var petName: String
    var caregiverName: String
    var ownerName: String
    /// "PASEO" | "HOSPEDAJE"
    var serviceType: String
    /// "CLIENT" | "CAREGIVER"
    var role: String
    var bookingId: String
}
