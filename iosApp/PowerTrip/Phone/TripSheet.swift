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
            if plan.needsReplan {
                Text(localized("trip_stop_missing"))
                    .font(.footnote)
                    .foregroundStyle(Brand.onErrorContainer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(Brand.errorContainer, in: RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
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
                            .padding(.vertical, 4)
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
                Label(localized("trip_send_maps"), systemImage: "location.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .brandProminent()
            .accessibilityIdentifier("send-to-maps")
            Button(action: onToggleSelecting) {
                Text(localized(selecting ? "trip_select_cancel" : "trip_select_section"))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .tint(Brand.primary)
            .fixedSize()
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

private let markerSize: CGFloat = 24
private let markerGap: CGFloat = 10
private let cardPadding: CGFloat = 12
private let rowPadding: CGFloat = 9
private let lineGap: CGFloat = 3
private let secondLineInset = markerSize + markerGap

/// Start, a card per stop and the destination, the drives between them on a dotted line;
/// while picking a section, a tap picks the point.
struct StopRail: View {
    let plan: TripPlan
    let startSocPercent: Double?
    let selection: SectionSelection
    let now: Date
    let actions: TripActions

    var body: some View {
        let last = plan.stops.count + 1
        let legs = plan.legs
        VStack(spacing: 0) {
            EndRow(
                title: plan.startAddress ?? localized("trip_start"),
                time: etaText(0, now: now),
                level: startSocPercent,
                levelUnknown: localized("trip_dep_now_unknown"),
                temperatureC: plan.route.startTemperatureC?.doubleValue,
                selected: picked(0),
                editDescription: actions.startSocEdit.map { _ in localized("trip_soc_edit") },
                onTap: selection.selecting ? { actions.pointPicked(0) } : actions.startSocEdit
            )
            ForEach(Array(plan.stops.enumerated()), id: \.element.site.id) { offset, stop in
                let index = offset + 1
                LegRow(leg: legs[offset], inSection: picked(offset) && picked(index))
                StopCard(
                    index: index,
                    stop: stop,
                    arrival: etaText(stop.arrivalMinutesFromStart, now: now),
                    selected: picked(index),
                    onTap: { selection.selecting ? actions.pointPicked(index) : actions.stopOpened(stop) }
                )
                .accessibilityIdentifier("trip-stop")
            }
            LegRow(leg: legs[last - 1], inSection: picked(last - 1) && picked(last))
            EndRow(
                title: plan.destination.name,
                time: etaText(plan.totalMinutes, now: now),
                level: plan.arrivalSocPercent,
                temperatureC: plan.route.destinationTemperatureC?.doubleValue,
                selected: picked(last),
                editDescription: actions.arrivalSocEdit.map { _ in localized("trip_arrival_soc_edit") },
                onTap: selection.selecting ? { actions.pointPicked(last) } : actions.arrivalSocEdit
            )
            if let attribution = plan.route.endTemperaturesAttribution {
                Text(attribution)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, cardPadding)
                    .padding(.vertical, 8)
            }
        }
    }

    private func picked(_ index: Int) -> Bool {
        selection.selecting && selection.includes(index: Int32(index))
    }
}

/// Start and destination with the reason in between; both levels stay editable, a different one may get there.
private struct UnreachableRail: View {
    let trip: TripUiStateUnreachable
    let actions: TripActions

    var body: some View {
        VStack(spacing: 0) {
            EndRow(
                title: localized("trip_start"),
                level: trip.startSocPercent?.doubleValue,
                levelUnknown: localized("trip_dep_now_unknown"),
                editDescription: localized("trip_soc_edit"),
                onTap: actions.startSocEdit
            )
            HStack(spacing: markerGap) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Brand.error)
                    .frame(width: markerSize, height: markerSize)
                Text(ChargeStopFormatter.shared.unreachableMessage(why: trip.why))
                    .font(.subheadline)
                    .foregroundStyle(Brand.error)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 6)
            EndRow(
                title: trip.destination.name,
                editDescription: localized("trip_arrival_soc_edit"),
                onTap: actions.arrivalSocEdit
            )
        }
    }
}

/// The trip's start or destination: a pin, the name and one time, the charge level and the forecast below.
private struct EndRow: View {
    let title: String
    var time: String? = nil
    var level: Double? = nil
    /// Stands in for an unknown level; without either the row has no second line.
    var levelUnknown: String? = nil
    var temperatureC: Double? = nil
    var selected = false
    /// Names what a tap edits and shows the pen; `nil` on a row that edits nothing.
    let editDescription: String?
    let onTap: (() -> Void)?

    var body: some View {
        let hasSecondLine = level != nil || levelUnknown != nil || temperatureC != nil
        VStack(alignment: .leading, spacing: lineGap) {
            HStack(spacing: 0) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Brand.primary)
                    .frame(width: markerSize, height: markerSize)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.leading, markerGap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !hasSecondLine { EditPen(description: editDescription) }
                if let time { ClockText(time) }
            }
            if hasSecondLine {
                HStack(spacing: 6) {
                    if let level {
                        BatteryIcon(percent: level)
                        LevelText(percent: level)
                    } else if let levelUnknown {
                        MetaLine(levelUnknown)
                    }
                    EditPen(description: editDescription)
                    if let temperatureC {
                        Spacer()
                        MetaLine(localized("trip_temperature", Int32(temperatureC.rounded())))
                    }
                }
                .padding(.leading, secondLineInset)
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Brand.primaryContainer : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }
}

/// One stop as a card: operator, town and arrival, then the levels, the power and the charging time.
private struct StopCard: View {
    let index: Int
    let stop: PlannedStop
    let arrival: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: lineGap) {
                HStack(spacing: 0) {
                    RankBadge(number: index, color: Brand.primary, textColor: Brand.onPrimary)
                    HStack(spacing: 6) {
                        Text(stop.site.operator ?? stop.site.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let town = stop.site.address?.town {
                            Text(town)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, markerGap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ClockText(arrival)
                }
                HStack(spacing: 6) {
                    BatteryIcon(percent: stop.arrivalSocPercent)
                    HStack(spacing: 3) {
                        LevelText(percent: stop.arrivalSocPercent)
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                        LevelText(percent: stop.departureSocPercent)
                    }
                    MetaLine("·")
                    MetaLine(localized("garage_kw", Int32(stop.maxPowerKw.rounded())))
                    Spacer()
                    MetaLine(durationText(stop.chargeMinutes))
                }
                .padding(.leading, secondLineInset)
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Brand.primaryContainer : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Brand.onPrimaryContainer : .primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The drive to the row below: a dotted line under the markers, time and distance beside it.
private struct LegRow: View {
    let leg: TripLeg
    let inSection: Bool

    var body: some View {
        Text("\(durationText(leg.driveMinutes)) · \(localized("trip_summary_distance", Int32(leg.distanceKm.rounded())))")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, cardPadding + secondLineInset)
            .padding(.vertical, 6)
            .background {
                GeometryReader { box in
                    let x = cardPadding + markerSize / 2
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 2))
                        path.addLine(to: CGPoint(x: x, y: box.size.height - 2))
                    }
                    .stroke(inSection ? Brand.primary : Color(.separator), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0, 5]))
                }
            }
    }
}

