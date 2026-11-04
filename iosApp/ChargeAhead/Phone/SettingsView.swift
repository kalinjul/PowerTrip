import SwiftUI
import Shared

enum SettingsPage: Hashable {
    case garage
    case addCar
    case vehicle
    case networks
    case legal
    case licenses
}

/// What Android keeps in its drawer, as a settings sheet: car, networks, minimum power, modes, about.
struct SettingsView: View {
    @StateObject private var owner: ViewModelOwner
    @State private var path: [SettingsPage]
    private let feature: ChargeStopsFeature

    init(feature: ChargeStopsFeature, startPage: SettingsPage?) {
        self.feature = feature
        _owner = StateObject(wrappedValue: ViewModelOwner(feature: feature))
        _path = State(initialValue: startPage.map { [$0] } ?? [])
    }

    var body: some View {
        let drawer = owner.viewModels.drawer()
        NavigationStack(path: $path) {
            Observing(drawer.uiState) { state in
                SettingsContent(
                    state: state,
                    onMinPower: { drawer.onFiltersChanged(filters: state.filters.doCopy(minPowerKw: $0, slowMode: state.filters.slowMode)) },
                    onMode: { drawer.onModeSelected(target: $0) }
                )
            }
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .garage: GarageView(feature: feature, onAdd: { path.append(.addCar) })
                case .addCar: AddCarView(feature: feature, onCustomCreated: { path = path.dropLast() + [.vehicle] })
                case .vehicle: VehicleEditView(feature: feature, onRemoved: { path.removeLast() })
                case .networks: NetworksView(feature: feature)
                case .legal: LegalView()
                case .licenses: LicensesView(feature: feature)
                }
            }
        }
    }
}

struct SettingsContent: View {
    let state: DrawerUiState
    let onMinPower: (Double) -> Void
    let onMode: (ChargeMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var explainingModes = false

    var body: some View {
        List {
            Section(localized("drawer_preferences")) {
                NavigationLink(value: SettingsPage.garage) {
                    NavigationRowLabel(systemImage: "car", title: localized("drawer_car"), subtitle: state.vehicleName ?? localized("drawer_car_none"))
                }
                .accessibilityIdentifier("garage")
                NavigationLink(value: SettingsPage.networks) {
                    NavigationRowLabel(systemImage: "line.3.horizontal.decrease", title: localized("drawer_networks"), subtitle: state.preferredNetworkCount > 0
                        ? localized("drawer_networks_selected", state.preferredNetworkCount)
                        : localized("drawer_networks_all"))
                }
            }
            Section(localized("drawer_min_power")) {
                Picker(localized("drawer_min_power"), selection: Binding(get: { state.filters.minPowerKw }, set: onMinPower)) {
                    ForEach([50.0, 150.0, 300.0], id: \.self) { step in
                        Text(localized("drawer_power_step", Int32(step))).tag(step)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                HStack(spacing: 10) {
                    ModeTile(mode: .ac, title: localized("drawer_mode_ac"), systemImage: "powerplug", current: state.mode, onSelect: onMode)
                    ModeTile(mode: .browse, title: localized("mode_browse"), systemImage: "globe.europe.africa", current: state.mode, onSelect: onMode)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                HStack(spacing: 6) {
                    Text(localized("drawer_mode"))
                    Button {
                        explainingModes = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localized("drawer_mode_info"))
                    .popover(isPresented: $explainingModes) {
                        Text(localized("drawer_mode_tooltip"))
                            .font(.footnote)
                            .padding()
                            .frame(idealWidth: 300)
                            .fixedSize(horizontal: false, vertical: true)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
            Section {
                NavigationLink(value: SettingsPage.legal) {
                    NavigationRowLabel(systemImage: "info.circle", title: localized("drawer_legal"))
                }
                NavigationLink(value: SettingsPage.licenses) {
                    NavigationRowLabel(systemImage: "doc.text", title: localized("drawer_licenses"))
                }
            } header: {
                Text(localized("drawer_about"))
            } footer: {
                BrandSignature()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
            }
        }
        .navigationTitle(localized("home_settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localized("ios_done")) { dismiss() }
                    .accessibilityIdentifier("settings-done")
            }
        }
    }
}

/// What a row that opens a page shows: icon, title, the current value under it.
struct NavigationRowLabel: View {
    let systemImage: String
    let title: String
    var subtitle: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.secondary)
        }
    }
}

/// One mode as a quick-settings tile: grey when off, filled with the mode's colour when on; tapping the lit one turns it off.
private struct ModeTile: View {
    let mode: ChargeMode
    let title: String
    let systemImage: String
    let current: ChargeMode
    let onSelect: (ChargeMode) -> Void

    var body: some View {
        let selected = current == mode
        Button {
            onSelect(selected ? .normal : mode)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Brand.onMode(mode) : .secondary)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                selected ? AnyShapeStyle(Brand.mode(mode)) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                in: RoundedRectangle(cornerRadius: selected ? 28 : 20)
            )
            .animation(.snappy, value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Imprint and privacy.
struct LegalView: View {
    var body: some View {
        List {
            Section(localized("about_legal_imprint")) {
                Text(localized("about_legal_imprint_body")).textSelection(.enabled)
            }
            Section(localized("about_legal_privacy")) {}
        }
        .navigationTitle(localized("drawer_legal"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Where the data comes from, each source with its datasets and their licences.
struct LicensesView: View {
    @StateObject private var owner: ViewModelOwner

    init(feature: ChargeStopsFeature) {
        _owner = StateObject(wrappedValue: ViewModelOwner(feature: feature))
    }

    var body: some View {
        let licenses = owner.viewModels.licenses()
        Observing(licenses.uiState) { state in
            LicensesContent(state: state, onRetry: { licenses.onRetry() })
        }
    }
}

struct LicensesContent: View {
    let state: LicensesUiState
    let onRetry: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Text(localized("about_licenses_intro", localized("app_name")))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section(localized("about_licenses_data_sources")) {
                switch onEnum(of: state.dataSources) {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed:
                    HStack {
                        Text(localized("about_data_sources_failed")).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button(localized("about_data_sources_retry"), action: onRetry)
                    }
                case .loaded(let loaded):
                    ForEach(loaded.sources, id: \.id) { source in
                        VStack(alignment: .leading, spacing: 6) {
                            link(source.name, url: source.url).font(.subheadline.weight(.semibold))
                            ForEach(Array(source.datasets.enumerated()), id: \.offset) { _, dataset in
                                HStack {
                                    Text(label(dataset.kind)).font(.subheadline).foregroundStyle(.secondary)
                                    Spacer()
                                    if let license = dataset.license {
                                        link(license.name, url: license.url).font(.footnote)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(localized("drawer_licenses"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func link(_ title: String, url: String?) -> some View {
        if let url, let target = URL(string: url) {
            Button(title) { openURL(target) }.buttonStyle(.plain).foregroundStyle(Brand.primary)
        } else {
            Text(title)
        }
    }

    private func label(_ kind: DatasetKind) -> String {
        switch kind {
        case .sites: return localized("about_dataset_sites")
        case .status: return localized("about_dataset_status")
        case .routing: return localized("about_dataset_routing")
        case .places: return localized("about_dataset_places")
        default: return localized("about_dataset_other")
        }
    }
}
