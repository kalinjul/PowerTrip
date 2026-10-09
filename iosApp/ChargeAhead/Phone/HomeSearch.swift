import SwiftUI
import Shared

/// The always-present search capsule; focusing it switches the home screen into searching.
struct SearchBar: View {
    @Binding var query: String
    let expanded: Bool
    let searching: Bool
    var focused: FocusState<Bool>.Binding
    let onOpen: () -> Void
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if expanded {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(localized("home_search_back"))
            } else {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            }
            TextField(localized("home_search_hint"), text: $query)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("search")
            if searching {
                ProgressView()
            } else if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("home_search_clear"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: RoundButton.size)
        .glassBackground(in: Capsule())
        .onChange(of: focused.wrappedValue) { _, isFocused in
            if isFocused && !expanded { onOpen() }
        }
    }
}

/// Replaces the bar while a trip is shown: where to, how far and how long; the x drops the trip.
struct DestinationHeader: View {
    let title: String
    let subtitle: String?
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("home_trip_clear"))
            .accessibilityIdentifier("trip-clear")
        }
        .padding(.leading, 18)
        .padding(.trailing, 2)
        .frame(height: RoundButton.size)
        .glassBackground(in: Capsule())
    }
}

/// Recents while the query is short, hits once it isn't; the failure and the empty result say so.
struct SearchResultsPanel: View {
    let state: SearchUiState
    let onPick: (SearchRow) -> Void

    var body: some View {
        Group {
            if state.failed {
                message(localized("plan_search_failed"), color: Brand.error)
            } else if state.rows.isEmpty && !state.isQueryTooShort && !state.searching {
                message(localized("plan_no_results"), color: .secondary)
            } else if !state.rows.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(state.rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { Divider().padding(.leading, 44) }
                            SearchRowView(row: row) { onPick(row) }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }
}

private struct SearchRowView: View {
    let row: SearchRow
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: row.recent ? "clock.arrow.circlepath" : "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let detail = row.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if let km = row.distanceKm {
                    Text(localized("plan_result_distance", SearchViewModelKt.asKmLabel(km.doubleValue)))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-row")
    }
}
