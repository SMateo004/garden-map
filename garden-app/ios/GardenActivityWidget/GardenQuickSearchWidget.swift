import SwiftUI
import WidgetKit

// ── Widget de home screen "acceso rápido" (sin servicio activo) ────────────
// Equivalente iOS del widget GardenQuickSearchWidget de Android (ver
// android/app/src/main/kotlin/com/garden/bolivia/widget/GardenQuickSearchWidget.kt)
// — mismo espíritu que el widget "¿A dónde vamos?" de Uber: una acción clara,
// siempre visible, un toque directo al marketplace sin pasar por el resto de
// la app. A diferencia de GardenServiceLiveActivityWidget (arriba en este
// mismo archivo/target), esto NO es un Live Activity — es un widget estático
// normal de WidgetKit, vive en el home screen todo el tiempo, no solo
// mientras hay un servicio en curso.
//
// Idea #3: si hay una reserva CONFIRMED próxima, muestra un countdown en vez
// del genérico "buscá un cuidador". A diferencia de la app y de Android, este
// widget corre en su PROPIO proceso — la única forma real de que reciba datos
// de la app es un App Group compartido (ver Runner.entitlements /
// GardenActivityWidget.entitlements, y el paso manual de Xcode documentado
// ahí, todavía pendiente). Sin ese paso, UserDefaults(suiteName:) devuelve
// nil y este widget simplemente muestra el contenido genérico de siempre —
// no rompe nada, solo no tiene el dato nuevo hasta que se habilite.

private let appGroupSuite = "group.com.garden.bolivia"

private struct NextBookingInfo {
    let petName: String
    let serviceType: String
    let startsAt: Date
    let counterpartName: String

    /// nil si no hay ninguna reserva próxima guardada, si ya pasó, o si el
    /// App Group todavía no está habilitado (ver comentario de arriba).
    static func load() -> NextBookingInfo? {
        guard let defaults = UserDefaults(suiteName: appGroupSuite),
              defaults.bool(forKey: "nextBookingActive") else { return nil }
        let startsAtMs = defaults.double(forKey: "nextBookingStartsAtMs")
        guard startsAtMs > 0 else { return nil }
        let startsAt = Date(timeIntervalSince1970: startsAtMs / 1000)
        guard startsAt > Date() else { return nil } // ya pasó
        return NextBookingInfo(
            petName: defaults.string(forKey: "nextBookingPetName") ?? "",
            serviceType: defaults.string(forKey: "nextBookingServiceType") ?? "PASEO",
            startsAt: startsAt,
            counterpartName: defaults.string(forKey: "nextBookingCounterpartName") ?? ""
        )
    }

    var emoji: String { serviceType == "HOSPEDAJE" ? "😴" : "🐕" }
    var serviceLabel: String {
        switch serviceType {
        case "PASEO": return "Paseo"
        case "GUARDERIA": return "Guardería"
        default: return "Hospedaje"
        }
    }
}

private struct QuickSearchEntry: TimelineEntry {
    let date: Date
    let nextBooking: NextBookingInfo?
}

private struct QuickSearchProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickSearchEntry {
        QuickSearchEntry(date: Date(), nextBooking: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickSearchEntry) -> Void) {
        completion(QuickSearchEntry(date: Date(), nextBooking: NextBookingInfo.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickSearchEntry>) -> Void) {
        let entry = QuickSearchEntry(date: Date(), nextBooking: NextBookingInfo.load())
        // Con countdown: refrescar cuando la reserva arranque (el countdown
        // deja de tener sentido) — WidgetKit igual la puede refrescar antes
        // por su cuenta (budget del sistema) o cuando reloadTimelines() se
        // llama desde la app al llegar un dato nuevo. Sin countdown (o si
        // el App Group no está habilitado todavía), .never — no hay nada
        // que cambie solo.
        let policy: TimelineReloadPolicy = entry.nextBooking != nil
            ? .after(entry.nextBooking!.startsAt)
            : .never
        completion(Timeline(entries: [entry], policy: policy))
    }
}

private struct QuickSearchView: View {
    let entry: QuickSearchEntry

    var body: some View {
        if let next = entry.nextBooking {
            nextBookingBody(next)
        } else {
            searchPromptBody
        }
    }

    private var searchPromptBody: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 185/255, green: 210/255, blue: 138/255).opacity(0.2))
                    .frame(width: 44, height: 44)
                Text("🐾")
                    .font(.system(size: 20))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Buscá un cuidador")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Paseo, guardería u hospedaje")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 185/255, green: 210/255, blue: 138/255))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color(red: 30/255, green: 45/255, blue: 15/255)) // forest, tono marca
        .widgetURL(URL(string: "garden://marketplace"))
    }

    private func nextBookingBody(_ next: NextBookingInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 185/255, green: 210/255, blue: 138/255).opacity(0.2))
                    .frame(width: 44, height: 44)
                Text(next.emoji)
                    .font(.system(size: 20))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(next.serviceLabel) de \(next.petName.isEmpty ? "tu mascota" : next.petName)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(timerInterval: Date()...next.startsAt, countsDown: true, showsHours: true)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(red: 185/255, green: 210/255, blue: 138/255))
                    if !next.counterpartName.isEmpty {
                        Text("· \(next.counterpartName)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 185/255, green: 210/255, blue: 138/255))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color(red: 30/255, green: 45/255, blue: 15/255)) // forest, tono marca
        // /my-bookings-tab, no una ruta de detalle por-reserva — mismo criterio
        // que la versión Android (ver GardenQuickSearchWidget.kt).
        .widgetURL(URL(string: "garden://my-bookings-tab"))
    }
}

struct GardenQuickSearchWidget: Widget {
    let kind: String = "GardenQuickSearchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickSearchProvider()) { entry in
            QuickSearchView(entry: entry)
        }
        .configurationDisplayName("Buscar cuidador")
        .description("Acceso directo al marketplace de Garden desde tu pantalla de inicio.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
