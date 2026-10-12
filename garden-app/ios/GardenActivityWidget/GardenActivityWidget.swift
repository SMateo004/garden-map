import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

// ── Lenguaje visual ───────────────────────────────────────────────────────────
// El mismo de la app (lib/theme/garden_theme.dart, lib/design/garden_service.dart):
// bosque profundo de fondo en la pantalla de bloqueo (se lee sobre cualquier
// fondo de pantalla), cada servicio con su ícono propio (exportado de
// GardenServiceIcon a Assets.xcassets: GardenSvcPaseo/Guarderia/Hospedaje) y
// su color. Antes: gris #1C1C1C y emojis (🐕 para paseo Y guardería, 😴,
// 🚶‍♂️🐕 caminando sobre la barra, "Servicio completado 🎉").

extension Color {
    static let gardenForest = Color(red: 22/255, green: 38/255, blue: 16/255)      // darkSurface
    static let gardenForestDeep = Color(red: 13/255, green: 26/255, blue: 7/255)   // darkBackground
    static let gardenTextOnDark = Color(red: 240/255, green: 247/255, blue: 232/255)
    static let gardenSubOnDark = Color(red: 169/255, green: 196/255, blue: 138/255)
    static let gardenOlive = Color(red: 119/255, green: 140/255, blue: 67/255)
    static let gardenAmber = Color(red: 255/255, green: 194/255, blue: 77/255)
}

/// Identidad de cada servicio (ícono, color, nombres) — una sola fuente para
/// la Actividad en vivo y el widget de acceso rápido.
struct GardenServiceStyle {
    let type: String

    var assetName: String {
        switch type {
        case "GUARDERIA": return "GardenSvcGuarderia"
        case "HOSPEDAJE": return "GardenSvcHospedaje"
        default: return "GardenSvcPaseo"
        }
    }

    var label: String {
        switch type {
        case "GUARDERIA": return "Guardería"
        case "HOSPEDAJE": return "Hospedaje"
        default: return "Paseo"
        }
    }

    /// Color del servicio sobre fondo claro / oscuro (GardenService.ink).
    func ink(dark: Bool) -> Color {
        switch type {
        case "GUARDERIA": return dark ? Color(red: 1, green: 194/255, blue: 77/255) : Color(red: 201/255, green: 133/255, blue: 0)
        case "HOSPEDAJE": return dark ? Color(red: 79/255, green: 209/255, blue: 138/255) : Color(red: 15/255, green: 122/255, blue: 62/255)
        default: return dark ? Color(red: 88/255, green: 226/255, blue: 98/255) : Color(red: 47/255, green: 168/255, blue: 58/255)
        }
    }

    /// Fondo suave del servicio (GardenService.soft).
    func soft(dark: Bool) -> Color {
        switch type {
        case "GUARDERIA": return dark ? Color(red: 51/255, green: 41/255, blue: 15/255) : Color(red: 1, green: 241/255, blue: 214/255)
        case "HOSPEDAJE": return dark ? Color(red: 18/255, green: 48/255, blue: 31/255) : Color(red: 220/255, green: 239/255, blue: 227/255)
        default: return dark ? Color(red: 23/255, green: 58/255, blue: 22/255) : Color(red: 226/255, green: 247/255, blue: 223/255)
        }
    }
}

/// Ícono del servicio sobre su círculo suave, como en la app.
struct GardenServiceBadge: View {
    let style: GardenServiceStyle
    var size: CGFloat = 48
    var dark: Bool = true

    var body: some View {
        ZStack {
            Circle().fill(style.soft(dark: dark))
            Image(style.assetName)
                .resizable()
                .scaledToFit()
                .padding(size * 0.19)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(style.label)
    }
}

// ── Textos y tiempos de la Actividad ─────────────────────────────────────────

@available(iOS 16.2, *)
private extension GardenServiceAttributes {
    var style: GardenServiceStyle { GardenServiceStyle(type: serviceType) }

    func title(_ state: ContentState) -> String {
        if state.status == "COMPLETED" {
            return role == "CLIENT" ? "\(petName) ya volvió" : "Servicio terminado"
        }
        if role == "CLIENT" {
            switch serviceType {
            case "GUARDERIA": return "\(petName) está en guardería"
            case "HOSPEDAJE": return "\(petName) está en hospedaje"
            default: return "\(petName) está de paseo"
            }
        }
        return "\(style.label) con \(petName)"
    }

    var subtitle: String { role == "CLIENT" ? "Con \(caregiverName)" : "Dueño: \(ownerName)" }

    /// "vuelve a las" / "termina a las" / "hasta el".
    var endCaption: String {
        if serviceType == "HOSPEDAJE" { return "hasta el" }
        return serviceType == "PASEO" && role == "CLIENT" ? "vuelve a las" : "termina a las"
    }

