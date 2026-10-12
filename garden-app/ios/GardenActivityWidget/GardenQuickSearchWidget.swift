import SwiftUI
import WidgetKit

// ── Widget de acceso rápido (pantalla de inicio, sin servicio en curso) ─────
// Equivalente iOS de GardenQuickSearchWidget.kt (Android). Precedencia:
// próxima reserva > resumen del mes > buscar cuidador.
//
// Mismo lenguaje que la app: crema / bosque según el modo del teléfono, los
// íconos propios de cada servicio (sin emojis), tú ("Busca un cuidador";
// antes "Buscá… ¡Seguí así!") y la próxima reserva con día y hora.
//
// Los datos de próxima reserva y del mes llegan por el App Group
// group.com.garden.bolivia (ver Runner.entitlements: falta el paso manual en
// Xcode de agregar la capability a ambos targets). Sin eso el widget muestra
// "Busca un cuidador", que funciona igual.

private let appGroupSuite = "group.com.garden.bolivia"

private struct NextBookingInfo {
    let petName: String
    let serviceType: String
    let startsAt: Date
    let counterpartName: String

    static func load() -> NextBookingInfo? {
        guard let defaults = UserDefaults(suiteName: appGroupSuite),
              defaults.bool(forKey: "nextBookingActive") else { return nil }
        let startsAtMs = defaults.double(forKey: "nextBookingStartsAtMs")
        guard startsAtMs > 0 else { return nil }
        let startsAt = Date(timeIntervalSince1970: startsAtMs / 1000)
        guard startsAt > Date() else { return nil }
        return NextBookingInfo(
            petName: defaults.string(forKey: "nextBookingPetName") ?? "",
            serviceType: defaults.string(forKey: "nextBookingServiceType") ?? "PASEO",
            startsAt: startsAt,
            counterpartName: defaults.string(forKey: "nextBookingCounterpartName") ?? ""
        )
    }

    var style: GardenServiceStyle { GardenServiceStyle(type: serviceType) }
    var title: String { "\(style.label) de \(petName.isEmpty ? "tu mascota" : petName)" }

    /// "Hoy a las 9:00" / "Mañana a las 9:00" / "Sáb 18 a las 9:00" — no se
    /// vence entre refrescos.
    var whenLabel: String {
        let cal = Calendar.current
        let time = DateFormatter()
        time.locale = Locale(identifier: "es_BO")
        time.dateFormat = "H:mm"
        let day: String
        if cal.isDateInToday(startsAt) {
            day = "Hoy"
        } else if cal.isDateInTomorrow(startsAt) {
            day = "Mañana"
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_BO")
            f.dateFormat = "EEE d"
            day = f.string(from: startsAt).replacingOccurrences(of: ".", with: "").capitalized
        }
        return "\(day) a las \(time.string(from: startsAt))"
    }
}

private struct MonthlyStatsInfo {
    let completedThisMonth: Int

    static func load() -> MonthlyStatsInfo? {
        guard let defaults = UserDefaults(suiteName: appGroupSuite),
              defaults.bool(forKey: "monthlyStatsActive") else { return nil }
        let count = defaults.integer(forKey: "monthlyStatsCompletedCount")
        guard count > 0 else { return nil }
        return MonthlyStatsInfo(completedThisMonth: count)
    }
}

private struct QuickSearchEntry: TimelineEntry {
    let date: Date
    let nextBooking: NextBookingInfo?
    let monthlyStats: MonthlyStatsInfo?
}

private struct QuickSearchProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickSearchEntry {
        QuickSearchEntry(date: Date(), nextBooking: nil, monthlyStats: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickSearchEntry) -> Void) {
        completion(QuickSearchEntry(date: Date(), nextBooking: NextBookingInfo.load(), monthlyStats: MonthlyStatsInfo.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickSearchEntry>) -> Void) {
        let entry = QuickSearchEntry(date: Date(), nextBooking: NextBookingInfo.load(), monthlyStats: MonthlyStatsInfo.load())
        // Con reserva: refrescar cuando empiece (y a medianoche cambia "Mañana" → "Hoy").
        let policy: TimelineReloadPolicy
        if let next = entry.nextBooking {
            let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
            policy = .after(min(next.startsAt, midnight))
        } else {
            policy = .never
        }
        completion(Timeline(entries: [entry], policy: policy))
    }
}

// ── Colores según el modo del teléfono ───────────────────────────────────────

