import ActivityKit
import Foundation

// Shared Live-Activity attributes.
// ⚠️ This struct is duplicated in the GardenActivityWidget extension target.
// Keep both in sync if you add fields.

@available(iOS 16.2, *)
struct GardenServiceAttributes: ActivityAttributes {

    // MARK: – Dynamic state (updated by the app; low-frequency)
    public struct ContentState: Codable, Hashable {
        /// When the service started — the widget computes elapsed time locally
        /// from this (TimelineView / Text(timerInterval:)) instead of requiring
        /// a native update every second, keeping us within ActivityKit's
        /// update budget.
        var startedAt: Date
        /// Total paid duration in seconds — original booked duration + any
        /// approved & paid extension (PASEO/GUARDERIA: minutes; HOSPEDAJE:
        /// nights). Re-sent whenever an extension is confirmed.
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

        // Defensive decode for Activities already running when a new app
        // version ships this struct — avoids a crash if an old payload shape
        // is ever handed to this decoder.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
            self.totalPaidSeconds = try c.decodeIfPresent(Int.self, forKey: .totalPaidSeconds) ?? 3600
            self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "IN_PROGRESS"
            self.mapSnapshotData = try c.decodeIfPresent(Data.self, forKey: .mapSnapshotData)
        }
    }

    // MARK: – Static metadata (set once at start)
    var petName: String
    var caregiverName: String
    var ownerName: String
    /// "PASEO" | "HOSPEDAJE" | "GUARDERIA"
    var serviceType: String
    /// "CLIENT" | "CAREGIVER"
    var role: String
    var bookingId: String
}