private struct EditPen: View {
    let description: String?

    var body: some View {
        if let description {
            Image(systemName: "pencil")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .accessibilityLabel(description)
        }
    }
}

private struct ClockText: View {
    let time: String

    init(_ time: String) { self.time = time }

    var body: some View {
        Text(time)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.leading, 8)
    }
}

private struct LevelText: View {
    let percent: Double

    var body: some View {
        Text(localized("garage_percent", Int32(percent.rounded())))
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// A horizontal battery, filled to the level.
private struct BatteryIcon: View {
    let percent: Double

    var body: some View {
        Canvas { context, size in
            let color = GraphicsContext.Shading.color(.secondary)
            let stroke: CGFloat = 1.5
            let nub: CGFloat = 2
            let bodyWidth = size.width - nub
            let body = CGRect(x: stroke / 2, y: stroke / 2, width: bodyWidth - stroke, height: size.height - stroke)
            context.stroke(Path(roundedRect: body, cornerRadius: 2.5), with: color, lineWidth: stroke)
            context.fill(Path(roundedRect: CGRect(x: bodyWidth, y: size.height * 0.3, width: nub, height: size.height * 0.4), cornerRadius: 1), with: color)
            let inset = stroke * 2
            let cell = body.insetBy(dx: inset, dy: inset)
            let width = cell.width * min(1, max(0, percent / 100))
            context.fill(Path(roundedRect: CGRect(x: cell.minX, y: cell.minY, width: width, height: cell.height), cornerRadius: 1), with: color)
        }
        .frame(width: 20, height: 11)
        .accessibilityHidden(true)
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
                            selected ? Brand.primaryContainer : Color(.secondarySystemBackground),
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
