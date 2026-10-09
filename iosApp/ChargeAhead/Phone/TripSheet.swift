import SwiftUI
import Shared

struct TripActions {
    var replan: () -> Void = {}
    var layoutToggled: () -> Void = {}
    var selectingToggled: () -> Void = {}
    var pointPicked: (Int) -> Void = { _ in }
    var stopOpened: (PlannedStop) -> Void = { _ in }
    var sentToMaps: () -> Void = {}
    /// `nil` makes the start row read-only.
    var startSocEdit: (() -> Void)?
    var arrivalSocEdit: (() -> Void)?

    static let none = TripActions()
}

/// The trip sheet's content: a plan, or why there is none.
struct TripSheetContent: View {
    let trip: TripUiStateSheet
    let layout: TripListLayout
    let now: Date
    let actions: TripActions

    var body: some View {
        if let planned = trip as? TripUiStatePlanned {
            VStack(spacing: 0) {
                TripSummaryRow(plan: planned.plan, layout: layout, onReplan: actions.replan, onToggleLayout: actions.layoutToggled)
                Divider()
                PlanBody(
                    plan: planned.plan,
                    startSocPercent: planned.startSocPercent?.doubleValue,
                    selection: planned.selection,
                    layout: layout,
                    now: now,
                    actions: actions
                )
            }
        } else if let unreachable = trip as? TripUiStateUnreachable {
            VStack(spacing: 0) {
                UnreachableSummaryRow(onReplan: actions.replan)
                Divider()
                ScrollView {
                    UnreachableRail(trip: unreachable, actions: actions)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
}

/// The plan's stops (rail or tiles) and the two things one does with them; shared with the active route page.
struct PlanBody: View {
    let plan: TripPlan
    let startSocPercent: Double?
    let selection: SectionSelection
    let layout: TripListLayout
    let now: Date
    let actions: TripActions

    var body: some View {
        VStack(spacing: 0) {
            if selection.selecting {
                SectionHint(waitingForSecond: selection.a != nil && selection.b == nil)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            Group {
                switch layout {
                case .tiles:
                    StopTiles(plan: plan, selection: selection, now: now, actions: actions)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                default:
                    ScrollView {
                        StopRail(plan: plan, startSocPercent: startSocPercent, selection: selection, now: now, actions: actions)
                            .padding(.horizontal, 16)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: layout)
            TripButtons(selecting: selection.selecting, onSend: actions.sentToMaps, onToggleSelecting: actions.selectingToggled)
        }
    }
}

private struct TripSummaryRow: View {
    let plan: TripPlan
    let layout: TripListLayout
    let onReplan: () -> Void
    let onToggleLayout: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("\(localizedPlural("trip_summary_stops", plan.stops.count, Int32(plan.stops.count))) · \(localized("trip_summary_charging", durationText(plan.chargeMinutes)))")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            ReplanButton(action: onReplan)
            Button(action: onToggleLayout) {
                Image(systemName: layout == .tiles ? "list.bullet" : "rectangle.split.3x1")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized(layout == .tiles ? "trip_layout_list" : "trip_layout_tiles"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
    }
}

private struct UnreachableSummaryRow: View {
    let onReplan: () -> Void

    var body: some View {
        HStack {
            Text(localized("trip_unreachable_summary"))
                .font(.footnote)
                .foregroundStyle(Brand.error)
            Spacer()
            ReplanButton(action: onReplan)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }
}

struct ReplanButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(localized("trip_replan"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.footnote.weight(.medium))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(Brand.primary)
        .accessibilityIdentifier("replan")
    }
}

private struct SectionHint: View {
    let waitingForSecond: Bool

    var body: some View {
        Text(localized(waitingForSecond ? "trip_section_hint_second" : "trip_section_hint"))
            .font(.footnote.weight(.medium))
            .foregroundStyle(Brand.onPrimaryContainer)
            .frame(maxWidth: .infinity)
            .padding(9)
            .background(Brand.primaryContainer, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Brand.sectionOutline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
    }
}

private struct TripButtons: View {
    let selecting: Bool
    let onSend: () -> Void
    let onToggleSelecting: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSend) {
                Label(localized("trip_send_maps"), systemImage: "flag.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.primary)
            .accessibilityIdentifier("send-to-maps")
            Button(action: onToggleSelecting) {
                Text(localized(selecting ? "trip_select_cancel" : "trip_select_section"))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .tint(selecting ? Brand.primary : .secondary)
            .fixedSize()
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

/// Start, stops and destination on one vertical line; while picking a section, a tap picks the point.
struct StopRail: View {
    let plan: TripPlan
    let startSocPercent: Double?
    let selection: SectionSelection
    let now: Date
    let actions: TripActions

    var body: some View {
        let last = plan.stops.count + 1
        VStack(spacing: 0) {
            RailRow(
                index: 0,
                last: last,
                selection: selection,
                trailingEdit: actions.startSocEdit.map { _ in localized("trip_soc_edit") },
                onTap: { selection.selecting ? actions.pointPicked(0) : actions.startSocEdit?() }
            ) {
                TerminusDot(color: Brand.start, square: false)
            } content: {
                Text(localized("trip_start")).font(.subheadline.weight(.semibold))
                MetaLine(startSocPercent.map { localized("trip_dep_now", Int32($0.rounded())) } ?? localized("trip_dep_now_unknown"))
            }
            ForEach(Array(plan.stops.enumerated()), id: \.element.site.id) { offset, stop in
                let index = offset + 1
                RailRow(
                    index: index,
                    last: last,
                    selection: selection,
                    onTap: { selection.selecting ? actions.pointPicked(index) : actions.stopOpened(stop) }
                ) {
                    RankBadge(number: index, color: Brand.operatorColor(stop.site))
                } content: {
                    Text(stop.site.operator ?? stop.site.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    MetaLine(localized(
                        "trip_stop_charge",
                        Int32(stop.maxPowerKw.rounded()),
                        Int32(stop.arrivalSocPercent.rounded()),
                        Int32(stop.departureSocPercent.rounded())
                    ))
                    MetaLine(localized(
                        "trip_stop_times",
                        etaText(stop.arrivalMinutesFromStart, now: now),
                        etaText(stop.arrivalMinutesFromStart + stop.chargeMinutes, now: now)
                    ))
                }
                .accessibilityIdentifier("trip-stop")
            }
            RailRow(
                index: last,
                last: last,
                selection: selection,
                trailingEdit: actions.arrivalSocEdit.map { _ in localized("trip_arrival_soc_edit") },
                onTap: { selection.selecting ? actions.pointPicked(last) : actions.arrivalSocEdit?() }
            ) {
                TerminusDot(color: Brand.error, square: true)
            } content: {
                Text(plan.destination.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                MetaLine(localized("trip_arr", etaText(plan.totalMinutes, now: now), Int32(plan.arrivalSocPercent.rounded())))
            }
        }
    }
}

/// Start and destination with the reason in between; both levels stay editable, a different one may get there.
private struct UnreachableRail: View {
    let trip: TripUiStateUnreachable
    let actions: TripActions

    var body: some View {
        let none = SectionSelection(selecting: false, a: nil, b: nil)
        VStack(spacing: 0) {
            RailRow(index: 0, last: 2, selection: none, trailingEdit: localized("trip_soc_edit"), onTap: { actions.startSocEdit?() }) {
                TerminusDot(color: Brand.start, square: false)
            } content: {
                Text(localized("trip_start")).font(.subheadline.weight(.semibold))
                MetaLine(trip.startSocPercent.map { localized("trip_dep_now", Int32($0.doubleValue.rounded())) } ?? localized("trip_dep_now_unknown"))
            }
            RailRow(index: 1, last: 2, selection: none, onTap: nil) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Brand.error)
            } content: {
                Text(ChargeStopFormatter.shared.unreachableMessage(why: trip.why))
                    .font(.subheadline)
                    .foregroundStyle(Brand.error)
            }
            RailRow(index: 2, last: 2, selection: none, trailingEdit: localized("trip_arrival_soc_edit"), onTap: { actions.arrivalSocEdit?() }) {
                TerminusDot(color: Brand.error, square: true)
            } content: {
                Text(trip.destination.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
    }
}

/// One rail row: the line segment, the dot, the text; a picked section tints the row.
private struct RailRow<Dot: View, Content: View>: View {
    let index: Int
    let last: Int
    let selection: SectionSelection
    var trailingEdit: String?
    let onTap: (() -> Void)?
    @ViewBuilder let dot: () -> Dot
    @ViewBuilder let content: () -> Content

    private static var dotSize: CGFloat { 28 }
    private static var dotTop: CGFloat { 8 }

    var body: some View {
        let selected = selection.selecting && selection.includes(index: Int32(index))
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .top) {
                GeometryReader { geometry in
                    let center = Self.dotTop + Self.dotSize / 2
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width / 2, y: index == 0 ? center : 0))
                        path.addLine(to: CGPoint(x: geometry.size.width / 2, y: index == last ? center : geometry.size.height))
                    }
                    .stroke(Color(.separator), lineWidth: 2)
                }
                dot()
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .background(Color(.systemBackground), in: Circle())
                    .padding(.top, Self.dotTop)
            }
            .frame(width: 36)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) { content() }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: Self.dotSize + Self.dotTop, alignment: .leading)
                    if let trailingEdit {
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                            .padding(.trailing, 6)
                            .accessibilityLabel(trailingEdit)
                    }
                }
                if index != last { Divider() }
            }
            .padding(.leading, 4)
        }
        .background {
            if selected {
                Brand.primaryContainer.clipShape(spanShape)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    /// Corners only where the picked span begins or ends, so the tint reads as one block.
    private var spanShape: UnevenRoundedRectangle {
        let top: CGFloat = selection.includes(index: Int32(index - 1)) ? 0 : 10
        let bottom: CGFloat = selection.includes(index: Int32(index + 1)) ? 0 : 10
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top)
    }
}

private struct TerminusDot: View {
    let color: Color
    let square: Bool

    var body: some View {
        if square {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 12)
        } else {
            Circle().fill(color).frame(width: 12, height: 12)
        }
    }
}

struct MetaLine: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

/// The stops as a swipeable row of tiles, for the collapsed sheet.
private struct StopTiles: View {
    let plan: TripPlan
    let selection: SectionSelection
    let now: Date
    let actions: TripActions

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(plan.stops.enumerated()), id: \.element.site.id) { offset, stop in
                    let index = offset + 1
                    let selected = selection.selecting && selection.includes(index: Int32(index))
                    Button {
                        selection.selecting ? actions.pointPicked(index) : actions.stopOpened(stop)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            RankBadge(number: index, color: Brand.operatorColor(stop.site))
                            Text(stop.site.operator ?? stop.site.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            MetaLine(localized("trip_tile_charge", Int32(stop.maxPowerKw.rounded()), Int32(stop.chargeMinutes.rounded())))
                            MetaLine(localized("trip_tile_arrival", etaText(stop.arrivalMinutesFromStart, now: now)))
                        }
                        .padding(10)
                        .frame(width: 136, alignment: .leading)
                        .background(
                            selected ? Brand.primaryContainer : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
