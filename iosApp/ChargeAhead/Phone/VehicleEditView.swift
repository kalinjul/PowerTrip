import SwiftUI
import Shared

/// The selected car's values, each edited in an alert; the catalog values back, or the car out of the garage.
struct VehicleEditView: View {
    @StateObject private var owner: ViewModelOwner
    let onRemoved: () -> Void

    init(feature: ChargeStopsFeature, onRemoved: @escaping () -> Void) {
        _owner = StateObject(wrappedValue: ViewModelOwner(feature: feature))
        self.onRemoved = onRemoved
    }

    var body: some View {
        let vehicleEdit = owner.viewModels.vehicleEdit()
        Observing(vehicleEdit.uiState) { state in
            VehicleEditContent(
                state: state,
                actions: VehicleEditActions(
                    nameOpened: { vehicleEdit.onNameEditOpened() },
                    consumptionOpened: { vehicleEdit.onConsumptionEditOpened() },
                    batteryOpened: { vehicleEdit.onBatteryEditOpened() },
                    dcPeakOpened: { vehicleEdit.onDcPeakEditOpened() },
                    inputChanged: { vehicleEdit.onEditorInputChanged(input: $0) },
                    confirmed: { vehicleEdit.onEditorConfirmed() },
                    dismissed: { vehicleEdit.onEditorDismissed() },
                    catalogRestored: { vehicleEdit.onCatalogValuesRestored() },
                    removeRequested: { vehicleEdit.onVehicleRemoveRequested() },
                    removeConfirmed: { vehicleEdit.onVehicleRemoveConfirmed() },
                    removeCancelled: { vehicleEdit.onVehicleRemoveCancelled() }
                )
            )
            .onChange(of: state.removed, initial: true) { _, removed in
                if removed { onRemoved() }
            }
        }
    }
}

struct VehicleEditActions {
    var nameOpened: () -> Void = {}
    var consumptionOpened: () -> Void = {}
    var batteryOpened: () -> Void = {}
    var dcPeakOpened: () -> Void = {}
    var inputChanged: (String) -> Void = { _ in }
    var confirmed: () -> Void = {}
    var dismissed: () -> Void = {}
    var catalogRestored: () -> Void = {}
    var removeRequested: () -> Void = {}
    var removeConfirmed: () -> Void = {}
    var removeCancelled: () -> Void = {}

    static let none = VehicleEditActions()
}

struct VehicleEditContent: View {
    let state: VehicleEditUiState
    let actions: VehicleEditActions

    // The field keeps its own text: a ViewModel round trip could hand back an older value mid-word.
    @State private var field = ""

    var body: some View {
        Group {
            if let vehicle = state.vehicle {
                List {
                    Section {
                        LabeledContent {
                            Text(state.catalog?.name ?? localized("vehicle_model_own"))
                        } label: {
                            RowLabel(title: localized("vehicle_model"), systemImage: "car")
                        }
                    }
                    Section {
                        valueRow("vehicle_name", "person.text.rectangle", vehicle.displayName, actions.nameOpened)
                        valueRow(
                            "vehicle_consumption", "speedometer",
                            localized("garage_kwh_per_100", oneDecimal(vehicle.consumptionKwhPer100Km)), actions.consumptionOpened
                        )
                        valueRow("vehicle_battery", "battery.25percent", localized("garage_kwh", oneDecimal(vehicle.usableBatteryKwh)), actions.batteryOpened)
                        valueRow(
                            "vehicle_dc", "bolt",
                            vehicle.dcPeakPowerKw.map { localized("garage_kw", Int32($0.doubleValue.rounded())) } ?? localized("vehicle_dc_unknown"),
                            actions.dcPeakOpened
                        )
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Button(action: actions.catalogRestored) {
                                RowLabel(title: localized("phone_action_restore_catalog_values"), systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.plain)
                            .disabled(!state.canRestoreCatalogValues)
                            .opacity(state.canRestoreCatalogValues ? 1 : 0.5)
                            Text(localized(restoreHint))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 40)
                        }
                    }
                    Section {
                        Button(localized("vehicle_remove"), role: .destructive, action: actions.removeRequested)
                            .frame(maxWidth: .infinity)
                    }
                }
                .alert(editorTitle, isPresented: Binding(get: { state.editor != nil }, set: { if !$0 { actions.dismissed() } })) {
                    TextField(editorTitle, text: $field)
                        .keyboardType(state.editor is VehicleEditorName ? .default : .decimalPad)
                    Button(localized("soc_dialog_apply"), action: actions.confirmed)
                        .disabled(state.editor?.applicable != true)
                    Button(localized("soc_dialog_cancel"), role: .cancel, action: actions.dismissed)
                } message: {
                    Text(editorMessage)
                }
                .alert(
                    localized("vehicle_remove_title", vehicle.displayName),
                    isPresented: Binding(get: { state.confirmingRemoval }, set: { if !$0 { actions.removeCancelled() } })
                ) {
                    Button(localized("vehicle_remove_confirm"), role: .destructive, action: actions.removeConfirmed)
                    Button(localized("soc_dialog_cancel"), role: .cancel, action: actions.removeCancelled)
                } message: {
                    Text(localized("vehicle_remove_text"))
                }
            }
        }
        .navigationTitle(localized("vehicle_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: editorKind, initial: true) { _, _ in
            field = editorInput ?? ""
        }
        .onChange(of: field) { _, text in
            if state.editor != nil && text != editorInput { actions.inputChanged(text) }
        }
    }

