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

private struct QuickSearchEntry: TimelineEntry {
    let date: Date
}

private struct QuickSearchProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickSearchEntry {
        QuickSearchEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickSearchEntry) -> Void) {
        completion(QuickSearchEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickSearchEntry>) -> Void) {
        // Contenido 100% estático — no hace falta refrescar nunca solo.
        completion(Timeline(entries: [QuickSearchEntry(date: Date())], policy: .never))
    }
}

private struct QuickSearchView: View {
    var body: some View {
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
}

struct GardenQuickSearchWidget: Widget {
    let kind: String = "GardenQuickSearchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickSearchProvider()) { _ in
            QuickSearchView()
        }
        .configurationDisplayName("Buscar cuidador")
        .description("Acceso directo al marketplace de Garden desde tu pantalla de inicio.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
