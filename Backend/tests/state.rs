use formula_live_backend::state::{Session, TimingState};
use serde_json::json;

fn state() -> TimingState {
    let mut state = TimingState::new("live");
    state.set_session(Session {
        session_key: 42,
        session_name: "Race".into(),
        circuit_short_name: "Monza".into(),
        date_start: "2026-09-01T12:00:00Z".into(),
        date_end: "2026-09-01T14:00:00Z".into(),
    });
    state.apply(
        "drivers",
        json!({"session_key":42,"driver_number":4,"full_name":"Lando Norris","name_acronym":"NOR"}),
    );
    state
}

#[test]
fn rejects_old_positions_and_other_sessions() {
    let mut state = state();
    state.apply(
        "position",
        json!({"session_key":42,"driver_number":4,"date":"2026-09-01T12:00:00Z","position":2}),
    );
    // This timestamp looks later as text, but is actually earlier in UTC.
    state.apply("position", json!({"session_key":42,"driver_number":4,"date":"2026-09-01T13:59:00+02:00","position":10}));
    state.apply(
        "position",
        json!({"session_key":1,"driver_number":4,"date":"2026-09-01T12:01:00Z","position":9}),
    );
    assert_eq!(state.snapshot().drivers[0].position, Some(2));
    let mut next = state.session.clone().unwrap();
    next.session_key = 43;
    state.set_session(next);
    assert!(state.snapshot().drivers.is_empty());
    assert!(state.snapshot().updated_at.is_none());
}

#[test]
fn merges_lap_corrections_and_rejects_previous_laps_and_document_versions() {
    let mut state = state();
    state.apply(
        "laps",
        json!({"session_key":42,"driver_number":4,"lap_number":12,"lap_duration":null,"_id":100}),
    );
    state.apply(
        "laps",
        json!({"session_key":42,"driver_number":4,"lap_number":12,"lap_duration":91.333,"_id":102}),
    );
    state.apply(
        "laps",
        json!({"session_key":42,"driver_number":4,"lap_number":12,"lap_duration":95,"_id":101}),
    );
    state.apply(
        "laps",
        json!({"session_key":42,"driver_number":4,"lap_number":11,"lap_duration":95,"_id":103}),
    );
    assert_eq!(state.snapshot().drivers[0].lap, Some(12));
    assert_eq!(state.snapshot().drivers[0].lap_time, Some(91.333));
}

#[test]
fn accepts_numeric_lapped_and_null_gaps() {
    let mut state = state();
    for (gap, expected) in [
        (json!(2.431), Some("+2.431")),
        (json!("+1 LAP"), Some("+1 LAP")),
        (json!(null), None),
    ] {
        state.apply(
            "intervals",
            json!({"session_key":42,"driver_number":4,"gap_to_leader":gap}),
        );
        assert_eq!(state.snapshot().drivers[0].gap.as_deref(), expected);
    }
}

#[test]
fn deduplicates_and_bounds_race_control_history() {
    let mut state = state();
    for i in 0..110 {
        let date = chrono::DateTime::from_timestamp(1_780_000_000 + i, 0)
            .unwrap()
            .to_rfc3339();
        let record = json!({"session_key":42,"date":date,"message":format!("Flag {i}")});
        state.apply("race_control", record.clone());
        state.apply("race_control", record);
    }
    assert_eq!(state.snapshot().messages.len(), 100);
    assert_eq!(state.snapshot().messages[0].message, "Flag 109");
}

#[test]
fn normalized_snapshot_keeps_swift_keys_and_explicit_null_values() {
    let state = state();
    let value = serde_json::to_value(state.snapshot()).unwrap();
    assert!(value.get("updatedAt").is_some());
    assert!(value.get("updated_at").is_none());
    let driver = &value["drivers"][0];
    assert_eq!(driver["number"], 4);
    assert!(driver
        .get("lapTime")
        .is_some_and(serde_json::Value::is_null));
    assert!(driver.get("gap").is_some_and(serde_json::Value::is_null));
    assert!(driver
        .get("interval")
        .is_some_and(serde_json::Value::is_null));
    assert!(driver
        .get("bestLap")
        .is_some_and(serde_json::Value::is_null));
}