private struct Palette {
    let dark: Bool
    var surface: Color { dark ? .gardenForest : Color(red: 250/255, green: 247/255, blue: 242/255) }
    var text: Color { dark ? .gardenTextOnDark : Color(red: 30/255, green: 45/255, blue: 15/255) }
    var sub: Color { dark ? .gardenSubOnDark : Color(red: 92/255, green: 114/255, blue: 56/255) }
    var primary: Color { dark ? Color(red: 163/255, green: 186/255, blue: 98/255) : .gardenOlive }
}

private extension View {
    /// iOS 17+ exige containerBackground: sin él el widget muestra un aviso
    /// de error en vez del contenido.
    @ViewBuilder func gardenWidgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(color, for: .widget)
        } else {
            self.background(color)
        }
    }
}

private struct QuickSearchView: View {
    let entry: QuickSearchEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    private var p: Palette { Palette(dark: scheme == .dark) }
    private var small: Bool { family == .systemSmall }

    var body: some View {
        Group {
            if let next = entry.nextBooking {
                nextBooking(next)
            } else if let stats = entry.monthlyStats {
                monthly(stats)
            } else {
                search
            }
        }
        .padding(small ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .gardenWidgetBackground(p.surface)
    }

    private var serviceRow: some View {
        HStack(spacing: small ? 4 : 6) {
            ForEach(["PASEO", "GUARDERIA", "HOSPEDAJE"], id: \.self) { s in
                GardenServiceBadge(style: GardenServiceStyle(type: s), size: small ? 34 : 40, dark: scheme == .dark)
            }
        }
    }

    // Buscar cuidador
    @ViewBuilder private var search: some View {
        if small {
            VStack(alignment: .leading, spacing: 0) {
                serviceRow
                Spacer(minLength: 6)
                Text("Busca un cuidador")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(p.text)
                    .lineLimit(2)
                Text("Cerca de ti")
                    .font(.system(size: 12))
                    .foregroundColor(p.sub)
            }
            .widgetURL(URL(string: "garden://marketplace"))
        } else {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Busca un cuidador")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(p.text)
                    Text("Verificados y cerca de ti")
                        .font(.system(size: 12))
                        .foregroundColor(p.sub)
                }
                Spacer(minLength: 4)
                serviceRow
            }
            .widgetURL(URL(string: "garden://marketplace"))
        }
    }

    // Próxima reserva
    @ViewBuilder private func nextBooking(_ n: NextBookingInfo) -> some View {
        let ink = n.style.ink(dark: scheme == .dark)
        if small {
            VStack(alignment: .leading, spacing: 0) {
                GardenServiceBadge(style: n.style, size: 40, dark: scheme == .dark)
                Spacer(minLength: 6)
                Text(n.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(p.text)
                    .lineLimit(2)
                Text(n.whenLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .widgetURL(URL(string: "garden://my-bookings-tab"))
        } else {
            HStack(spacing: 12) {
                GardenServiceBadge(style: n.style, size: 48, dark: scheme == .dark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(p.text)
                        .lineLimit(1)
                    Text(n.counterpartName.isEmpty ? n.whenLabel : "\(n.whenLabel) · con \(n.counterpartName)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(p.sub)
            }
            .widgetURL(URL(string: "garden://my-bookings-tab"))
        }
    }

    // Resumen del mes
    private func monthly(_ m: MonthlyStatsInfo) -> some View {
        let unit = m.completedThisMonth == 1 ? "servicio este mes" : "servicios este mes"
        return Group {
            if small {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(m.completedThisMonth)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundColor(p.primary)
                    Text(unit)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(p.text)
                    Spacer(minLength: 4)
                    Text("Reserva el próximo")
                        .font(.system(size: 12))
                        .foregroundColor(p.sub)
                }
            } else {
                HStack(spacing: 14) {
                    Text("\(m.completedThisMonth)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundColor(p.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unit)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(p.text)
                        Text("Toca para reservar el próximo")
                            .font(.system(size: 12))
                            .foregroundColor(p.sub)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(p.sub)
                }
            }
        }
        .widgetURL(URL(string: "garden://marketplace"))
    }
}

struct GardenQuickSearchWidget: Widget {
    let kind: String = "GardenQuickSearchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickSearchProvider()) { entry in
            QuickSearchView(entry: entry)
        }
        .configurationDisplayName("Garden")
        .description("Busca un cuidador o mira tu próxima reserva.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
