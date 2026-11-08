//! What is flagged right now, worked out from real OpenF1 race-control wording: sector flags
//! (`scope: "Sector"`, a marshal sector number), track-wide states, and how each one ends.
use formula_live_backend::flags::{FlagStatus, SectorFlagKind, TrackFlag};
use formula_live_backend::state::{Session, TimingState};
use serde_json::{json, Value};

fn state() -> TimingState {
    let mut state = TimingState::new("live");
    state.set_session(Session {
        session_key: 42,
        session_name: "Qualifying".into(),
        circuit_short_name: "Interlagos".into(),
        date_start: "2026-11-07T18:00:00Z".into(),
        date_end: "2026-11-07T19:00:00Z".into(),
    });
    state
}

fn send(state: &mut TimingState, time: &str, mut record: Value) {
    record["session_key"] = json!(42);
    record["date"] = json!(format!("2026-11-07T{time}+00:00"));
    state.apply("race_control", record);
}

fn yellow(state: &mut TimingState, time: &str, sector: i64) {
    send(
        state,
        time,
        json!({"category":"Flag","flag":"YELLOW","scope":"Sector","sector":sector,
               "message":format!("YELLOW IN TRACK SECTOR {sector}")}),
    );
}

fn double_yellow(state: &mut TimingState, time: &str, sector: i64) {
    send(
        state,
        time,
        json!({"category":"Flag","flag":"DOUBLE YELLOW","scope":"Sector","sector":sector,
               "message":format!("DOUBLE YELLOW IN TRACK SECTOR {sector}")}),
    );
}

fn clear_sector(state: &mut TimingState, time: &str, sector: i64) {
    send(
        state,
        time,
        json!({"category":"Flag","flag":"CLEAR","scope":"Sector","sector":sector,
               "message":format!("CLEAR IN TRACK SECTOR {sector}")}),
    );
}

fn track_clear(state: &mut TimingState, time: &str) {
    send(
        state,
        time,
        json!({"category":"Flag","flag":"CLEAR","scope":"Track","message":"TRACK CLEAR"}),
    );
}

fn red(state: &mut TimingState, time: &str) {
    send(
        state,
        time,
        json!({"category":"Flag","flag":"RED","scope":"Track","message":"RED FLAG"}),
    );
}

fn safety_car(state: &mut TimingState, time: &str, message: &str) {
    send(
        state,
        time,
        json!({"category":"SafetyCar","message":message}),
    );
}

fn sectors(status: &FlagStatus) -> Vec<(i64, SectorFlagKind)> {
    status.sectors.iter().map(|s| (s.sector, s.flag)).collect()
}

#[test]
fn nothing_is_flagged_before_any_message() {
    let status = state().snapshot().flags;
    assert_eq!(status.track, TrackFlag::Clear);
    assert!(status.sectors.is_empty());
    assert_eq!(status.track_since, None);
}

#[test]
fn a_sector_is_yellow_from_its_flag_until_its_own_clear() {
    let mut state = state();
    yellow(&mut state, "17:47:43", 1);
    yellow(&mut state, "17:47:45", 16);
    // Sectors 1 and 16 are yellow, sector 16 is listed after 1.
    assert_eq!(
        sectors(&state.snapshot().flags),
        vec![(1, SectorFlagKind::Yellow), (16, SectorFlagKind::Yellow)]
    );
    assert_eq!(state.snapshot().flags.track, TrackFlag::Clear);

    clear_sector(&mut state, "17:54:32", 16);
    assert_eq!(
        sectors(&state.snapshot().flags),
        vec![(1, SectorFlagKind::Yellow)]
    );
    clear_sector(&mut state, "17:54:34", 1);
    assert!(state.snapshot().flags.sectors.is_empty());
}

#[test]
fn a_double_yellow_replaces_a_yellow_in_the_same_sector_and_back() {
    let mut state = state();
    yellow(&mut state, "19:29:07", 3);
    double_yellow(&mut state, "19:29:07", 4);
    assert_eq!(
        sectors(&state.snapshot().flags),
        vec![
            (3, SectorFlagKind::Yellow),
            (4, SectorFlagKind::DoubleYellow)
        ]
    );
    double_yellow(&mut state, "19:30:00", 3);
    yellow(&mut state, "19:30:05", 4);
    assert_eq!(
        sectors(&state.snapshot().flags),
        vec![
            (3, SectorFlagKind::DoubleYellow),
            (4, SectorFlagKind::Yellow)
        ]
    );
}

