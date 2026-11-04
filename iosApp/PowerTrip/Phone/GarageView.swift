import SwiftUI
import Shared

/// The garage: the cars to swipe through, the selected one's settings, and the two battery levels.
struct GarageView: View {
    @StateObject private var owner: ViewModelOwner
    let onAdd: () -> Void

    init(feature: ChargeStopsFeature, onAdd: @escaping () -> Void) {
        _owner = StateObject(wrappedValue: ViewModelOwner(feature: feature))
        self.onAdd = onAdd
    }

    var body: some View {
        let garage = owner.viewModels.garage()
        Observing(garage.uiState) { state in
            GarageContent(
                state: state,
                actions: GarageActions(
                    addOpened: onAdd,
                    vehicleSelected: { garage.onVehicleSelected(profile: $0) },
                    socOpened: { garage.onSocSheetOpened() },
                    socChanged: { garage.onSocSheetChanged(percent: Int32($0)) },
                    socConfirmed: { garage.onSocSheetConfirmed() },
                    socDismissed: { garage.onSocSheetDismissed() },
                    arrivalOpened: { garage.onArrivalSheetOpened() },
                    arrivalChanged: { garage.onArrivalSheetChanged(percent: Int32($0)) },
                    arrivalConfirmed: { garage.onArrivalSheetConfirmed() },
                    arrivalDismissed: { garage.onArrivalSheetDismissed() }
                )
            )
        }
    }
}

struct GarageActions {
    /// From the empty garage: a link inside a list row would take over the whole row.
    var addOpened: () -> Void = {}
    var vehicleSelected: (VehicleProfile) -> Void = { _ in }
    var socOpened: () -> Void = {}
    var socChanged: (Int) -> Void = { _ in }
    var socConfirmed: () -> Void = {}
    var socDismissed: () -> Void = {}
    var arrivalOpened: () -> Void = {}
    var arrivalChanged: (Int) -> Void = { _ in }
    var arrivalConfirmed: () -> Void = {}
    var arrivalDismissed: () -> Void = {}

    static let none = GarageActions()
}

/// The garage drawn from its state alone.
struct GarageContent: View {
    let state: GarageUiState
    let actions: GarageActions

    var body: some View {
        List {
            if state.loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 228).listRowBackground(Color.clear)
            } else if let selected = state.selected {
                Section {
                    CarPager(vehicles: state.vehicles, selected: selected, fullRangeKm: state.fullRangeKm, onSelect: actions.vehicleSelected)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listSectionSeparator(.hidden)
                }
                .modifier(EdgeToEdgeSection())
                Section {
                    NavigationLink(value: SettingsPage.vehicle) {
                        LevelRowLabel(systemImage: "slider.horizontal.3", title: localized("garage_vehicle_row"), supporting: localized("garage_vehicle_row_hint"))
                    }
                    .accessibilityIdentifier("vehicle-edit")
                }
            } else {
                Section {
                    EmptyGarageCard(onAdd: actions.addOpened)
                        .listRowInsets(EdgeInsets())
                }
            }
            if !state.loading {
                Section {
                    Button(action: actions.socOpened) {
                        LabeledContent {
                            Text(localized("garage_percent", Int32(state.socPercent.rounded()))).levelValue()
                        } label: {
                            LevelRowLabel(systemImage: "battery.25percent", title: localized("garage_soc_title"), supporting: localized("garage_soc_row_hint"))
                        }
                    }
                    .accessibilityIdentifier("level-soc")
                    Button(action: actions.arrivalOpened) {
                        LabeledContent {
                            Text(localized("garage_percent", Int32(state.arrivalSocPercent.rounded()))).levelValue()
                        } label: {
                            LevelRowLabel(systemImage: "flag", title: localized("garage_arrival_title"), supporting: localized("garage_arrival_row_hint"))
                        }
                    }
                    .accessibilityIdentifier("level-arrival")
                }
            }
        }
        .listSectionSpacing(16)
        .navigationTitle(localized("garage_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if state.selected != nil {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: SettingsPage.addCar) {
                        Label(localized("garage_add_title"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("garage-add")
                }
            }
        }
        .sheet(item: Binding(
            get: { state.socSheet.map { OpenLevel(percent: $0.intValue) } },
            set: { open in if open == nil { actions.socDismissed() } }
        )) { open in
            LevelSheet(
                title: localized("garage_soc_title"),
                hint: localized("garage_soc_sheet_hint"),
                percent: open.percent,
                range: TripPlanKt.SOC_RANGE,
                onChange: actions.socChanged,
                onApply: actions.socConfirmed,
                onCancel: actions.socDismissed
            )
        }
        .sheet(item: Binding(
            get: { state.arrivalSheet.map { OpenLevel(percent: $0.intValue) } },
            set: { open in if open == nil { actions.arrivalDismissed() } }
        )) { open in
            LevelSheet(
                title: localized("garage_arrival_title"),
                hint: localized("garage_arrival_sheet_hint"),
                percent: open.percent,
                range: GarageViewModelKt.ARRIVAL_SOC_RANGE,
                onChange: actions.arrivalChanged,
                onApply: actions.arrivalConfirmed,
                onCancel: actions.arrivalDismissed
            )
        }
    }
}

