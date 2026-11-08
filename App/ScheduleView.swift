import SwiftUI

struct ScheduleView: View {
    let endpoint: String
    @State private var store = ScheduleStore()
    @State private var results = ResultsStore()
    @State private var season = RaceSchedule.currentSeason()
    @State private var filter = ScheduleFilter.all
    /// The season the filter was last defaulted for, so a refresh keeps the filter the user picked.
    @State private var defaultedFor = ""
    @State private var refresh = 0
    @State private var showingDetails = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var timeZoneName: String { TimeZone.autoupdatingCurrent.identifier }

    var body: some View {
        ScrollViewReader { proxy in
            page(proxy)
        }
    }

    private func page(_ proxy: ScrollViewProxy) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                // At accessibility sizes the header alone would fill the screen, so it scrolls with the list.
                ScrollView {
                    VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                        header
                        listContent(proxy)
                    }
                    .racingPagePadding()
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    // The controls stay put while the list scrolls, so jumping to the next race never hides them.
                    header
                        .racingPagePadding([.horizontal, .top])
                        .padding(.bottom, RacingStyle.Space.s)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                    ScrollView {
                        listContent(proxy)
                            .racingPagePadding([.horizontal, .bottom])
                            .frame(maxWidth: 900)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .background(RacingStyle.background)
        .task(id: "\(endpoint)|\(season)|\(refresh)") {
            results.reset()
            await store.load(endpoint: endpoint, season: season)
            // Open on what is coming: Upcoming while races remain, All once the season is over.
            let key = "\(endpoint)|\(season)"
            if let schedule = store.schedule, defaultedFor != key {
                filter = schedule.defaultFilter(at: .now)
                defaultedFor = key
            }
        }
    }

    private static let topID = "calendar-top"

    private func listContent(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            if store.loading { ProgressView().accessibilityLabel("Loading season").frame(maxWidth: .infinity).padding(RacingStyle.Space.xl) }
            if let error = store.error, store.schedule != nil {
                Label("Refresh failed · Showing saved schedule. \(error)", systemImage: "wifi.exclamationmark")
                    .font(RacingStyle.Typography.caption).foregroundStyle(Color(RacingPalette.statusStale))
            }
            if let error = store.error, store.schedule == nil {
                ContentUnavailableView {
                    Label("Schedule unavailable", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button { refresh += 1 } label: { Label("Try again", systemImage: "arrow.clockwise").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44) }.help("Try again")
                }
            }
            if let schedule = store.schedule {
                calendar(schedule, proxy: proxy)
            }
        }
        .id(Self.topID)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            seasonControls
            Picker("Show races", selection: $filter) {
                ForEach(ScheduleFilter.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            caption
        }
    }

