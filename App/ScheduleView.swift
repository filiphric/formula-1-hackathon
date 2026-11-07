import SwiftUI

struct ScheduleView: View {
    let endpoint: String
    @State private var store = ScheduleStore()
    @State private var season = Calendar.current.component(.year, from: .now)
    @State private var filter = ScheduleFilter.all
    /// The season the filter was last defaulted for, so a refresh keeps the filter the user picked.
    @State private var defaultedFor = ""
    @State private var refresh = 0
    private let currentYear = Calendar.current.component(.year, from: .now)
    private var timeZoneName: String { TimeZone.autoupdatingCurrent.identifier }

    var body: some View {
        ScrollViewReader { proxy in
            page(proxy)
        }
    }

    private func page(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            // The controls stay put while the list scrolls, so jumping to the next race never hides them.
            header
                .racingPagePadding([.horizontal, .top])
                .padding(.bottom, RacingStyle.Space.s)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            ScrollView {
                VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                    if store.loading { ProgressView("Loading season…").frame(maxWidth: .infinity).padding(RacingStyle.Space.xl) }
                    if let error = store.error {
                        ContentUnavailableView {
                            Label("Schedule unavailable", systemImage: "wifi.exclamationmark")
                        } description: { Text(error) } actions: {
                            Button("Try again") { refresh += 1 }
                        }
                    }
                    if let schedule = store.schedule {
                        calendar(schedule, proxy: proxy)
                    }
                }
                .id(Self.topID)
                .racingPagePadding([.horizontal, .bottom])
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .background(RacingStyle.background)
        .task(id: "\(endpoint)|\(season)|\(refresh)") {
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

    private var header: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            HStack(spacing: RacingStyle.Space.s) {
                Text("Calendar").font(RacingStyle.Typography.display).racingHeading()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker("Season", selection: $season) {
                    ForEach(Array((2023...max(2023, currentYear + 1)).reversed()), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }.labelsHidden().fixedSize()
                Button { refresh += 1 } label: {
                    Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(RacingStyle.textSecondary)
                .disabled(store.loading).accessibilityLabel("Refresh calendar")
            }
            Picker("Show races", selection: $filter) {
                ForEach(ScheduleFilter.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            caption
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
                if schedule.isStale(at: now) && schedule.mode != "demo" {
                    Label("Saved schedule · May be out of date. Refresh to check for changes.", systemImage: "clock.badge.exclamationmark")
                        .font(RacingStyle.Typography.caption).foregroundStyle(Color(RacingPalette.statusStale))
                }
                if races.isEmpty {
                    ContentUnavailableView("No \(filter == .all ? "scheduled" : filter.rawValue.lowercased()) races", systemImage: "calendar", description: Text("Choose another season or filter. Future calendars may not be published yet."))
                }
                ForEach(Array(races.enumerated()), id: \.element.round) { index, race in
                    let emphasis = WeekendEmphasis(race: race, nextRound: next, now: now)
                    VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                        if emphasis == .past && (index == 0 || !races[index - 1].isPast(at: now)) { completedHeader }
                        WeekendCard(race: race, emphasis: emphasis, now: now)
                    }.id(race.round)
                }
                if schedule.nextRace(at: now) == nil && !races.isEmpty { seasonComplete }
                footer(schedule)
            }
            // Land on the next race (or the last one of a finished season), not on the oldest past row.
            .task(id: "\(schedule.season)|\(schedule.fetchedAt)|\(filter.rawValue)") {
                try? await Task.sleep(for: .milliseconds(120))
                switch schedule.calendarFocus(for: filter, at: Date()) {
                case .nextRace(let round), .seasonComplete(let round): proxy.scrollTo(round, anchor: .top)
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

    /// One quiet line: what "past" and "TBC" mean, and when the calendar was fetched.
    private func footer(_ schedule: RaceSchedule) -> some View {
        let fetched = schedule.fetchedDate.map { " Fetched \($0.formatted(date: .abbreviated, time: .shortened))." } ?? ""
        return Text("Past means the scheduled race start has passed; results are not tracked. TBC times are not yet published.\(fetched)")
            .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textTertiary)
    }
}

private struct WeekendCard: View {
    let race: RaceWeekend
    let emphasis: WeekendEmphasis
    let now: Date
    @State private var expanded: Bool

    init(race: RaceWeekend, emphasis: WeekendEmphasis, now: Date) {
        self.race = race
        self.emphasis = emphasis
        self.now = now
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
            if expanded { sessions }
        }
        .racingCard(emphasis == .next ? .regular : .compact)
        .overlay(alignment: .top) {
            if emphasis == .next { RacingStyle.red.frame(height: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: RacingStyle.Radius.card))
    }

    private var spokenSummary: String {
        var parts = ["Round \(race.round)", race.name, race.circuit]
        if let dateRange { parts.append(dateRange) }
        parts.append(emphasis == .next ? "Next race, \(race.countdownText(now: now))" : emphasis == .past ? "Past" : "Upcoming")
        return parts.joined(separator: ", ")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(RacingStyle.Typography.bodyStrong).foregroundStyle(secondary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityHidden(true)
    }

    /// The next race: big title, countdown to lights out, open by default.
    private var hero: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.s) {
            HStack(spacing: RacingStyle.Space.s) {
                Text(emphasis.badge).font(RacingStyle.Typography.label).tracking(1).foregroundStyle(RacingStyle.onRed)
                    .padding(.horizontal, RacingStyle.Space.s).padding(.vertical, RacingStyle.Space.xs)
                    .background(RacingStyle.red, in: Capsule())
                Text("Round \(race.round) · \(race.country)").racingLabel().foregroundStyle(RacingStyle.textSecondary)
                Spacer()
                chevron
            }
            Text(race.name).font(RacingStyle.Typography.display).racingHeading().multilineTextAlignment(.leading)
            Text(race.circuit).font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline) { dates; Spacer(); countdown }
                VStack(alignment: .leading, spacing: RacingStyle.Space.s) { dates; countdown }
            }
        }
    }

    @ViewBuilder private var dates: some View {
        if let dateRange {
            Label(dateRange, systemImage: "calendar").font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
            Text("Race start").racingLabel().foregroundStyle(RacingStyle.textSecondary)
            Text(race.countdownText(now: now)).font(RacingStyle.Typography.figure)
        }
    }

    /// Everything that is not the next race: one compact row.
    private var row: some View {
        HStack(spacing: RacingStyle.Space.m) {
            Text(String(format: "%02d", race.round))
                .font(isPast ? RacingStyle.Typography.figureQuiet : RacingStyle.Typography.figure)
                .foregroundStyle(isPast ? RacingStyle.textTertiary : primary)
            VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
                Text(race.name)
                    .font(isPast ? RacingStyle.Typography.headlineQuiet : RacingStyle.Typography.headline)
                    .foregroundStyle(primary).multilineTextAlignment(.leading)
                meta
            }
            Spacer(minLength: RacingStyle.Space.s)
            chevron
        }
        .frame(minHeight: 44)
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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
                        Text(session.name).font(RacingStyle.Typography.bodyStrong).foregroundStyle(primary)
                        Text(session.localDate()).font(RacingStyle.Typography.caption).foregroundStyle(secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: RacingStyle.Space.xs) {
                        Text(session.localTime()).font(RacingStyle.Typography.data).foregroundStyle(primary)
                        if let start = session.startDate, start <= now {
                            Text("Started").font(RacingStyle.Typography.caption).foregroundStyle(secondary)
                        }
                    }
                }.accessibilityElement(children: .combine)
            }
        }
        .padding(.top, RacingStyle.Space.s)
    }
}
