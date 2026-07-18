import ActivityKit
import SwiftUI
import WidgetKit

// ── Brand colors ──────────────────────────────────────────────────────────────

private extension Color {
    static let gardenGreen = Color(red: 119/255, green: 140/255, blue: 67/255)
    static let gardenGreenDim = Color(red: 119/255, green: 140/255, blue: 67/255).opacity(0.22)
    static let gardenSurface = Color(white: 0.11)
    static let gardenTrack = Color.white.opacity(0.14)
}

// ── Attribute / progress helpers ──────────────────────────────────────────────

@available(iOS 16.2, *)
private extension GardenServiceAttributes {
    /// Icon shown in the small, fixed-size Dynamic Island compact/minimal slots.
    var compactEmoji: String {
        switch serviceType {
        case "PASEO": return "🐕"
        case "GUARDERIA": return "🐕"
        default: return "😴" // HOSPEDAJE
        }
    }

    /// Emoji marker that walks left→right along the progress track. Combos
    /// (two glyphs) are fine here — there's room on lock screen/expanded.
    var progressMarkerEmoji: String {
        switch serviceType {
        case "PASEO": return "🚶‍♂️🐕"       // dueño/cuidador caminando con la mascota
        case "GUARDERIA": return "🐕"        // mascota paseando sola en la guardería
        default: return "🐾💤"               // HOSPEDAJE: mascota durmiendo
        }
    }

    var serviceLabel: String {
        switch serviceType {
        case "PASEO": return "En paseo"
        case "GUARDERIA": return "En guardería"
        default: return "En hospedaje"
        }
    }

    var serviceNoun: String {
        switch serviceType {
        case "PASEO": return "paseo"
        case "GUARDERIA": return "guardería"
        default: return "hospedaje"
        }
    }

    func displayTitle(state: ContentState) -> String {
        if state.status == "COMPLETED" { return "Servicio completado 🎉" }
        return role == "CLIENT"
            ? "\(petName) está de \(serviceNoun)"
            : "Paseando a \(petName)"
    }

    func displaySubtitle() -> String {
        role == "CLIENT" ? "Con \(caregiverName)" : "Dueño: \(ownerName)"
    }
}

@available(iOS 16.2, *)
private extension ActivityViewContext<GardenServiceAttributes> {
    /// 0...1 progress of elapsed time vs. total paid duration, at a given date.
    func progress(at date: Date) -> Double {
        let total = Double(max(state.totalPaidSeconds, 1))
        let elapsed = date.timeIntervalSince(state.startedAt)
        return min(max(elapsed / total, 0), 1)
    }

    /// Slightly over the goal (extra/unpaid overtime not yet reflected in an
    /// approved extension) — used to flag the bar in amber instead of hiding it.
    func isOvertime(at date: Date) -> Bool {
        date.timeIntervalSince(state.startedAt) > Double(state.totalPaidSeconds)
    }
}

// ── Reusable walking-progress bar ─────────────────────────────────────────────

/// Horizontal track with an emoji marker sliding left→right as the service
/// advances towards its paid time goal, capped by a Garden paw print at the
/// finish line. Recomputes every few seconds via TimelineView (fully local,
/// no extra ActivityKit updates) and glides between ticks with `.animation`
/// so the motion still reads as continuous on the lock screen.
@available(iOS 16.2, *)
private struct WalkingProgressBar: View {
    let context: ActivityViewContext<GardenServiceAttributes>
    var markerSize: CGFloat = 22
    var trackHeight: CGFloat = 6
    var pawSize: CGFloat = 16