    private var seasonControls: some View {
        HStack(spacing: RacingStyle.Space.s) {
            Image(systemName: "calendar")
                .accessibilityLabel("Calendar").accessibilityAddTraits(.isHeader)
            Picker("Season", selection: $season) {
                ForEach(RaceSchedule.availableSeasons(), id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }.labelsHidden().fixedSize()
            Spacer()
            Button { showingDetails = true } label: {
                Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(RacingStyle.textSecondary)
            .accessibilityLabel("Calendar details").help("Calendar details")
            .popover(isPresented: $showingDetails, arrowEdge: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                        Text("Calendar details").font(RacingStyle.Typography.title)
                        Text("Past means the scheduled race start has passed. Open a past race to see its results, which can take a while to appear after the flag. TBC times are not yet published.")
                            .fixedSize(horizontal: false, vertical: true)
                        if let schedule = store.schedule {
                            Text(schedule.timesCaption(timeZoneIdentifier: timeZoneName))
                                .fixedSize(horizontal: false, vertical: true)
                            if let fetched = schedule.fetchedDate {
                                Label(fetched.formatted(date: .abbreviated, time: .shortened), systemImage: "arrow.clockwise")
                                    .accessibilityLabel("Calendar fetched \(fetched.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                    }
                    .font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
                    .padding(RacingStyle.Space.xl)
                }
                .frame(idealWidth: 320, maxWidth: 320, idealHeight: 300, maxHeight: 360)
                .presentationCompactAdaptation(.popover)
            }
            Button { refresh += 1 } label: {
                Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(RacingStyle.textSecondary)
            .disabled(store.loading).accessibilityLabel("Refresh calendar")
        }
    }

    /// The only note above the list: which zone the times are in and where the calendar comes from.
    @ViewBuilder private var caption: some View {
        if let schedule = store.schedule {
            Text(schedule.timesCaption(timeZoneIdentifier: timeZoneName))
                .font(RacingStyle.Typography.caption)
                .foregroundStyle(schedule.mode == "demo" ? Color(RacingPalette.statusDemo) : RacingStyle.textSecondary)
        } else {
            Text("Times in \(timeZoneName)").font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
        }
    }

    private func calendar(_ schedule: RaceSchedule, proxy: ScrollViewProxy) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let next = schedule.nextRace(at: now)?.round
            let races = schedule.races(matching: filter, at: now)
            VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                if store.calendarIsStale() && schedule.mode != "demo" {
                    Label("Saved schedule · May be out of date", systemImage: "clock.badge.exclamationmark")
                        .font(RacingStyle.Typography.caption).foregroundStyle(Color(RacingPalette.statusStale))
                }
                if races.isEmpty {
                    ContentUnavailableView("No \(filter == .all ? "scheduled" : filter.rawValue.lowercased()) races", systemImage: "calendar", description: Text("Choose another season or filter. Future calendars may not be published yet."))
                }
                ForEach(Array(races.enumerated()), id: \.element.round) { index, race in
                    let emphasis = WeekendEmphasis(race: race, nextRound: next, now: now)
                    VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                        if emphasis == .past && (index == 0 || !races[index - 1].isPast(at: now)) { completedHeader }
                        WeekendCard(race: race, emphasis: emphasis, now: now, endpoint: endpoint, season: schedule.season, results: results)
                    }.id(race.round)
                }
                if schedule.nextRace(at: now) == nil && !races.isEmpty { seasonComplete }
            }
            // Land on the next race (or the last one of a finished season), not on the oldest past row.
            .task(id: "\(schedule.season)|\(schedule.fetchedAt)|\(filter.rawValue)") {
                try? await Task.sleep(for: .milliseconds(120))
                switch schedule.calendarFocus(for: filter, at: Date()) {
                case .nextRace(let round), .seasonComplete(let round):
                    proxy.scrollTo(round, anchor: .top)
                case .top: proxy.scrollTo(Self.topID, anchor: .top)
                }
            }
        }
    }

    /// Past rows are quiet; this one header says why, so the rows do not each repeat "PAST".
    private var completedHeader: some View {
        Label("Completed", systemImage: "flag.checkered")
            .racingLabel().foregroundStyle(RacingStyle.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }

    private var seasonComplete: some View {
        Label("Season complete", systemImage: "flag.checkered")
            .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textTertiary)
            .frame(maxWidth: .infinity)
    }
}

private struct WeekendCard: View {
    let race: RaceWeekend
    let emphasis: WeekendEmphasis
    let now: Date
    let endpoint: String
    let season: Int
    let results: ResultsStore
    @State private var expanded: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    init(race: RaceWeekend, emphasis: WeekendEmphasis, now: Date, endpoint: String, season: Int, results: ResultsStore) {
        self.race = race
        self.emphasis = emphasis
        self.now = now
        self.endpoint = endpoint
        self.season = season
        self.results = results
        _expanded = State(initialValue: emphasis.startsExpanded)
    }

