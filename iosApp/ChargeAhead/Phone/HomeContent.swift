import SwiftUI
import Shared

struct HomeActions {
    var settings: () -> Void = {}
    /// The location button with no position to centre on.
    var locate: () -> Void = {}
    /// The location button with a position: the map flies there.
    var recenter: () -> Void = {}
    var chargeNow: () -> Void = {}
    var activeRoute: () -> Void = {}
    var modeDismissed: () -> Void = {}
    var searchOpened: () -> Void = {}
    var searchClosed: () -> Void = {}
    var picked: (SearchRow) -> Void = { _ in }
    var tripCleared: () -> Void = {}
    var destinationTapped: () -> Void = {}
    var permissionRequested: () -> Void = {}
    var zoomHintTapped: () -> Void = {}

    static let none = HomeActions()
}

/// The map screen drawn from its state: the map is a slot, so a golden can put a plain backdrop there.
struct HomeContent<MapLayer: View, Compass: View>: View {
    let home: HomeUiState
    let search: SearchUiState
    @Binding var query: String
    let destination: Destination?
    let plan: TripPlan?
    let planning: Bool
    let activeRouteEnabled: Bool
    /// `nil` until the platform has been asked.
    let hasLocationPermission: Bool?
    let actions: HomeActions
    @ViewBuilder let map: () -> MapLayer
    @ViewBuilder let compass: () -> Compass

    @FocusState private var searchFocused: Bool

    private var searching: Bool { search.expanded }
    private var browsing: Bool { !searching && destination == nil }

    var body: some View {
        ZStack {
            map().ignoresSafeArea()

            ModeGlow(mode: home.mode)

            if searching {
                // While the panel is open the map only takes a dismissing tap.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { actions.searchClosed() }
            }

            VStack(spacing: 8) {
                topBar
                if searching {
                    SearchResultsPanel(state: search, onPick: actions.picked)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack(alignment: .top) {
                        Spacer()
                        if home.locationUnavailable {
                            HintChip(text: localized("phone_status_location_unavailable"), color: Brand.error)
                        }
                        Spacer()
                    }
                    .overlay(alignment: .topTrailing) {
                        VStack(spacing: 8) {
                            compass()
                            if home.loadingSites {
                                ProgressView()
                                    .tint(Brand.primary)
                                    .accessibilityLabel(localized("map_loading_sites"))
                            }
                        }
                        .frame(width: RoundButton.size)
                    }
                }
                Spacer()
                if browsing {
                    bottomControls
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.snappy, value: searching)

            if !searching {
                ModeFlag(mode: home.mode, onDismiss: actions.modeDismissed)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if hasLocationPermission == false {
                PermissionCard(onRequest: actions.permissionRequested)
            }

            if planning {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(localized("plan_planning"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .glassBackground(in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .onChange(of: searching) { _, open in searchFocused = open }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if !searching {
                RoundButton(systemImage: "line.3.horizontal", label: localized("home_settings"), action: actions.settings)
                    .accessibilityIdentifier("settings")
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if let destination, !searching {
                DestinationHeader(
                    title: destination.name,
                    subtitle: plan.map(headerLine),
                    onTap: actions.destinationTapped,
                    onClear: actions.tripCleared
                )
            } else {
                SearchBar(
                    query: $query,
                    expanded: searching,
                    searching: search.searching,
                    focused: $searchFocused,
                    onOpen: actions.searchOpened,
                    onBack: actions.searchClosed
                )
            }
            if !searching {
                RoundButton(
                    systemImage: "location.fill",
                    label: localized("map_my_location"),
                    busy: home.searchingLocation,
                    tint: Brand.primary,
                    action: home.position == nil ? actions.locate : actions.recenter
                )
                .accessibilityValue(home.position == nil ? localized("phone_status_waiting") : "")
                .accessibilityIdentifier("locate")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 24) {
            if home.belowMinZoom {
                Button(action: actions.zoomHintTapped) {
                    HintChip(text: localized("map_zoom_hint"), color: .primary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                HomePill(
                    title: localized("home_pill_charge_now"),
                    systemImage: "bolt.batteryblock.fill",
                    iconTint: Brand.start,
                    action: actions.chargeNow
                )
                .accessibilityIdentifier("charge-now")
                HomePill(
                    title: localized("home_pill_active_route"),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill",
                    iconTint: Brand.primary,
                    action: actions.activeRoute
                )
                .disabled(!activeRouteEnabled)
                .accessibilityIdentifier("active-route")
            }
        }
    }
}

/// "312 km · 3h 10m" for the destination header.
func headerLine(_ plan: TripPlan) -> String {
    "\(localized("trip_summary_distance", Int32(plan.route.distanceKm.rounded()))) · \(durationText(plan.totalMinutes))"
}

/// A round glass button beside the search bar.
struct RoundButton: View {
    static let size: CGFloat = 48

    let systemImage: String
    let label: String
    var busy = false
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().tint(tint)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: Self.size, height: Self.size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassBackground(in: Circle())
        .accessibilityLabel(label)
    }
}

private struct HomePill: View {
    let title: String
    let systemImage: String
    let iconTint: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label {
                Text(title).foregroundStyle(.primary)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(iconTint)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .glassBackground(in: Capsule())
    }
}

struct HintChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassBackground(in: Capsule())
    }
}

/// The mode's colour bleeding in from the screen's edges, breathing slowly; nothing in the normal mode.
private struct ModeGlow: View {
    let mode: ChargeMode

    var body: some View {
        if mode != .normal {
            Rectangle()
                .strokeBorder(Brand.mode(mode), lineWidth: 36)
                .blur(radius: 28)
                .phaseAnimator([0.75, 1.0]) { glow, breath in
                    glow.opacity(breath)
                } animation: { _ in
                    .easeInOut(duration: 1.8)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A small flag on the right edge, mid-height, naming the mode; tapping it switches the mode off.
private struct ModeFlag: View {
    let mode: ChargeMode
    let onDismiss: () -> Void

    var body: some View {
        if mode != .normal {
            Button(action: onDismiss) {
                HStack(spacing: 4) {
                    Text(localized(mode == .ac ? "mode_ac" : "mode_browse"))
                        .font(.caption.weight(.semibold))
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Brand.onMode(mode))
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .background(Brand.mode(mode), in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("home_mode_off"))
        }
    }
}

private struct PermissionCard: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(localized("phone_permission_message"))
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button(localized("phone_permission_action"), action: onRequest)
                .brandProminent()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(32)
    }
}
