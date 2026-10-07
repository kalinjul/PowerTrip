import SwiftUI
import Shared

/// The garage: the car planning uses, adding one from the catalog, and the two battery levels.
struct GarageView: View {
    @StateObject private var owner: ViewModelOwner

    init(feature: ChargeStopsFeature) {
        _owner = StateObject(wrappedValue: ViewModelOwner(feature: feature))
    }

    var body: some View {
        let garage = owner.viewModels.garage()
        Observing(garage.uiState) { state in
            GarageContent(
                state: state,
                actions: GarageActions(
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
            ) {
                AddCarView(addCar: owner.viewModels.addCar())
            }
        }
    }
}

struct GarageActions {
    var vehicleSelected: (VehicleProfile) -> Void = { _ in }
    var socOpened: () -> Void = {}
    var socChanged: (Int) -> Void = { _ in }
    var socConfirmed: () -> Void = {}
    var socDismissed: () -> Void = {}
    var arrivalOpened: () -> Void = {}
    var arrivalChanged: (Int) -> Void = { _ in }
    var arrivalConfirmed: () -> Void = {}
    var arrivalDismissed: () -> Void = {}
}

/// The garage drawn from its state alone.
struct GarageContent<AddCar: View>: View {
    let state: GarageUiState
    var actions = GarageActions()
    @ViewBuilder let addCar: () -> AddCar
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if state.loading {
                    ProgressView()
                } else {
                    Section {
                        if state.vehicles.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(localized("garage_empty_title")).font(.headline)
                                Text(localized("garage_empty_text"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(state.vehicles, id: \.id) { vehicle in
                            Button {
                                actions.vehicleSelected(vehicle)
                            } label: {
                                VehicleRow(
                                    vehicle: vehicle,
                                    rangeKm: state.fullRangeKm[vehicle.id]?.doubleValue,
                                    selected: vehicle.id == state.selected?.id
                                )
                            }
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("vehicle")
                            .accessibilityAddTraits(vehicle.id == state.selected?.id ? .isSelected : [])
                        }
                        NavigationLink {
                            addCar()
                        } label: {
                            Label(localized("garage_add_title"), systemImage: "plus")
                        }
                        .accessibilityIdentifier("garage-add")
                    }
                    Section {
                        LevelRow(
                            icon: "bolt.batteryblock",
                            title: localized("garage_soc_title"),
                            hint: localized("garage_soc_row_hint"),
                            percent: state.socPercent,
                            onTap: actions.socOpened
                        )
                        .accessibilityIdentifier("level-soc")
                        LevelRow(
                            icon: "flag",
                            title: localized("garage_arrival_title"),
                            hint: localized("garage_arrival_row_hint"),
                            percent: state.arrivalSocPercent,
                            onTap: actions.arrivalOpened
                        )
                        .accessibilityIdentifier("level-arrival")
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
            .navigationTitle(localized("garage_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("ios_done")) { dismiss() }
                }
            }
        }
    }
}

/// A sheet's level as an item, so `.sheet(item:)` keeps showing it while the sheet animates away.
private struct OpenLevel: Identifiable {
    let percent: Int
    var id: Int { 0 }
}

private struct VehicleRow: View {
    let vehicle: VehicleProfile
    let rangeKm: Double?
    let selected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.displayName).font(.headline)
                Text(specs).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
    }

    private var specs: String {
        var parts = [
            localized("garage_kwh", oneDecimal(vehicle.usableBatteryKwh)),
            localized("garage_kwh_per_100", oneDecimal(vehicle.consumptionKwhPer100Km)),
        ]
        if let range = rangeKm {
            parts.insert("\(localized("garage_range_number", Int32(range.rounded()))) \(localized("garage_range_unit"))", at: 0)
        }
        return parts.joined(separator: " · ")
    }
}

private struct LevelRow: View {
    let icon: String
    let title: String
    let hint: String
    let percent: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(hint).font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon)
                }
                Spacer()
                Text(localized("garage_percent", Int32(percent.rounded())))
                    .foregroundStyle(.tint)
            }
        }
        .foregroundStyle(.primary)
    }
}

/// A level picked with a slider, applied only on confirm, like the Android sheet.
struct LevelSheet: View {
    let title: String
    let hint: String
    let percent: Int
    let range: KotlinIntRange
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
            Text(hint).foregroundStyle(.secondary)
            Text(localized("garage_percent", Int32(percent)))
                .font(.system(size: 56, weight: .semibold, design: .rounded))
            Slider(
                value: Binding(get: { Double(percent) }, set: { onChange(Int($0.rounded())) }),
                in: Double(range.first)...Double(range.last),
                step: 1
            )
            Button(action: onApply) {
                Text(localized("soc_dialog_apply")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

/// The catalog minus what is already in the garage, searchable; a tap adds the car and selects it.
struct AddCarView: View {
    let addCar: AddCarViewModel
    // The field's own echo: read back from the ViewModel, fast typing lost characters.
    @State private var query = ""

    var body: some View {
        Observing(addCar.uiState) { state in
            AddCarContent(state: state, query: $query) { addCar.onPresetAdded(preset: $0) }
        }
        .onChange(of: query) { _, text in addCar.onQueryChanged(query: text) }
        .onAppear { query = addCar.uiState.value.query }
    }
}

struct AddCarContent: View {
    let state: AddCarUiState
    @Binding var query: String
    var onPresetAdded: (VehiclePreset) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(state.matches, id: \.id) { preset in
            Button {
                onPresetAdded(preset)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).font(.headline)
                    Text(localized(
                        "garage_preset_line",
                        oneDecimal(preset.usableBatteryKwh),
                        oneDecimal(preset.consumptionKwhPer100Km),
                        Int32(preset.dcPeakPowerKw.rounded())
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("preset")
        }
        .overlay {
            if state.matches.isEmpty && !state.query.isEmpty {
                ContentUnavailableView.search(text: state.query)
            }
        }
        .searchable(text: $query, prompt: localized("garage_search"))
        .navigationTitle(localized("garage_add_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "52.8" or "52,8", following the device's locale like the Android garage.
private func oneDecimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
}