    private var isPast: Bool { emphasis == .past }
    /// Past weekends are visibly quieter: no white, lighter weight (see `row`).
    private var primary: Color { isPast ? RacingStyle.textSecondary : RacingStyle.textPrimary }
    private var secondary: Color { isPast ? RacingStyle.textTertiary : RacingStyle.textSecondary }
    private var dateRange: String? { race.dateRange() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                Group { emphasis == .next ? AnyView(hero) : AnyView(row) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(spokenSummary)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the sessions" : "Shows the sessions")
            if expanded {
                if isPast {
                    ResultsSection(race: race, phase: results.phases[race.round]) {
                        results.retry(round: race.round)
                        Task { await results.load(round: race.round, endpoint: endpoint, season: season) }
                    }
                }
                sessions
            }
        }
        // Results are fetched the first time a finished weekend is opened, not for the whole season up front.
        .task(id: expanded && isPast) {
            guard expanded && isPast else { return }
            await results.load(round: race.round, endpoint: endpoint, season: season)
        }
        .racingCard(emphasis == .next ? .regular : .compact)
        .overlay(alignment: .top) {
            if emphasis == .next { RacingStyle.red.frame(height: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: RacingStyle.Radius.card))
        // The card keeps its identity as the clock moves on: when a race becomes the next one it opens,
        // and when it passes it folds up, instead of keeping whatever state it was created with.
        .onChange(of: emphasis) { _, new in expanded = new.startsExpanded }
    }

    private var spokenSummary: String {
        var parts = ["Round \(race.round)", race.name, race.circuit]
        if let dateRange { parts.append(dateRange) }
        parts.append(emphasis == .next ? "Next race, \(race.countdownText(now: now))" : emphasis == .past ? "Past" : "Upcoming")
        return parts.joined(separator: ", ")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(RacingStyle.Typography.bodyStrong)
            // Tertiary for every row, so the chevron is never brighter than the title beside it.
            .foregroundStyle(RacingStyle.textTertiary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityHidden(true)
    }

    /// The next race: big title, countdown to lights out, open by default.
    private var hero: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.s) {
            // The chevron shares the badge row and is centred on it, like the chevron on every other row.
            HStack(alignment: .center, spacing: RacingStyle.Space.s) {
                // The badge and the round never break mid-word: when they do not fit side by side they stack.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: RacingStyle.Space.s) { badge; roundLabel(stacked: false) }
                    VStack(alignment: .leading, spacing: RacingStyle.Space.xs) { badge; roundLabel(stacked: false) }
                    VStack(alignment: .leading, spacing: RacingStyle.Space.xs) { badge; roundLabel(stacked: true) }
                }
                Spacer(minLength: RacingStyle.Space.s)
                chevron
            }
            // The chevron's 44pt hit area is taller than the badge; pull the row back up so the card keeps its rhythm.
            .padding(.vertical, -RacingStyle.Space.s)
            Text(race.name).font(RacingStyle.Typography.display).racingHeading().multilineTextAlignment(.leading)
            Text(race.circuit).font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline) { dates; Spacer(); countdown }
                VStack(alignment: .leading, spacing: RacingStyle.Space.s) { dates; countdown }
            }
        }
    }

    private var badge: some View {
        Text(emphasis.badge).font(RacingStyle.Typography.label).tracking(1).foregroundStyle(RacingStyle.onRed)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, RacingStyle.Space.s).padding(.vertical, RacingStyle.Space.xs)
            .background(RacingStyle.red, in: Capsule())
    }

    /// "Round 20 · Brazil" on one line; stacked ("Round 20" over "Brazil", no separator) when it does not fit.
    private func roundLabel(stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(race.roundLines(stacked: stacked), id: \.self) { Text($0).lineLimit(1).fixedSize() }
        }
        .racingLabel().foregroundStyle(RacingStyle.textSecondary)
    }

    @ViewBuilder private var dates: some View {
        if let dateRange {
            Label(dateRange, systemImage: "calendar").font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private var countdown: some View {
        Label(race.countdownText(now: now), systemImage: "flag.checkered")
            .font(RacingStyle.Typography.figure)
            .accessibilityLabel("Race starts \(race.countdownText(now: now))")
    }

    /// Everything that is not the next race: one compact row. At accessibility sizes the round number
    /// moves above the title so the title keeps the full width instead of breaking mid-word.
    @ViewBuilder private var row: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
                HStack { roundNumber; Spacer(minLength: RacingStyle.Space.s); chevron }
                rowTitle
                meta
            }
        } else {
            HStack(spacing: RacingStyle.Space.m) {
                roundNumber
                VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
                    rowTitle
                    meta
                }
                Spacer(minLength: RacingStyle.Space.s)
                chevron
            }
            .frame(minHeight: 44)
        }
    }

    private var roundNumber: some View {
        Text(String(format: "%02d", race.round))
            .font(isPast ? RacingStyle.Typography.figureQuiet : RacingStyle.Typography.figure)
            .foregroundStyle(isPast ? RacingStyle.textTertiary : primary)
    }

    private var rowTitle: some View {
        Text(race.name)
            .font(isPast ? RacingStyle.Typography.headlineQuiet : RacingStyle.Typography.headline)
            .foregroundStyle(primary).multilineTextAlignment(.leading)
    }

    /// Country and dates on one line; at very large text the dates drop to their own line, still unbroken.
    @ViewBuilder private var meta: some View {
        let joined = [race.country, dateRange].compactMap { $0 }.joined(separator: " · ")
        ViewThatFits(in: .horizontal) {
            Text(joined).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 0) {
                Text(race.country)
                if let dateRange { Text(dateRange).lineLimit(1).minimumScaleFactor(0.7) }
            }
        }
        .font(RacingStyle.Typography.caption).foregroundStyle(secondary)
    }

    private var sessions: some View {
        VStack(spacing: RacingStyle.Space.m) {
            Divider().overlay(RacingStyle.raised)
            ForEach(race.sessions) { session in
                // Name and time share a row when they fit; otherwise the time drops under the name
                // instead of breaking either word.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) { sessionName(session); Spacer(); sessionTime(session, alignment: .trailing) }
                    VStack(alignment: .leading, spacing: RacingStyle.Space.xs) { sessionName(session); sessionTime(session, alignment: .leading) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, RacingStyle.Space.s)
    }

    private func sessionName(_ session: ScheduledSession) -> some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
            Text(session.name).font(RacingStyle.Typography.bodyStrong).foregroundStyle(primary).fixedSize(horizontal: false, vertical: true)
            Text(session.localDate()).font(RacingStyle.Typography.caption).foregroundStyle(secondary)
        }
    }

    private func sessionTime(_ session: ScheduledSession, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: RacingStyle.Space.xs) {
            Text(session.localTime()).font(RacingStyle.Typography.data).foregroundStyle(primary).lineLimit(1).fixedSize()
            if let start = session.startDate, start <= now {
                Image(systemName: "clock.badge.checkmark").font(RacingStyle.Typography.caption).foregroundStyle(secondary).accessibilityLabel("Scheduled start has passed").help("Scheduled start has passed")
            }
        }
    }
}

