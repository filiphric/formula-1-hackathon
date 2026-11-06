import SwiftUI

struct ScheduleView: View {
    let endpoint: String
    @State private var store = ScheduleStore()
    @State private var season = Calendar.current.component(.year, from: .now)
    @State private var filter = "All"
    @State private var refresh = 0
    private let currentYear = Calendar.current.component(.year, from: .now)
    private let accent = Color(red: 1, green: 0.22, blue: 0.18)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("THE SEASON").font(.caption.bold()).tracking(3).foregroundStyle(accent)
                        Spacer()
                        Picker("Season", selection: $season) {
                            ForEach(Array((2023...max(2023, currentYear + 1)).reversed()), id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }.labelsHidden().fixedSize()
                    }
                    Text("Every weekend.\nYour local time.").font(.largeTitle.bold())
                    Label("Times in \(TimeZone.autoupdatingCurrent.identifier)", systemImage: "globe")
                        .font(.callout).foregroundStyle(.secondary)
                    Picker("Show races", selection: $filter) {
                        ForEach(["All", "Upcoming", "Past"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented)
                    if store.loading { ProgressView("Loading season…").frame(maxWidth: .infinity).padding(40) }
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
                }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.045, green: 0.05, blue: 0.065))
            .navigationTitle("Schedule")
            .toolbar {
                Button("Refresh", systemImage: "arrow.clockwise") { refresh += 1 }.disabled(store.loading)
            }
            .task(id: "\(endpoint)|\(season)|\(refresh)") {
                await store.load(endpoint: endpoint, season: season)
            }
        }
    }

    private func calendar(_ schedule: RaceSchedule) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let next = schedule.nextRace(at: now)?.id
            let races = schedule.races.filter {
                filter == "All" || (filter == "Past" ? $0.isPast(at: now) : !$0.isPast(at: now))
            }
            VStack(alignment: .leading, spacing: 16) {
                if schedule.mode == "demo" {
                    Label("DEMO · Fictional sample weekends", systemImage: "info.circle")
                        .font(.callout.bold()).foregroundStyle(.orange)
                } else {
                    Text("\(schedule.source) · Calendar data, subject to change")
                        .font(.caption).foregroundStyle(.secondary)
                }
                let fetched = schedule.fetchedDate
                let stale = schedule.isStale(at: now)
                if stale && schedule.mode != "demo" {
                    Label("Saved schedule · May be out of date. Refresh to check for changes.", systemImage: "clock.badge.exclamationmark")
                        .font(.callout).foregroundStyle(.orange)
                }
                if let fetched {
                    Text("Fetched \(fetched.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if races.isEmpty {
                    ContentUnavailableView("No \(filter == "All" ? "scheduled" : filter.lowercased()) races", systemImage: "calendar", description: Text("Choose another season or filter. Future calendars may not be published yet."))
                }
                ForEach(races) { race in
                    WeekendCard(race: race, next: race.id == next, now: now)
                }
                Text("Past means the scheduled race start has passed; results and completion are not tracked here. Times marked TBC are not yet published.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WeekendCard: View {
    let race: RaceWeekend
    let next: Bool
    let now: Date
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 14) {
                ForEach(race.sessions) { session in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.name).font(.headline)
                            Text(session.localDate()).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(session.localTime()).font(.headline.monospacedDigit())
                            if let start = session.startDate, start <= now {
                                Text("Started").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.accessibilityElement(children: .combine)
                    if session.id != race.sessions.last?.id { Divider() }
                }
            }.padding(.top, 18)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ROUND \(race.round) · \(race.country.uppercased())").font(.caption.bold())
                    Spacer()
                    Text(race.isPast(at: now) ? "PAST" : next ? "NEXT RACE" : "UPCOMING")
                        .font(.caption.bold()).foregroundStyle(next ? .red : .secondary)
                }
                Text(race.name).font(.title2.bold())
                Text(race.circuit).font(.subheadline).foregroundStyle(.secondary)
                if let first = race.sessions.first, let last = race.sessions.last {
                    Label("\(first.localDate()) – \(last.localDate())", systemImage: "calendar")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.padding(.trailing, 8)
        }
        .tint(.white)
        .padding(20)
        .background(.white.opacity(next ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(next ? .red.opacity(0.7) : .clear))
        .onAppear { if next { expanded = true } }
    }
}
