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
