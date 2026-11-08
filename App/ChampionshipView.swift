import SwiftUI
import Observation

/// The official driver standings for one season, fetched when the page is first reached and refreshed
/// while it stays open, so a freshly classified race shows up without relaunching.
@MainActor @Observable
final class StandingsStore {
    private(set) var standings: ChampionshipStandings?
    private(set) var failed = false
    private var scope = ""

    func load(endpoint: String, season: Int) async {
        let key = "\(endpoint)|\(season)"
        if scope != key { scope = key; standings = nil }
        guard let url = ChampionshipStandings.endpoint(from: endpoint, season: season) else {
            failed = true
            return
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let result = try JSONDecoder().decode(ChampionshipStandings.self, from: data)
            guard result.season == season else { throw URLError(.cannotParseResponse) }
            guard scope == key else { return }
            standings = result
            failed = false
        } catch {
            // A cancelled refresh (the page went away) is not a failure to show.
            if scope == key, !Task.isCancelled { failed = true }
        }
    }
}

/// The championship table. While a race or sprint is running it adds the points the current running order
/// would score and re-sorts, marking the change; otherwise it shows the official table as published.
struct ChampionshipView: View {
    let snapshot: TimingSnapshot
    let endpoint: String
    @State private var store = StandingsStore()
    @ScaledMetric(relativeTo: .body) private var rowHeight = 44
    @Environment(\.dynamicTypeSize) private var typeSize

    private var season: Int {
        let start = snapshot.session.flatMap { TrackLayout.parseDate($0.start) } ?? Date()
        return Calendar(identifier: .gregorian).component(.year, from: start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            RacingSectionTitle(title: "Championship", subtitle: "Drivers · \(season)")
            content
        }
        .racingCard()
        .task(id: "\(endpoint)|\(season)") {
            // Official points change only when a race is classified, so a slow refresh is enough.
            while !Task.isCancelled {
                await store.load(endpoint: endpoint, season: season)
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let standings = store.standings {
            // The clock only matters at the edges of the session, so a minute is fine grained enough.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                table(standings, session: ChampionshipProjection.scoringSession(for: snapshot, now: context.date))
            }
        } else if store.failed {
            VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                Label("Standings unavailable. Check your backend connection.", systemImage: "wifi.exclamationmark")
                    .font(RacingStyle.Typography.body).foregroundStyle(Color(RacingPalette.statusStale))
                Button { Task { await store.load(endpoint: endpoint, season: season) } } label: {
                    Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(RacingStyle.textPrimary)
                .accessibilityLabel("Retry").help("Retry")
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: rowHeight)
                .accessibilityLabel("Loading standings")
        }
    }

    @ViewBuilder private func table(_ standings: ChampionshipStandings, session: ChampionshipSession?) -> some View {
        let rows = ChampionshipProjection.rows(standings: standings, snapshot: snapshot, session: session)
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            banner(standings, session: session)
            if rows.isEmpty {
                Text("The season's first standings are not published yet.")
                    .font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    standingRow(row, projecting: session != nil)
                    if row.id != rows.last?.id { Divider().overlay(RacingStyle.raised) }
                }
            }
            Text(standings.footnote)
                .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
        }
    }

    /// Says which of the two tables this is. A projection must never be mistaken for the official points.
    private func banner(_ standings: ChampionshipStandings, session: ChampionshipSession?) -> some View {
        let isDemo = standings.mode == "demo"
        let text: String
        if let session {
            text = (session == .race ? "Projected · If the race ended now" : "Projected · If the sprint ended now")
        } else {
            text = standings.round.map { "Official · After round \($0)" } ?? "Official"
        }
        return HStack(spacing: RacingStyle.Space.s) {
            Label(text, systemImage: session == nil ? "checkmark.seal.fill" : "dot.radiowaves.left.and.right")
                .racingLabel()
                .foregroundStyle(session == nil ? RacingStyle.textPrimary : RacingStyle.onRed)
                .padding(.horizontal, RacingStyle.Space.m).padding(.vertical, RacingStyle.Space.xs)
                .background(session == nil ? RacingStyle.raised : RacingStyle.red, in: Capsule())
            if isDemo {
                Text("Demo").racingLabel().foregroundStyle(Color(RacingPalette.statusDemo))
            }
            if standings.stale {
                Text("Stale").racingLabel().foregroundStyle(Color(RacingPalette.statusStale))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func standingRow(_ row: StandingRow, projecting: Bool) -> some View {
        let shown = projecting ? row.projectedPosition : row.position
        let total = projecting ? row.projectedPoints : row.points
        return HStack(spacing: RacingStyle.Space.m) {
            Text("\(shown)").font(RacingStyle.Typography.figure).lineLimit(1).fixedSize()
                .frame(minWidth: 32, alignment: .trailing)
            RoundedRectangle(cornerRadius: RacingStyle.Radius.tag)
                .fill(row.color.map { Color.team($0) } ?? RacingStyle.raised)
                .frame(width: 4, height: rowHeight * 0.6)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.code ?? String(row.name.split(separator: " ").last?.prefix(3).uppercased() ?? ""))
                    .font(RacingStyle.Typography.code).lineLimit(1)
                if typeSize < .xxLarge || typeSize.isAccessibilitySize {
                    Text(row.team).font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: RacingStyle.Space.s)
            if projecting { movement(row) }
            VStack(alignment: .trailing, spacing: 0) {
                Text(StandingRow.pointsText(total)).font(RacingStyle.Typography.data).lineLimit(1).fixedSize()
                if projecting, row.gained > 0 {
                    Text("+\(row.gained)").font(RacingStyle.Typography.caption.monospacedDigit())
                        .foregroundStyle(RacingStyle.textSecondary).lineLimit(1).fixedSize()
                }
            }
        }
        .frame(minHeight: rowHeight)
        .padding(.vertical, RacingStyle.Space.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenSummary(projecting: projecting))
    }

    /// An arrow and a number, so a rise or a fall is never carried by colour alone.
    @ViewBuilder private func movement(_ row: StandingRow) -> some View {
        if row.change != 0 {
            Label("\(abs(row.change))", systemImage: row.change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(RacingStyle.Typography.label.monospacedDigit())
                .foregroundStyle(row.change > 0 ? Color(RacingPalette.statusLive) : Color(RacingPalette.statusStale))
                .lineLimit(1).fixedSize()
        }
    }
}

extension ChampionshipStandings {
    var footnote: String {
        mode == "demo" ? "\(source). Not real results." : "Source: \(source). Projection assumes the standings before this session and ties keep the official order."
    }
}
