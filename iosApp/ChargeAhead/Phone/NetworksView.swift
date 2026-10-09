import SwiftUI
import Shared

/// Picking the networks one charges with; edits are staged and committed when the page is left.
struct NetworksView: View {
    let networks: NetworksViewModel
    // The field's own echo, as in the add-car search.
    @State private var query = ""

    var body: some View {
        Observing(networks.uiState) { state in
            NetworksContent(state: state, query: $query, onToggle: { networks.onNetworkToggled(key: $0) })
        }
        .onChange(of: query) { _, text in networks.onSearchChanged(query: text) }
        .onAppear { networks.onEnter() }
        .onDisappear { networks.onLeave() }
    }
}

struct NetworksContent: View {
    let state: NetworksUiState
    @Binding var query: String
    let onToggle: (String) -> Void

    var body: some View {
        List {
            Section {
                Text(localized("phone_networks_intro")).font(.footnote).foregroundStyle(.secondary)
            }
            Section(localized("phone_networks_mine")) {
                if state.networks.isEmpty {
                    Text(localized("phone_networks_no_match", state.search.trimmingCharacters(in: .whitespaces)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(state.networks, id: \.key) { network in
                    let selected = state.selected.contains(network.key)
                    Button {
                        onToggle(network.key)
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(Brand.networkColor(network.key)).frame(width: 10, height: 10)
                            Text(network.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected ? AnyShapeStyle(Brand.primary) : AnyShapeStyle(.tertiary))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: localized("phone_networks_search"))
        .navigationTitle(localized("phone_networks_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