/// A sheet's level as an item, so `.sheet(item:)` keeps showing it while the sheet animates away.
private struct OpenLevel: Identifiable {
    let percent: Int
    var id: Int { 0 }
}

/// The cars side by side; the next one peeks in at the edge and swiping to it selects it.
private struct CarPager: View {
    let vehicles: [VehicleProfile]
    let selected: VehicleProfile
    let fullRangeKm: [String: KotlinDouble]
    let onSelect: (VehicleProfile) -> Void

    @State private var shownId: String?

    /// The cards line up with the rows below; the neighbours peek into the margin.
    private static let inset: CGFloat = 16
    private static let gap: CGFloat = 6

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Self.gap) {
                ForEach(vehicles, id: \.id) { vehicle in
                    CarCard(vehicle: vehicle, fullRangeKm: fullRangeKm[vehicle.id]?.doubleValue)
                        .accessibilityElement(children: .combine)
                        .containerRelativeFrame(.horizontal)
                        // The neighbours shrink towards the shown card and fade, so a swipe glides instead of jumping.
                        .scrollTransition(.interactive, axis: .horizontal) { card, phase in
                            card
                                .scaleEffect(1 - 0.08 * abs(phase.value), anchor: phase.value < 0 ? .trailing : .leading)
                                .opacity(1 - 0.4 * abs(phase.value))
                        }
                        .accessibilityIdentifier("vehicle")
                        .accessibilityAddTraits(vehicle.id == selected.id ? .isSelected : [])
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Self.inset, for: .scrollContent)
        // Room for the card's shadow, which the list row would otherwise cut off.
        .contentMargins(.vertical, 12, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $shownId)
        .scrollClipDisabled()
        .onAppear { shownId = selected.id }
        .onChange(of: selected.id) { _, id in
            if shownId != id { withAnimation { shownId = id } }
        }
        .onChange(of: shownId) { _, id in
            guard let id, id != selected.id, let vehicle = vehicles.first(where: { $0.id == id }) else { return }
            onSelect(vehicle)
        }
    }
}

/// A list row clips what it draws, so the pager's row has to reach the screen's edges for a neighbour to peek.
private struct EdgeToEdgeSection: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.listSectionMargins(.horizontal, 0)
        } else {
            content
        }
    }
}

/// The car in the brand's tint: its name, the range on a full battery, and the three numbers planning uses.
private struct CarCard: View {
    let vehicle: VehicleProfile
    let fullRangeKm: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(vehicle.displayName).font(.title2.weight(.semibold)).lineLimit(2)
            if let km = fullRangeKm {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(localized("garage_range_number", Int32(km.rounded())))
                        .font(.system(size: 52, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text(localized("garage_range_unit")).font(.title2.weight(.semibold))
                }
                .padding(.top, 12)
                Text(localized("garage_range_caption")).font(.subheadline).opacity(0.75)
            }
            Divider().overlay(Brand.onPrimaryContainer.opacity(0.15)).padding(.vertical, 16)
            HStack(alignment: .top) {
                Stat(label: localized("garage_stat_battery"), value: oneDecimal(vehicle.usableBatteryKwh), unit: localized("garage_unit_kwh"))
                Stat(
                    label: localized("garage_stat_dc"),
                    value: vehicle.dcPeakPowerKw.map { "\(Int($0.doubleValue.rounded()))" } ?? "–",
                    unit: localized("garage_unit_kw")
                )
                Stat(label: localized("garage_stat_consumption"), value: oneDecimal(vehicle.consumptionKwhPer100Km), unit: localized("garage_unit_kwh_per_100"))
            }
        }
        .foregroundStyle(Brand.onPrimaryContainer)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // On the shape alone: on the whole card, every label would cast its own shadow.
            RoundedRectangle(cornerRadius: 24)
                .fill(Brand.primaryContainer)
                .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
        }
    }

    private struct Stat: View {
        let label: String
        let value: String
        let unit: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.footnote.weight(.medium)).opacity(0.75)
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                Text(unit).font(.caption2.weight(.medium)).opacity(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EmptyGarageCard: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "car.fill")
                .font(.system(size: 28))
                .foregroundStyle(Brand.onPrimaryContainer)
                .frame(width: 64, height: 64)
                .background(Brand.primaryContainer, in: Circle())
            Text(localized("garage_empty_title")).font(.headline).padding(.top, 10)
            Text(localized("garage_empty_text"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onAdd) {
                Label(localized("garage_add_title"), systemImage: "plus")
            }
            .brandProminent()
            .padding(.top, 14)
            .accessibilityIdentifier("garage-add")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

/// Grey icon, title, a line under it; the rows of the garage.
private struct LevelRowLabel: View {
    let systemImage: String
    let title: String
    let supporting: String

    var body: some View {
        // Fixed colours: inside a List button the hierarchical styles would follow the tint.
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Color(.label))
                Text(supporting).font(.footnote).foregroundStyle(Color(.secondaryLabel))
            }
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Color(.secondaryLabel))
        }
    }
}