#[test]
fn interval_to_car_ahead_is_kept_apart_from_gap_to_leader() {
    let mut state = state();
    // Third on the road: 7.5 s behind the leader, but only 1.25 s behind the car in front.
    state.apply(
        "intervals",
        json!({"session_key":42,"driver_number":4,"gap_to_leader":7.5,"interval":1.25}),
    );
    let driver = state.snapshot().drivers.remove(0);
    assert_eq!(driver.gap.as_deref(), Some("+7.500"));
    assert_eq!(driver.interval.as_deref(), Some("+1.250"));
    // A lapped car reports text, and the leader reports no interval at all.
    state.apply(
        "intervals",
        json!({"session_key":42,"driver_number":4,"gap_to_leader":"+1 LAP","interval":"+1 LAP"}),
    );
    let driver = state.snapshot().drivers.remove(0);
    assert_eq!(driver.interval.as_deref(), Some("+1 LAP"));
    state.apply(
        "intervals",
        json!({"session_key":42,"driver_number":4,"gap_to_leader":null,"interval":null}),
    );
    assert_eq!(state.snapshot().drivers[0].interval, None);
}

fn lap(state: &mut TimingState, number: i64, duration: serde_json::Value, id: Option<i64>) {
    let mut record =
        json!({"session_key":42,"driver_number":4,"lap_number":number,"lap_duration":duration});
    if let Some(id) = id {
        record["_id"] = json!(id);
    }
    state.apply("laps", record);
}

#[test]
fn best_lap_is_the_quickest_completed_lap_not_the_latest() {
    let mut state = state();
    assert_eq!(state.snapshot().drivers[0].best_lap, None);
    lap(&mut state, 1, json!(95.0), Some(1));
    lap(&mut state, 2, json!(90.5), Some(2));
    lap(&mut state, 3, json!(91.3), Some(3));
    let driver = state.snapshot().drivers.remove(0);
    assert_eq!(driver.lap_time, Some(91.3));
    assert_eq!(driver.best_lap, Some(90.5));
    // A slower lap, an unfinished lap and nonsense durations never change it.
    lap(&mut state, 4, json!(99.0), Some(4));
    lap(&mut state, 5, json!(null), Some(5));
    lap(&mut state, 6, json!(0), Some(6));
    lap(&mut state, 7, json!(-3.0), Some(7));
    assert_eq!(state.snapshot().drivers[0].best_lap, Some(90.5));
    lap(&mut state, 8, json!(89.9), Some(8));
    assert_eq!(state.snapshot().drivers[0].best_lap, Some(89.9));
}

#[test]
fn best_lap_counts_a_result_that_arrives_after_the_next_lap_started() {
    let mut state = state();
    lap(&mut state, 5, json!(null), Some(10));
    // Lap 6 has begun when lap 5's time finally arrives: the lap record rejects it as stale,
    // but it was still the fastest lap.
    lap(&mut state, 6, json!(null), Some(11));
    lap(&mut state, 5, json!(88.8), Some(12));
    let driver = state.snapshot().drivers.remove(0);
    assert_eq!(driver.lap, Some(6));
    assert_eq!(driver.best_lap, Some(88.8));
}

#[test]
fn best_lap_follows_corrections_and_ignores_older_revisions_and_rest_copies() {
    let mut state = state();
    lap(&mut state, 3, json!(90.0), Some(20));
    // A newer revision corrects the lap, even to a slower time (a deleted fast lap).
    lap(&mut state, 3, json!(93.0), Some(21));
    assert_eq!(state.snapshot().drivers[0].best_lap, Some(93.0));
    // An older revision, and a REST copy without a revision, do not undo the correction.
    lap(&mut state, 3, json!(90.0), Some(19));
    lap(&mut state, 3, json!(90.0), None);
    assert_eq!(state.snapshot().drivers[0].best_lap, Some(93.0));
}