    var body: some View {
        TimelineView(.periodic(from: context.state.startedAt, by: 3)) { timeline in
            let progress = context.progress(at: timeline.date)
            let overtime = context.isOvertime(at: timeline.date)

            GeometryReader { geo in
                let usableWidth = max(geo.size.width - markerSize, 0)
                let markerX = usableWidth * progress

                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.gardenTrack)
                        .frame(height: trackHeight)

                    // Filled progress
                    Capsule()
                        .fill(overtime ? Color.orange : Color.gardenGreen)
                        .frame(width: max(markerX + markerSize / 2, trackHeight), height: trackHeight)
                        .animation(.linear(duration: 3), value: markerX)

                    // Garden paw at the finish line — brand watermark + goal marker
                    Image("GardenPaw")
                        .resizable()
                        .scaledToFit()
                        .frame(width: pawSize, height: pawSize)
                        .opacity(0.9)
                        .offset(x: usableWidth + markerSize - pawSize / 2, y: 0)

                    // Emoji walking marker
                    Text(context.state.status == "COMPLETED" ? "🏁" : context.attributes.progressMarkerEmoji)
                        .font(.system(size: markerSize))
                        .offset(x: markerX, y: -(markerSize / 2) + trackHeight / 2)
                        .animation(.linear(duration: 3), value: markerX)
                }
            }
            .frame(height: max(markerSize, pawSize))
        }
    }
}

// ── Lock Screen / Banner ──────────────────────────────────────────────────────

@available(iOS 16.2, *)
struct GardenLockScreenView: View {
    let context: ActivityViewContext<GardenServiceAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.gardenGreenDim)
                        .frame(width: 54, height: 54)
                    Text(context.attributes.compactEmoji)
                        .font(.system(size: 26))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.displayTitle(state: context.state))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(context.attributes.displaySubtitle())
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if context.state.status != "COMPLETED" {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(
                            timerInterval: context.state.startedAt...Date.distantFuture,
                            countsDown: false,
                            showsHours: true
                        )
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gardenGreen)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 92)
                        Text("transcurrido")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.5))
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.gardenGreen)
                }
            }

            if context.state.status != "COMPLETED" {
                WalkingProgressBar(context: context, markerSize: 24, trackHeight: 6, pawSize: 18)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .activityBackgroundTint(Color.gardenSurface)
        .activitySystemActionForegroundColor(.white)
    }
}

// ── Widget + Dynamic Island ───────────────────────────────────────────────────

@available(iOS 16.2, *)
struct GardenServiceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GardenServiceAttributes.self) { context in

            // Lock Screen / Banner
            GardenLockScreenView(context: context)

        } dynamicIsland: { context in
            DynamicIsland {

                // Expanded (press & hold the pill)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.gardenGreenDim)
                                .frame(width: 40, height: 40)
                            Text(context.attributes.compactEmoji)
                                .font(.system(size: 20))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.attributes.petName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(context.attributes.serviceLabel)
                                .font(.system(size: 11))
                                .foregroundColor(Color(white: 0.6))
                        }
                    }
                    .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(
                            timerInterval: context.state.startedAt...Date.distantFuture,
                            countsDown: false,
                            showsHours: true
                        )
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gardenGreen)
                        .frame(maxWidth: 92)
                        Text("⏱ tiempo")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.5))
                    }
                    .padding(.trailing, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.status != "COMPLETED" {
                        WalkingProgressBar(context: context, markerSize: 20, trackHeight: 5, pawSize: 14)
                            .padding(.horizontal, 12)
                            .padding(.top, 2)
                    }

                    Divider()
                        .overlay(Color.gardenGreenDim)
                        .padding(.horizontal, 8)

                    HStack(spacing: 6) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.5))
                        Text(context.attributes.displaySubtitle())
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.65))
                        Spacer()
                        HStack(spacing: 3) {
                            Text("Abrir Garden")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.gardenGreen)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }

            } compactLeading: {
                Text(context.attributes.compactEmoji)
                    .font(.system(size: 14))

            } compactTrailing: {
                Text(
                    timerInterval: context.state.startedAt...Date.distantFuture,
                    countsDown: false,
                    showsHours: true
                )
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.gardenGreen)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 42)

            } minimal: {
                Text(context.attributes.compactEmoji)
                    .font(.system(size: 12))
            }
            .keylineTint(.gardenGreen)
            .contentMargins(.horizontal, 10, for: .compactLeading)
            .contentMargins(.horizontal, 10, for: .compactTrailing)
        }
    }
}

// ── Bundle entry point ────────────────────────────────────────────────────────

@available(iOS 16.2, *)
@main
struct GardenActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        GardenServiceLiveActivityWidget()
    }
}