/// The finishing order of a past race, shown above its sessions.
private struct ResultsSection: View {
    let race: RaceWeekend
    let phase: ResultsStore.Phase?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            Divider().overlay(RacingStyle.raised)
            Label("Results", systemImage: "flag.checkered")
                .racingLabel().foregroundStyle(RacingStyle.textSecondary)
                .accessibilityAddTraits(.isHeader)
            switch phase {
            case .loaded(let results): loaded(results)
            case .failed:
                HStack {
                    Text("Results unavailable").font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                    Spacer()
                    Button(action: retry) {
                        Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(RacingStyle.textSecondary)
                    .accessibilityLabel("Try loading results again")
                }
            case .loading, nil:
                ProgressView().accessibilityLabel("Loading results").frame(maxWidth: .infinity)
            }
        }
        .padding(.top, RacingStyle.Space.s)
    }

    @ViewBuilder private func loaded(_ results: RaceResults) -> some View {
        if results.entries.isEmpty {
            Text("Results not published yet").font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
        } else {
            VStack(spacing: RacingStyle.Space.m) {
                ForEach(results.entries) { ResultRow(entry: $0) }
            }
            if results.mode == "demo" {
                Text(results.source).font(RacingStyle.Typography.caption).foregroundStyle(Color(RacingPalette.statusDemo))
            } else if results.stale {
                Label("Saved results · May be out of date", systemImage: "clock.badge.exclamationmark")
                    .font(RacingStyle.Typography.caption).foregroundStyle(Color(RacingPalette.statusStale))
            } else {
                Text("Results from \(results.source)").font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textTertiary)
            }
        }
    }
}

private struct ResultRow: View {
    let entry: ResultEntry

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: RacingStyle.Space.m) {
                position
                driver
                Spacer(minLength: RacingStyle.Space.s)
                outcome(alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
                HStack(spacing: RacingStyle.Space.m) { position; driver }
                outcome(alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.spokenSummary)
    }

    private var position: some View {
        Text(entry.positionText)
            .font(RacingStyle.Typography.figure)
            .foregroundStyle(entry.isClassified ? RacingStyle.textPrimary : RacingStyle.textTertiary)
            .frame(minWidth: 36, alignment: .leading).lineLimit(1)
    }

    private var driver: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: RacingStyle.Space.xs) {
                Text(entry.name).font(RacingStyle.Typography.bodyStrong).foregroundStyle(RacingStyle.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.fastestLap {
                    Image(systemName: "stopwatch").font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                }
            }
            Text(entry.team).font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
        }
    }

    private func outcome(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(entry.outcome).font(RacingStyle.Typography.data).foregroundStyle(RacingStyle.textPrimary).lineLimit(1).fixedSize()
            if let points = entry.pointsText {
                Text("\(points) pts").font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
            }
        }
    }
}
