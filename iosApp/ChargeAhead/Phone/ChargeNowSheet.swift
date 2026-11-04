import SwiftUI
import Shared

/// "Charge now" over the session's ViewModel, so the map shows the same candidates while the sheet is up.
struct ChargeNowView: View {
    let model: ChargeNowViewModel
    let onNavigate: (ChargeNowCandidate) -> Void
    let onOpen: (ChargeNowCandidate) -> Void

    var body: some View {
        Observing(model.uiState) { sheet in
            if let open = sheet as? ChargeNowSheetUiStateOpen {
                ChargeNowContent(state: open.content, selectedSiteId: open.selectedSiteId, onNavigate: onNavigate, onOpen: onOpen)
            }
        }
        .onDisappear { model.onSheetClosed() }
    }
}

/// The best chargers nearby: no position, loading, empty, or the ranked cards with the relax notice.
struct ChargeNowContent: View {
    let state: ChargeNowUiState
    /// The candidate the map shows as its callout; its card is highlighted and scrolled to.
    var selectedSiteId: String? = nil
    let onNavigate: (ChargeNowCandidate) -> Void
    let onOpen: (ChargeNowCandidate) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("cn_title")).font(.title3.bold())
                    switch onEnum(of: state) {
                    case .noPosition:
                        Text(localized("home_no_position")).foregroundStyle(.secondary)
                    case .loading:
                        Text(localized("cn_subtitle")).font(.footnote).foregroundStyle(.secondary)
                        ForEach(0..<4, id: \.self) { _ in StationCard.placeholder }
                            .redacted(reason: .placeholder)
                            .accessibilityLabel(localized("cn_loading"))
                    case .ready(let ready):
                        rows(ready.result)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .onChange(of: selectedSiteId) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    @ViewBuilder
    private func rows(_ result: ChargeNowResult) -> some View {
        if result.candidates.isEmpty {
            Text(localized("cn_empty")).foregroundStyle(.secondary)
        } else {
            Text(localized(result.relaxed.isEmpty ? "cn_subtitle" : "cn_relaxed"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(Array(result.candidates.enumerated()), id: \.element.site.id) { index, candidate in
                card(rank: index + 1, candidate)
            }
            if !result.more.isEmpty {
                SectionLabel(localized("cn_more")).padding(.top, 8)
                ForEach(Array(result.more.enumerated()), id: \.element.site.id) { index, candidate in
                    card(rank: result.candidates.count + index + 1, candidate)
                }
            }
        }
    }

    private func card(rank: Int, _ candidate: ChargeNowCandidate) -> some View {
        StationCard(
            rank: rank,
            badgeColor: Brand.operatorColor(candidate.site),
            title: candidate.site.operator ?? candidate.site.name,
            address: ChargeStopFormatter.shared.addressLine(site: candidate.site),
            metaLine: chargeNowMeta(candidate),
            sendLabel: localized("cn_navigate", candidate.site.name),
            selected: candidate.site.id == selectedSiteId,
            onSend: { onNavigate(candidate) },
            onTap: { onOpen(candidate) }
        )
        .id(candidate.site.id)
    }
}

/// "3,4 km · 350 kW", on the card and on the map's callout alike.
func chargeNowMeta(_ candidate: ChargeNowCandidate) -> String {
    localized(
        "cn_distance_power",
        candidate.distanceKm.formatted(.number.precision(.fractionLength(1))),
        Int32(candidate.maxPowerKw.rounded())
    )
}

/// The charging-station card: rank, network, address and a hand-off to Maps.
struct StationCard: View {
    let rank: Int
    let badgeColor: Color
    let title: String
    let address: String?
    let metaLine: String
    let sendLabel: String
    var selected = false
    let onSend: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            RankBadge(number: rank, color: badgeColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let address {
                    Text(address).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                MetaLine(metaLine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onSend) {
                Image(systemName: "location.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Brand.primary)
                    .frame(width: 36, height: 36)
                    .background(Brand.primaryContainer, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sendLabel)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .foregroundStyle(selected ? Brand.onPrimaryContainer : .primary)
        .background(selected ? Brand.primaryContainer : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static var placeholder: StationCard {
        StationCard(
            rank: 1, badgeColor: Color(.systemGray4), title: "Ladepark Musterstadt",
            address: "Musterstraße 1, 12345 Musterstadt", metaLine: "1,2 km · 150 kW",
            sendLabel: "", onSend: {}, onTap: {}
        )
    }
}

/// The selected candidate on the map: rank, network, distance and power, the tail's tip on the site.
struct ChargeNowCallout: View {
    let rank: Int
    let color: Color
    let title: String
    let meta: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RankBadge(number: rank, color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(meta).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: 200, alignment: .leading)
            }
            .padding(.leading, 7)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color, lineWidth: 2))
            CalloutTail()
                .fill(color)
                .frame(width: 14, height: 8)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

private struct CalloutTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
