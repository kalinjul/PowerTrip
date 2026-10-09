import SwiftUI
import Shared

/// The committed trip: its numbers, planning it anew from here or ending it, the stops and the hand-off to Maps.
struct ActiveRouteView: View {
    let state: ActiveRouteUiState
    let now: Date
    let actions: TripActions
    let onEnd: () -> Void

    // Kept past "Navigieren beenden", so the page keeps its content while it slides out.
    @State private var lastTrip: CommittedTrip?

    var body: some View {
        Group {
            if let trip = state.trip ?? lastTrip {
                VStack(spacing: 0) {
                    summary(trip.plan)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    PlanBody(
                        plan: trip.plan,
                        startSocPercent: trip.startSocPercent?.doubleValue,
                        selection: state.selection,
                        layout: .list,
                        now: now,
                        actions: actions
                    )
                }
                .navigationTitle(trip.plan.destination.name)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: state.trip, initial: true) { _, trip in
            if let trip { lastTrip = trip }
        }
    }

    private func summary(_ plan: TripPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([
                localized("trip_summary_distance", Int32(plan.route.distanceKm.rounded())),
                durationText(plan.totalMinutes),
                localizedPlural("trip_summary_stops", plan.stops.count, Int32(plan.stops.count)),
            ].joined(separator: " · "))
            .font(.headline)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Text(localized("trip_arr", etaText(plan.totalMinutes, now: now), Int32(plan.arrivalSocPercent.rounded())))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(action: actions.replan) {
                    HStack(spacing: 6) {
                        if state.planning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        Text(localized("trip_replan")).lineLimit(1)
                    }
                    .frame(minHeight: 22)
                }
                .fixedSize()
                .buttonStyle(.bordered)
                .tint(Brand.primary)
                .disabled(!state.canReplan || state.planning)
                .accessibilityIdentifier("replan")
                Button(role: .destructive, action: onEnd) {
                    Text(localized("active_route_end")).lineLimit(1).minimumScaleFactor(0.9).frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("end-trip")
            }
            .font(.subheadline.weight(.medium))
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