    /// garden://service/<bookingId> — mismo formato que el widget de Android,
    /// manejado por AppDelegate.swift (_routeFromDeepLinkURL).
    var deepLinkURL: URL? { URL(string: "garden://service/\(bookingId)") }
}

@available(iOS 16.2, *)
private extension GardenServiceAttributes.ContentState {
    var endsAt: Date { startedAt.addingTimeInterval(TimeInterval(max(totalPaidSeconds, 60))) }
    var range: ClosedRange<Date> { startedAt...endsAt }
}

/// Hora o día de fin, grande y en el color del servicio.
@available(iOS 16.2, *)
private struct EndTimeView: View {
    let attributes: GardenServiceAttributes
    let state: GardenServiceAttributes.ContentState
    var size: CGFloat = 24

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(attributes.endCaption)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gardenSubOnDark)
            Group {
                if attributes.serviceType == "HOSPEDAJE" {
                    Text(state.endsAt, format: .dateTime.weekday(.abbreviated).day())
                } else {
                    Text(state.endsAt, style: .time)
                }
            }
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundColor(attributes.style.ink(dark: true))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
        }
    }
}

/// Barra de avance nativa (se mueve sola, sin gastar actualizaciones) en el
/// color del servicio, y debajo cuánto falta, en vivo.
@available(iOS 16.2, *)
private struct ProgressBlock: View {
    let attributes: GardenServiceAttributes
    let state: GardenServiceAttributes.ContentState

    var body: some View {
        VStack(spacing: 6) {
            ProgressView(timerInterval: state.range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(attributes.style.ink(dark: true))
            .labelsHidden()

            HStack(spacing: 4) {
                Text("Empezó a las")
                Text(state.startedAt, style: .time)
                Spacer(minLength: 4)
                Text("Faltan")
                Text(timerInterval: state.range, countsDown: true, showsHours: true)
                    .monospacedDigit()
                    .foregroundColor(.gardenTextOnDark)
                    .frame(maxWidth: 64, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.gardenSubOnDark)
        }
    }
}

// ── Pantalla de bloqueo / banner ──────────────────────────────────────────────

@available(iOS 16.2, *)
struct GardenLockScreenView: View {
    let context: ActivityViewContext<GardenServiceAttributes>

    var body: some View {
        let a = context.attributes
        let s = context.state
        let done = s.status == "COMPLETED"

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                GardenServiceBadge(style: a.style, size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.title(s))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.gardenTextOnDark)
                        .lineLimit(1)
                    Text(done ? "Toca para ver el resumen" : a.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.gardenSubOnDark)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(a.style.ink(dark: true))
                } else {
                    EndTimeView(attributes: a, state: s)
                }
            }

            if !done {
                ProgressBlock(attributes: a, state: s)

                // Mini-mapa — solo PASEO; se omite hasta que llega el primero.
                if a.serviceType == "PASEO",
                   let data = s.mapSnapshotData,
                   let map = UIImage(data: data) {
                    Image(uiImage: map)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 72)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "es_BO"))
        .activityBackgroundTint(Color.gardenForest)
        .activitySystemActionForegroundColor(.gardenTextOnDark)
        .widgetURL(a.deepLinkURL)
    }
}

// ── Widget + Dynamic Island ───────────────────────────────────────────────────

@available(iOS 16.2, *)
struct GardenServiceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GardenServiceAttributes.self) { context in
            GardenLockScreenView(context: context)
        } dynamicIsland: { context in
            let a = context.attributes
            let s = context.state
            let ink = a.style.ink(dark: true)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        GardenServiceBadge(style: a.style, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.petName)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.gardenTextOnDark)
                                .lineLimit(1)
                            Text(a.style.label)
                                .font(.system(size: 11))
                                .foregroundColor(.gardenSubOnDark)
                        }
                    }
                    .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if s.status != "COMPLETED" {
                        EndTimeView(attributes: a, state: s, size: 20)
                            .padding(.trailing, 6)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if s.status != "COMPLETED" {
                            ProgressBlock(attributes: a, state: s)
                        }
                        HStack(spacing: 6) {
                            Text(a.subtitle)
                                .font(.system(size: 12))
                                .foregroundColor(.gardenSubOnDark)
                                .lineLimit(1)
                            Spacer()
                            // En la isla expandida .widgetURL no cubre las
                            // sub-regiones: el botón necesita su propio Link.
                            if let url = a.deepLinkURL {
                                Link(destination: url) {
                                    HStack(spacing: 3) {
                                        Text(a.serviceType == "PASEO" ? "Ver el mapa" : "Ver en Garden")
                                            .font(.system(size: 12, weight: .semibold))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(ink)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                Image(a.style.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                // Cuánto falta, en vivo (antes: tiempo transcurrido).
                Text(timerInterval: s.range, countsDown: true, showsHours: false)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(ink)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(a.style.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            }
            .keylineTint(ink)
            .widgetURL(a.deepLinkURL)
        }
    }
}

// ── Bundle entry point ────────────────────────────────────────────────────────

@available(iOS 16.2, *)
@main
struct GardenActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        GardenServiceLiveActivityWidget()
        GardenQuickSearchWidget()
    }
}