#[test]
fn a_sector_flag_remembers_when_it_was_raised() {
    let mut state = state();
    yellow(&mut state, "19:33:20", 13);
    assert_eq!(
        state.snapshot().flags.sectors[0].since,
        "2026-11-07T19:33:20+00:00"
    );
}

#[test]
fn track_clear_withdraws_every_sector_flag_and_a_red_flag() {
    let mut state = state();
    red(&mut state, "20:03:18");
    yellow(&mut state, "20:03:30", 10);
    double_yellow(&mut state, "20:03:31", 11);
    assert_eq!(state.snapshot().flags.track, TrackFlag::Red);
    track_clear(&mut state, "20:05:29");
    let status = state.snapshot().flags;
    assert_eq!(status.track, TrackFlag::Clear);
    assert!(status.sectors.is_empty());
}

#[test]
fn a_red_flag_is_track_wide_and_keeps_its_time() {
    let mut state = state();
    red(&mut state, "18:02:23");
    let status = state.snapshot().flags;
    assert_eq!(status.track, TrackFlag::Red);
    assert_eq!(
        status.track_since.as_deref(),
        Some("2026-11-07T18:02:23+00:00")
    );
}

#[test]
fn the_safety_car_lasts_until_the_track_is_clear_not_until_it_comes_in() {
    let mut state = state();
    safety_car(&mut state, "07:20:04", "SAFETY CAR DEPLOYED");
    assert_eq!(state.snapshot().flags.track, TrackFlag::SafetyCar);
    safety_car(&mut state, "07:26:11", "SAFETY CAR IN THIS LAP");
    assert_eq!(state.snapshot().flags.track, TrackFlag::SafetyCar);
    track_clear(&mut state, "07:27:50");
    assert_eq!(state.snapshot().flags.track, TrackFlag::Clear);
}

#[test]
fn the_virtual_safety_car_ends_with_its_own_ending_message() {
    // Real sessions often follow "VSC ENDING" with sector flags rather than "TRACK CLEAR".
    let mut state = state();
    safety_car(&mut state, "13:32:52", "VSC DEPLOYED");
    assert_eq!(state.snapshot().flags.track, TrackFlag::VirtualSafetyCar);
    safety_car(&mut state, "13:35:29", "VSC ENDING");
    assert_eq!(state.snapshot().flags.track, TrackFlag::Clear);
}

#[test]
fn a_virtual_safety_car_ending_does_not_end_a_red_flag() {
    let mut state = state();
    red(&mut state, "13:00:00");
    safety_car(&mut state, "13:01:00", "VSC ENDING");
    assert_eq!(state.snapshot().flags.track, TrackFlag::Red);
}

#[test]
fn flags_shown_to_one_driver_say_nothing_about_the_track() {
    let mut state = state();
    send(
        &mut state,
        "15:00:00",
        json!({"category":"Flag","flag":"BLUE","scope":"Driver","driver_number":4,
               "message":"WAVED BLUE FLAG FOR CAR 4 (NOR) TIMED AT 15:00:00"}),
    );
    send(
        &mut state,
        "15:00:01",
        json!({"category":"Flag","flag":"BLACK AND WHITE","scope":"Driver","driver_number":4,
               "message":"BLACK AND WHITE FLAG FOR CAR 4 (NOR) - TRACK LIMITS"}),
    );
    send(
        &mut state,
        "15:00:02",
        json!({"category":"Flag","flag":"GREEN","scope":"Track","message":"GREEN LIGHT - PIT EXIT OPEN"}),
    );
    // Even a red flag is only the track's when its scope is the track.
    send(
        &mut state,
        "15:00:03",
        json!({"category":"Flag","flag":"RED","scope":"Driver","driver_number":4,"message":"RED FLAG FOR CAR 4"}),
    );
    let status = state.snapshot().flags;
    assert_eq!(status.track, TrackFlag::Clear);
    assert!(status.sectors.is_empty());
}

#[test]
fn steward_messages_that_mention_the_safety_car_or_vsc_are_not_a_deployment() {
    let mut state = state();
    send(
        &mut state,
        "21:21:08",
        json!({"category":"Other","message":"INCIDENT INVOLVING CAR 5 (BOR) NOTED - VSC INFRINGEMENT"}),
    );
    send(
        &mut state,
        "21:21:09",
        json!({"category":"Other","message":"FIA STEWARDS: 5 SECOND TIME PENALTY - SAFETY CAR INFRINGEMENT"}),
    );
    assert_eq!(state.snapshot().flags.track, TrackFlag::Clear);
}