    private func valueRow(_ titleKey: String, _ systemImage: String, _ value: String, _ onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            LabeledContent {
                Text(value).foregroundStyle(Brand.primary)
            } label: {
                RowLabel(title: localized(titleKey), systemImage: systemImage)
            }
        }
        .buttonStyle(.plain)
    }

    private var restoreHint: String {
        if state.catalog == nil { return "vehicle_restore_unavailable" }
        return state.canRestoreCatalogValues ? "vehicle_restore_customized" : "vehicle_restore_current"
    }

    /// Which editor is open, so switching editors reseeds the field.
    private var editorKind: String {
        switch state.editor {
        case is VehicleEditorName: return "name"
        case is VehicleEditorBattery: return "battery"
        case is VehicleEditorDcPeak: return "dc"
        case is VehicleEditorConsumption: return "consumption"
        default: return ""
        }
    }

    private var editorInput: String? {
        switch state.editor {
        case let name as VehicleEditorName: return name.input
        case let battery as VehicleEditorBattery: return battery.input
        case let dc as VehicleEditorDcPeak: return dc.input
        case let consumption as VehicleEditorConsumption: return consumption.input
        default: return nil
        }
    }

    private var editorTitle: String {
        switch state.editor {
        case is VehicleEditorName: return localized("vehicle_name")
        case is VehicleEditorBattery: return localized("vehicle_battery")
        case is VehicleEditorDcPeak: return localized("vehicle_dc")
        case is VehicleEditorConsumption: return localized("vehicle_consumption")
        default: return ""
        }
    }

    /// The unit and the catalog's value, or why the number can't be taken.
    private var editorMessage: String {
        guard let editor = state.editor else { return "" }
        if !field.trimmingCharacters(in: .whitespaces).isEmpty && !editor.applicable {
            return localized("vehicle_number_invalid")
        }
        let preset = state.catalog
        let catalogValue: String? = {
            switch editor {
            case is VehicleEditorName: return preset?.name
            case is VehicleEditorBattery: return preset.map { localized("garage_kwh", oneDecimal($0.usableBatteryKwh)) }
            case is VehicleEditorDcPeak: return preset.map { localized("garage_kw", Int32($0.dcPeakPowerKw.rounded())) }
            case is VehicleEditorConsumption: return preset.map { localized("garage_kwh_per_100", oneDecimal($0.consumptionKwhPer100Km)) }
            default: return nil
            }
        }()
        let unit: String? = {
            switch editor {
            case is VehicleEditorBattery: return localized("garage_unit_kwh")
            case is VehicleEditorDcPeak: return localized("garage_unit_kw")
            case is VehicleEditorConsumption: return localized("garage_unit_kwh_per_100")
            default: return nil
            }
        }()
        return [unit, catalogValue.map { localized("vehicle_catalog_value", $0) }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// Grey icon, primary title, as in the rest of the settings.
private struct RowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.secondary)
        }
    }
}
