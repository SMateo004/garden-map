import ActivityKit
import Foundation

// ⚠️ Keep in sync with ios/Runner/GardenServiceAttributes.swift

@available(iOS 16.2, *)
struct GardenServiceAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        /// When the service started — the widget computes elapsed time locally
        /// (via TimelineView / Text(timerInterval:)) from this instead of
        /// requiring a native update every second. Keeps us well within
        /// ActivityKit's update budget.
        var startedAt: Date
        /// Total paid duration in seconds — the "goal" the progress bar/emoji
        /// walks towards. Original booked duration + any approved & paid
        /// extension. Re-sent (rare, low-frequency update) whenever an
        /// extension is confirmed so the goal moves "en seguida".
        var totalPaidSeconds: Int
        /// "IN_PROGRESS" | "COMPLETED"
        var status: String

        private enum CodingKeys: String, CodingKey {
            case startedAt, totalPaidSeconds, status
        }

        init(startedAt: Date, totalPaidSeconds: Int, status: String) {
            self.startedAt = startedAt
            self.totalPaidSeconds = totalPaidSeconds
            self.status = status
        }

        // Defensive decode: if a previously-running Activity (started before an
        // app update shipped these fields) somehow reaches this decoder with an
        // older payload shape, fall back to sane defaults instead of crashing.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
            self.totalPaidSeconds = try c.decodeIfPresent(Int.self, forKey: .totalPaidSeconds) ?? 3600
            self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "IN_PROGRESS"
        }
    }

    var petName: String
    var caregiverName: String
    var ownerName: String
    var serviceType: String      // "PASEO" | "HOSPEDAJE" | "GUARDERIA"
    var role: String             // "CLIENT" | "CAREGIVER"
    var bookingId: String
}
