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
        /// Snapshot PNG del mini-mapa (idea #1) — solo se llena durante PASEO,
        /// re-enviado cada ~30s desde _updateMapSnapshot en
        /// service_execution_screen.dart. nil mientras no llegó el primero
        /// todavía (arranque del servicio) o para GUARDERIA/HOSPEDAJE (no se
        /// mueven, no hay nada que mostrar). Data es Codable nativo — se
        /// serializa como base64 sin código extra.
        var mapSnapshotData: Data?

        private enum CodingKeys: String, CodingKey {
            case startedAt, totalPaidSeconds, status, mapSnapshotData
        }

        init(startedAt: Date, totalPaidSeconds: Int, status: String, mapSnapshotData: Data? = nil) {
            self.startedAt = startedAt
            self.totalPaidSeconds = totalPaidSeconds
            self.status = status
            self.mapSnapshotData = mapSnapshotData
        }

        // Defensive decode: if a previously-running Activity (started before an
        // app update shipped these fields) somehow reaches this decoder with an
        // older payload shape, fall back to sane defaults instead of crashing.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
            self.totalPaidSeconds = try c.decodeIfPresent(Int.self, forKey: .totalPaidSeconds) ?? 3600
            self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "IN_PROGRESS"
            self.mapSnapshotData = try c.decodeIfPresent(Data.self, forKey: .mapSnapshotData)
        }
    }

    var petName: String
    var caregiverName: String
    var ownerName: String
    var serviceType: String      // "PASEO" | "HOSPEDAJE" | "GUARDERIA"
    var role: String             // "CLIENT" | "CAREGIVER"
    var bookingId: String
}