#[test]
fn session_finished_ends_everything_raised_before_it_but_not_flags_after_it() {
    let mut state = state();
    red(&mut state, "19:40:00");
    yellow(&mut state, "19:40:30", 5);
    send(
        &mut state,
        "19:41:00",
        json!({"category":"SessionStatus","message":"SESSION FINISHED"}),
    );
    let status = state.snapshot().flags;
    assert_eq!(status.track, TrackFlag::Clear);
    assert!(status.sectors.is_empty());
    // A cool-down lap incident after the chequered flag is a real yellow.
    yellow(&mut state, "19:41:41", 12);
    assert_eq!(
        sectors(&state.snapshot().flags),
        vec![(12, SectorFlagKind::Yellow)]
    );
}

#[test]
fn messages_in_the_same_second_keep_the_order_they_arrived_in() {
    // Both orders happen in real sessions: the second message wins.
    let mut raised_then_cleared = state();
    double_yellow(&mut raised_then_cleared, "14:37:59", 11);
    clear_sector(&mut raised_then_cleared, "14:37:59", 11);
    assert!(raised_then_cleared.snapshot().flags.sectors.is_empty());

    let mut cleared_then_raised = state();
    clear_sector(&mut cleared_then_raised, "15:05:15", 10);
    double_yellow(&mut cleared_then_raised, "15:05:15", 10);
    assert_eq!(
        sectors(&cleared_then_raised.snapshot().flags),
        vec![(10, SectorFlagKind::DoubleYellow)]
    );
}

#[test]
fn a_late_arriving_older_message_does_not_override_a_newer_one() {
    let mut state = state();
    clear_sector(&mut state, "17:54:34", 1);
    yellow(&mut state, "17:47:43", 1);
    assert!(state.snapshot().flags.sectors.is_empty());
}

#[test]
fn a_yellow_stays_flagged_after_more_than_a_hundred_later_messages() {
    let mut state = state();
    yellow(&mut state, "10:00:00", 7);
    for i in 0..150 {
        send(
            &mut state,
            &format!("11:{:02}:{:02}", i / 60, i % 60),
            json!({"category":"Flag","flag":"BLUE","scope":"Driver","driver_number":4,
                   "message":format!("WAVED BLUE FLAG {i}")}),
        );
    }
    let snapshot = state.snapshot();
    // The visible list stays at 100 messages, but the flag state still knows about sector 7.
    assert_eq!(snapshot.messages.len(), 100);
    assert_eq!(sectors(&snapshot.flags), vec![(7, SectorFlagKind::Yellow)]);
}

#[test]
fn a_new_session_starts_with_nothing_flagged() {
    let mut state = state();
    red(&mut state, "18:02:23");
    yellow(&mut state, "18:03:00", 4);
    state.set_session(Session {
        session_key: 43,
        session_name: "Race".into(),
        circuit_short_name: "Interlagos".into(),
        date_start: "2026-11-08T17:00:00Z".into(),
        date_end: "2026-11-08T19:00:00Z".into(),
    });
    let status = state.snapshot().flags;
    assert_eq!(status.track, TrackFlag::Clear);
    assert!(status.sectors.is_empty());
}

#[test]
fn flags_serialise_with_the_camel_case_keys_the_app_reads() {
    let mut state = state();
    safety_car(&mut state, "14:20:02", "SAFETY CAR DEPLOYED");
    double_yellow(&mut state, "14:20:06", 17);
    let value = serde_json::to_value(state.snapshot()).unwrap();
    assert_eq!(value["flags"]["track"], "safetyCar");
    assert_eq!(value["flags"]["trackSince"], "2026-11-07T14:20:02+00:00");
    assert_eq!(
        value["flags"]["sectors"],
        json!([{"sector":17,"flag":"doubleYellow","since":"2026-11-07T14:20:06+00:00"}])
    );
    let virtual_car = {
        let mut state = state;
        safety_car(&mut state, "14:25:00", "VSC DEPLOYED");
        serde_json::to_value(state.snapshot()).unwrap()
    };
    assert_eq!(virtual_car["flags"]["track"], "virtualSafetyCar");
}

#[test]
fn a_clear_snapshot_serialises_an_explicit_null_for_the_track_time() {
    let value = serde_json::to_value(state().snapshot()).unwrap();
    assert_eq!(value["flags"]["track"], "clear");
    assert!(value["flags"]["trackSince"].is_null());
    assert_eq!(value["flags"]["sectors"], json!([]));
}