#[test]
fn best_lap_is_per_driver_and_cleared_when_the_session_changes() {
    let mut state = state();
    state.apply(
        "drivers",
        json!({"session_key":42,"driver_number":16,"full_name":"Charles Leclerc","name_acronym":"LEC"}),
    );
    lap(&mut state, 1, json!(92.0), Some(1));
    state.apply(
        "laps",
        json!({"session_key":42,"driver_number":16,"lap_number":1,"lap_duration":90.0,"_id":2}),
    );
    let drivers = state.snapshot().drivers;
    let best = |number: i64| {
        drivers
            .iter()
            .find(|d| d.number == number)
            .unwrap()
            .best_lap
    };
    assert_eq!(best(4), Some(92.0));
    assert_eq!(best(16), Some(90.0));
    let mut next = state.session.clone().unwrap();
    next.session_key = 43;
    state.set_session(next.clone());
    state.apply(
        "drivers",
        json!({"session_key":43,"driver_number":4,"full_name":"Lando Norris","name_acronym":"NOR"}),
    );
    assert_eq!(state.snapshot().drivers[0].best_lap, None);
}

#[test]
fn rest_bootstrap_does_not_overwrite_live_lap_corrections() {
    let mut state = state();
    state.apply(
        "laps",
        json!({"session_key":42,"driver_number":4,"lap_number":12,"lap_duration":91.333,"_id":102}),
    );
    state.apply(
        "laps",
        json!({"session_key":42,"driver_number":4,"lap_number":12,"lap_duration":null}),
    );
    assert_eq!(state.snapshot().drivers[0].lap_time, Some(91.333));
    // A later lap from a resync must still supersede the previous lap.
    state.apply(
        "laps",
        json!({"session_key":42,"driver_number":4,"lap_number":13,"lap_duration":92.5}),
    );
    assert_eq!(state.snapshot().drivers[0].lap_time, Some(92.5));
}

#[test]
fn locations_are_timestamped_ordered_validated_and_session_scoped() {
    let mut state = state();
    let sample = |date: &str, x: i64, y: i64| json!({"session_key":42,"driver_number":4,"date":date,"x":x,"y":y});
    state.apply("location", sample("2026-11-06T12:00:02Z", 300, -100));
    state.apply("location", sample("2026-11-06T12:00:01Z", 200, -200));
    state.apply("location", json!({"session_key":42,"driver_number":4,"date":"2026-11-06T12:00:01Z","x":700,"y":700,"_id":99999}));
    let snapshot = state.snapshot();
    let location = snapshot.drivers[0].location.as_ref().unwrap();
    assert_eq!((location.x, location.y), (300.0, -100.0));
    assert_eq!(location.date, "2026-11-06T12:00:02Z");
    state.apply("location", sample("2026-11-06T12:00:03Z", 0, 0));
    state.apply("location", sample("invalid", 500, 500));
    state.apply(
        "location",
        json!({"session_key":99,"driver_number":4,"date":"2026-11-06T12:00:04Z","x":900,"y":900}),
    );
    state.apply(
        "location",
        json!({"session_key":42,"driver_number":4,"date":"2026-11-06T12:00:04Z","x":900}),
    );
    assert_eq!(
        state.snapshot().drivers[0].location.as_ref().unwrap().x,
        300.0
    );
    state.track = Some(formula_live_backend::state::TrackLayout {
        rotation_degrees: None,
        source: "test".into(),
        points: vec![],
    });
    state.set_session(Session {
        session_key: 43,
        session_name: "Qualifying".into(),
        circuit_short_name: "Other circuit".into(),
        date_start: "".into(),
        date_end: "".into(),
    });
    assert!(state.snapshot().track.is_none());
    assert!(state.snapshot().drivers.is_empty());
}

#[test]
fn location_contract_is_additive_and_demo_positions_move_on_its_layout() {
    let demo = TimingState::demo();
    let first = demo.snapshot();
    assert_eq!(first.track.as_ref().unwrap().points.len(), 181);
    assert!(first.track.as_ref().unwrap().source.contains("Fictional"));
    for driver in &first.drivers {
        let location = driver.location.as_ref().unwrap();
        assert!(location.x.abs() <= 3750.0);
        assert!(location.y.abs() <= 2200.0);
        assert!(chrono::DateTime::parse_from_rfc3339(&location.date).is_ok());
    }
    let mut legacy = serde_json::to_value(first).unwrap();
    legacy.as_object_mut().unwrap().remove("track");
    for driver in legacy["drivers"].as_array_mut().unwrap() {
        driver.as_object_mut().unwrap().remove("location");
    }
    let decoded: formula_live_backend::state::Snapshot = serde_json::from_value(legacy).unwrap();
    assert!(decoded.track.is_none());
    assert!(decoded.drivers.iter().all(|d| d.location.is_none()));
}

