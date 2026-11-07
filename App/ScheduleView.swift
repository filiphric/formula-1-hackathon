import SwiftUI

struct ScheduleView: View {
    let endpoint: String
    @State private var store = ScheduleStore()
    @State private var season = Calendar.current.component(.year, from: .now)
    @State private var filter = "All"
    @State private var refresh = 0
    private let currentYear = Calendar.current.component(.year, from: .now)
    private var timeZoneName: String { TimeZone.autoupdatingCurrent.identifier }

    var body: some View {
        ScrollView {
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
                    ForEach(["All", "Upcoming", "Past"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                caption
                if store.loading { ProgressView("Loading season…").frame(maxWidth: .infinity).padding(RacingStyle.Space.xl) }
                if let error = store.error {
                    ContentUnavailableView {
                        Label("Schedule unavailable", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try again") { refresh += 1 }
                    }
                }
                if let schedule = store.schedule {
                    calendar(schedule)
                }
            }
            .racingPagePadding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(RacingStyle.background)
        .task(id: "\(endpoint)|\(season)|\(refresh)") {
            await store.load(endpoint: endpoint, season: season)
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

    private func calendar(_ schedule: RaceSchedule) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let next = schedule.nextRace(at: now)?.round
            let races = schedule.races.filter {
                filter == "All" || (filter == "Past" ? $0.isPast(at: now) : !$0.isPast(at: now))
            }
            VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                if schedule.isStale(at: now) && schedule.mode != "demo" {
                    Label("Saved schedule · May be out of date. Refresh to check for changes.", systemImage: "clock.badge.exclamationmark")
                        .font(RacingStyle.Typography.caption).foregroundStyle(Color(RacingPalette.statusStale))
                }
                if races.isEmpty {
                    ContentUnavailableView("No \(filter == "All" ? "scheduled" : filter.lowercased()) races", systemImage: "calendar", description: Text("Choose another season or filter. Future calendars may not be published yet."))
                }
                ForEach(races) { race in
                    WeekendCard(race: race, emphasis: WeekendEmphasis(race: race, nextRound: next, now: now), now: now)
                }
                footer(schedule)
            }
        }
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
    private var primary: Color { isPast ? RacingStyle.textTertiary : RacingStyle.textPrimary }
    private var secondary: Color { isPast ? RacingStyle.textTertiary : RacingStyle.textSecondary }
    private var dateRange: String? {
        guard let first = race.sessions.first, let last = race.sessions.last else { return nil }
        return first.localDate() == last.localDate() ? first.localDate() : "\(first.localDate()) – \(last.localDate())"
    }

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
            HStack(alignment: .lastTextBaseline) {
                if let dateRange {
                    Label(dateRange, systemImage: "calendar").font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: RacingStyle.Space.xs) {
                    Text("Race start").racingLabel().foregroundStyle(RacingStyle.textSecondary)
                    Text(race.countdownText(now: now)).font(RacingStyle.Typography.figure)
                }
            }
        }
    }

    /// Everything that is not the next race: one compact row.
    private var row: some View {
        HStack(spacing: RacingStyle.Space.m) {
            Text(String(format: "%02d", race.round)).font(RacingStyle.Typography.figure).foregroundStyle(primary)
            VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
                Text(race.name).font(RacingStyle.Typography.headline).foregroundStyle(primary).multilineTextAlignment(.leading)
                Text([race.country, dateRange].compactMap { $0 }.joined(separator: " · "))
                    .font(RacingStyle.Typography.caption).foregroundStyle(secondary)
            }
            Spacer(minLength: RacingStyle.Space.s)
            if isPast { Text(emphasis.badge).racingLabel().foregroundStyle(RacingStyle.textTertiary) }
            chevron
        }
        .frame(minHeight: 44)
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
