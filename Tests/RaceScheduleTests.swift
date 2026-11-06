import Foundation
import Testing
@testable import FormulaCore

private func fixture() throws -> RaceSchedule {
    let url = Bundle.module.url(forResource: "schedule", withExtension: "json", subdirectory: "Fixtures")!
    return try JSONDecoder().decode(RaceSchedule.self, from: Data(contentsOf: url))
}

private func instant(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}

@Test func calendarContractIncludesStandardAndSprintWeekends() throws {
    let schedule = try fixture()
    #expect(schedule.races.count == 2)
    #expect(schedule.races[0].sessions.map(\.name) == ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"])
    #expect(schedule.races[1].sessions.map(\.name) == ["Practice 1", "Sprint qualifying", "Sprint", "Qualifying", "Race"])
    #expect(schedule.source == "Jolpica F1")
    #expect(!schedule.stale)
}

@Test func localTimezoneChangesDayAndRespectsDaylightSaving() throws {
    let schedule = try fixture()
    let bratislava = TimeZone(identifier: "Europe/Bratislava")!
    let la = TimeZone(identifier: "America/Los_Angeles")!
    let locale = Locale(identifier: "en_GB")
    let practice = schedule.races[0].sessions[0]
    #expect(practice.localDate(timeZone: bratislava, locale: locale) == "Sat 28 Mar")
    #expect(practice.localTime(timeZone: bratislava, locale: locale) == "00:30")
    #expect(practice.localDate(timeZone: la, locale: locale) == "Fri 27 Mar")
    #expect(practice.localTime(timeZone: la, locale: locale) == "16:30")
    let race = schedule.races[0].sessions.last!
    // Europe changes to summer time on March 29, so this is UTC + 2.
    #expect(race.localTime(timeZone: bratislava, locale: locale) == "16:00")
}

@Test func pastAndNextUseRaceInstantRatherThanPracticeOrUTCDate() throws {
    let schedule = try fixture()
    #expect(schedule.nextRace(at: instant("2026-03-28T18:00:00Z"))?.round == 1)
    #expect(!schedule.races[0].isPast(at: instant("2026-03-29T13:59:59Z")))
    #expect(schedule.races[0].isPast(at: instant("2026-03-29T14:00:00Z")))
    #expect(schedule.nextRace(at: instant("2026-03-29T14:00:00Z"))?.round == 2)
    #expect(schedule.nextRace(at: instant("2026-12-01T00:00:00Z")) == nil)
}

@Test func unpublishedTimeStaysTBCAndDateIsNotShifted() throws {
    let race = RaceWeekend(round: 1, name: "Sample", circuit: "Sample", country: "Sample", sessions: [
        ScheduledSession(name: "Race", date: "2026-03-29", start: nil)
    ])
    let la = TimeZone(identifier: "America/Los_Angeles")!
    #expect(race.sessions[0].localTime(timeZone: la) == "Time TBC")
    #expect(race.sessions[0].localDate(timeZone: la, locale: Locale(identifier: "en_GB")) == "Sun 29 Mar")
    #expect(!race.isPast(at: instant("2026-03-30T06:59:59Z"), timeZone: la))
    #expect(race.isPast(at: instant("2026-03-30T07:00:00Z"), timeZone: la))
}

@Test func calendarEndpointKeepsHostAndTLSWithoutTimingQuery() {
    #expect(RaceSchedule.endpoint(from: "wss://example.com:9443/live?token=private#live", season: 2026)?.absoluteString == "https://example.com:9443/schedule/2026")
    #expect(RaceSchedule.endpoint(from: "ws://localhost:8787/live", season: 2025)?.absoluteString == "http://localhost:8787/schedule/2025")
    #expect(RaceSchedule.endpoint(from: "https://example.com", season: 2026) == nil)
    #expect(RaceSchedule.endpoint(from: "ws://user:password@example.com/live", season: 2026) == nil)
}

@Test func backendFractionalFetchTimestampControlsFreshness() throws {
    let schedule = try fixture()
    let fetched = try #require(schedule.fetchedDate)
    #expect(abs(fetched.timeIntervalSince(instant("2026-11-06T15:00:00Z")) - 0.123456) < 0.001)
    #expect(!schedule.isStale(at: fetched.addingTimeInterval(899)))
    #expect(schedule.isStale(at: fetched.addingTimeInterval(900)))
}

@Test func seasonsMatchBackendUTCYearAroundNewYear() {
    // Already January 1 in Bratislava, but the server still accepts through 2027.
    let before = instant("2026-12-31T23:30:00Z")
    #expect(RaceSchedule.currentSeason(at: before) == 2026)
    #expect(RaceSchedule.availableSeasons(at: before) == [2027, 2026, 2025, 2024, 2023])
    let after = instant("2027-01-01T00:00:00Z")
    #expect(RaceSchedule.currentSeason(at: after) == 2027)
    #expect(RaceSchedule.availableSeasons(at: after).first == 2028)
}

@Test func scheduleEndpointPreservesDeploymentPrefix() {
    #expect(RaceSchedule.endpoint(from: "wss://example.com/formula/live", season: 2026)?.absoluteString == "https://example.com/formula/schedule/2026")
    #expect(RaceSchedule.endpoint(from: "wss://example.com/a%20b/live/?old=1", season: 2025)?.absoluteString == "https://example.com/a%20b/schedule/2025")
}

@Test func editingServerDoesNotChangeConfirmedConnection() {
    var connection = ServerConnection(endpoint: "ws://first.example/live")
    connection.beginEditing()
    connection.draftEndpoint = "ws://partial"
    #expect(connection.activeEndpoint == "ws://first.example/live")
    connection.beginEditing() // Reopening a dismissed sheet discards its abandoned draft.
    #expect(connection.draftEndpoint == "ws://first.example/live")
    connection.draftEndpoint = "  wss://second.example/formula/live  "
    connection.connect()
    #expect(connection.activeEndpoint == "wss://second.example/formula/live")
}

@Test func rescheduledRaceUsesDateInsteadOfRoundForNextRace() throws {
    let original = try fixture()
    let postponed = RaceWeekend(round: 1, name: "Postponed Grand Prix", circuit: "Sample", country: "Sample", sessions: [
        ScheduledSession(name: "Race", date: "2026-12-01", start: "2026-12-01T14:00:00Z")
    ])
    let schedule = RaceSchedule(season: 2026, mode: "calendar", source: "Sample", fetchedAt: original.fetchedAt,
                                stale: false, races: [postponed, original.races[1]])
    #expect(schedule.nextRace(at: instant("2026-11-01T00:00:00Z"))?.round == 2)
}
