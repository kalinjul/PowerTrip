import SwiftUI
import Shared

/// A charger's details over the map. Live charge points replace the site's connectors: the two often disagree.
struct StopDetailSheet: View {
    let stop: ChargeStop
    let live: [LiveConnectorGroup]?
    /// Arrival and departure when the site is a planned stop.
    let tripLine: String?
    let onNavigate: () -> Void

    var body: some View {
        let formatter = ChargeStopFormatter.shared
        let connectorLines = (live ?? []).isEmpty
            ? formatter.connectorLines(stop: stop)
            : formatter.liveConnectorLines(groups: live ?? [])
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Circle().fill(Brand.operatorColor(stop.site)).frame(width: 10, height: 10)
                    Text(stop.site.operator ?? stop.site.name).font(.title2.bold())
                }
                if let address = formatter.addressLine(stop: stop) {
                    Text(address).font(.subheadline).foregroundStyle(.secondary)
                }
                if let tripLine {
                    Text(tripLine).font(.subheadline).monospacedDigit()
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(formatter.primaryLine(stop: stop)).font(.subheadline.weight(.semibold))
                Text(formatter.secondaryLine(stop: stop)).font(.footnote).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(localized("phone_detail_connectors"))
                if connectorLines.isEmpty {
                    Text(localized("phone_detail_unknown_connectors")).font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(connectorLines, id: \.self) { line in
                        Text(line).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let source = formatter.sourceLine(stop: stop) {
                Text(localized("phone_detail_source", source)).font(.caption).foregroundStyle(.tertiary)
            }
            Button(action: onNavigate) {
                Label(localized("phone_detail_navigate"), systemImage: "flag.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Brand.primary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The small capitals above a group, as on Android's sheets and drawer.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}