#[test]
fn locations_do_not_hide_a_stalled_timing_feed() {
    let mut state = state();
    state.apply(
        "position",
        json!({"session_key":42,"driver_number":4,"position":1,"date":"2026-11-06T12:00:00Z"}),
    );
    state.apply(
        "location",
        json!({"session_key":42,"driver_number":4,"x":300,"y":400,"date":"2026-11-06T12:01:00Z"}),
    );
    let snapshot = state.snapshot();
    assert_eq!(snapshot.updated_at.as_deref(), Some("2026-11-06T12:00:00Z"));
    assert_eq!(
        snapshot.drivers[0].location.as_ref().unwrap().date,
        "2026-11-06T12:01:00Z"
    );
}

fn radio(i: i64, driver: i64, url: &str) -> serde_json::Value {
    let date = chrono::DateTime::from_timestamp(1_780_000_000 + i, 0)
        .unwrap()
        .to_rfc3339();
    json!({"session_key":42,"date":date,"driver_number":driver,"recording_url":url})
}

#[test]
fn team_radio_is_listed_newest_first_with_swift_keys() {
    let mut state = state();
    state.apply("team_radio", radio(1, 4, "https://example.com/a.mp3"));
    state.apply("team_radio", radio(3, 16, "https://example.com/c.mp3"));
    state.apply("team_radio", radio(2, 4, "https://example.com/b.mp3"));
    // The same clip arriving twice (REST bootstrap plus stream) is one entry.
    state.apply("team_radio", radio(2, 4, "https://example.com/b.mp3"));
    let value = serde_json::to_value(state.snapshot()).unwrap();
    let urls: Vec<_> = value["radios"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["recordingUrl"].as_str().unwrap())
        .collect();
    assert_eq!(
        urls,
        [
            "https://example.com/c.mp3",
            "https://example.com/b.mp3",
            "https://example.com/a.mp3"
        ]
    );
    assert_eq!(value["radios"][0]["driverNumber"], 16);
    assert!(value["radios"][0].get("driver_number").is_none());
}

#[test]
fn team_radio_only_accepts_https_recordings_for_a_driver() {
    let mut state = state();
    for url in [
        "http://example.com/a.mp3",
        "file:///etc/passwd",
        "https:///no-host.mp3",
        "https://user@example.com/a.mp3",
        "javascript:alert(1)",
        "",
    ] {
        state.apply("team_radio", radio(1, 4, url));
    }
    let mut missing_driver = radio(2, 4, "https://example.com/a.mp3");
    missing_driver
        .as_object_mut()
        .unwrap()
        .remove("driver_number");
    state.apply("team_radio", missing_driver);
    let mut other_session = radio(3, 4, "https://example.com/a.mp3");
    other_session["session_key"] = json!(7);
    state.apply("team_radio", other_session);
    assert!(state.snapshot().radios.is_empty());
}

#[test]
fn bounds_team_radio_history_to_the_newest_clips() {
    let mut state = state();
    for i in 0..510 {
        state.apply(
            "team_radio",
            radio(i, 4, &format!("https://example.com/{i}.mp3")),
        );
    }
    let radios = state.snapshot().radios;
    assert_eq!(radios.len(), 500);
    assert_eq!(
        radios[0].recording_url.as_deref(),
        Some("https://example.com/509.mp3")
    );
}

#[test]
fn a_whole_qualifying_session_of_radio_is_kept() {
    // The 2026 São Paulo qualifying has 33 clips; none may be dropped.
    let mut state = state();
    for i in 0..33 {
        state.apply(
            "team_radio",
            radio(i, 4 + i % 15, &format!("https://example.com/{i}.mp3")),
        );
    }
    assert_eq!(state.snapshot().radios.len(), 33);
}
