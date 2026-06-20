import ActivityKit
import SwiftUI
import WidgetKit

// ── Brand colors ──────────────────────────────────────────────────────────────

private extension Color {
    static let gardenGreen = Color(red: 119/255, green: 140/255, blue: 67/255)
    static let gardenGreenDim = Color(red: 119/255, green: 140/255, blue: 67/255).opacity(0.22)
    static let gardenSurface = Color(white: 0.11)
}

// ── Attribute helpers ─────────────────────────────────────────────────────────

@available(iOS 16.2, *)
private extension GardenServiceAttributes {
    var serviceEmoji: String { serviceType == "PASEO" ? "🐾" : "🏠" }
    var serviceLabel: String { serviceType == "PASEO" ? "En paseo" : "En hospedaje" }

    func displayTitle(state: ContentState) -> String {
        if state.status == "COMPLETED" { return "Servicio completado 🎉" }
        return role == "CLIENT"
            ? "\(petName) está de \(serviceType == "PASEO" ? "paseo" : "hospedaje")"
            : "Paseando a \(petName)"
    }

    func displaySubtitle() -> String {
        role == "CLIENT" ? "Con \(caregiverName)" : "Dueño: \(ownerName)"
    }
}

// ── Lock Screen / Banner ──────────────────────────────────────────────────────

@available(iOS 16.2, *)
struct GardenLockScreenView: View {
    let context: ActivityViewContext<GardenServiceAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.gardenGreenDim)
                    .frame(width: 54, height: 54)
                Text(context.attributes.serviceEmoji)
                    .font(.system(size: 28))
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
                    Text(context.state.timerValue)
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gardenGreen)
                        .minimumScaleFactor(0.8)
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
                            Text(context.attributes.serviceEmoji)
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
                        Text(context.state.timerValue)
                            .font(.system(size: 20, weight: .heavy, design: .monospaced))
                            .foregroundColor(.gardenGreen)
                        Text("⏱ tiempo")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.5))
                    }
                    .padding(.trailing, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
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
                Text(context.attributes.serviceEmoji)
                    .font(.system(size: 14))

            } compactTrailing: {
                Text(context.state.timerValue)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.gardenGreen)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 42)

            } minimal: {
                Text(context.attributes.serviceEmoji)
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