private extension Text {
    func levelValue() -> some View {
        font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Brand.primary)
    }
}

/// A level picked with a slider, applied only on confirm, like the Android sheet.
struct LevelSheet: View {
    let title: String
    var hint: String?
    /// `nil` while no level is known yet; apply waits for one.
    let percent: Int?
    let range: KotlinIntRange
    var applyLabel = localized("soc_dialog_apply")
    let onChange: (Int) -> Void
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button(localized("soc_dialog_cancel"), role: .cancel, action: onCancel)
            }
            if let hint {
                Text(hint).foregroundStyle(.secondary)
            }
            Text(percent.map { localized("garage_percent", Int32($0)) } ?? "–")
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Slider(
                value: Binding(
                    get: { Double(percent ?? Int((range.first + range.last) / 2)) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: Double(range.first)...Double(range.last),
                step: 1
            )
            Button(action: onApply) {
                Text(applyLabel).frame(maxWidth: .infinity)
            }
            .brandProminent()
            .controlSize(.large)
            .disabled(percent == nil)
        }
        .padding(24)
        .tint(Brand.primary)
        .presentationDetents([.medium])
        .onAppear {
            // Nothing stored yet: start where the slider stands, so apply works without a drag.
            if percent == nil { onChange(Int((range.first + range.last) / 2)) }
        }
    }
}

/// The catalog minus what is already in the garage, searchable; a tap adds the car and selects it.
struct AddCarView: View {
    @StateObject private var owner: ViewModelOwner
    /// An own car has no values yet; the caller opens its page instead of going back.
    let onCustomCreated: () -> Void
    // The field's own echo: read back from the ViewModel, fast typing lost characters.
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    init(feature: ChargeStopsFeature, onCustomCreated: @escaping () -> Void) {
        _owner = StateObject(wrappedValue: ViewModelOwner(feature: feature))
        self.onCustomCreated = onCustomCreated
    }

    var body: some View {
        let addCar = owner.viewModels.addCar()
        Observing(addCar.uiState) { state in
            AddCarContent(
                state: state,
                query: $query,
                onPresetAdded: { addCar.onPresetAdded(preset: $0) },
                onCustomCreated: { addCar.onCustomCarCreated(name: $0) }
            )
        }
        .onChange(of: query) { _, text in owner.viewModels.addCar().onQueryChanged(query: text) }
        .task {
            for await event in addCar.event {
                guard let event else { continue }
                addCar.onEventHandled()
                switch onEnum(of: event) {
                case .presetAdded: dismiss()
                case .customCreated: onCustomCreated()
                }
            }
        }
    }
}

struct AddCarContent: View {
    let state: AddCarUiState
    @Binding var query: String
    let onPresetAdded: (VehiclePreset) -> Void
    var onCustomCreated: (String) -> Void = { _ in }

    var body: some View {
        let typed = state.query.trimmingCharacters(in: .whitespaces)
        List {
            ForEach(state.matches, id: \.id) { preset in
                Button {
                    onPresetAdded(preset)
                } label: {
                    AddRow(
                        title: preset.name,
                        subtitle: localized(
                            "garage_preset_line",
                            oneDecimal(preset.usableBatteryKwh),
                            oneDecimal(preset.consumptionKwhPer100Km),
                            Int32(preset.dcPeakPowerKw.rounded())
                        )
                    )
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("preset")
            }
            Button {
                onCustomCreated(typed.isEmpty ? localized("addcar_custom_default_name") : typed)
            } label: {
                AddRow(
                    title: typed.isEmpty ? localized("addcar_custom") : localized("addcar_custom_named", typed),
                    subtitle: localized("addcar_custom_hint")
                )
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("custom-car")
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: localized("garage_search"))
        .navigationTitle(localized("garage_add_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct AddRow: View {
        let title: String
        let subtitle: String

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Brand.primary)
            }
        }
    }
}

/// "52.8" or "52,8", following the device's locale like the Android garage.
func oneDecimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
}
