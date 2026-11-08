//! What is flagged on the circuit right now, reduced from the session's whole race-control history.
//! The rules are documented in the README's Flags section.
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// A condition that applies to the whole circuit.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TrackFlag {
    #[default]
    Clear,
    Red,
    SafetyCar,
    VirtualSafetyCar,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SectorFlagKind {
    Yellow,
    DoubleYellow,
}

/// A yellow or double yellow in one marshal sector.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SectorFlag {
    pub sector: i64,
    pub flag: SectorFlagKind,
    /// When race control raised it, as OpenF1 reported the time.
    pub since: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FlagStatus {
    pub track: TrackFlag,
    /// When the current track-wide condition began; `None` while the track is clear.
    pub track_since: Option<String>,
    /// Marshal sectors under yellow, lowest number first.
    pub sectors: Vec<SectorFlag>,
}

/// Whether a record can change what is flagged. When history is trimmed these are kept longest, so a flag
/// that has been out for a long time is not forgotten behind a flood of messages that cannot affect it.
pub fn affects_flags(record: &Value) -> bool {
    let text = |field: &str| {
        record[field]
            .as_str()
            .unwrap_or_default()
            .trim()
            .to_lowercase()
    };
    matches!(text("category").as_str(), "safetycar" | "sessionstatus")
        || matches!(text("scope").as_str(), "track" | "sector")
}

/// Reduce race-control records to the current flags. `records` must be oldest first.
pub fn flag_status<'a>(records: impl IntoIterator<Item = &'a Value>) -> FlagStatus {
    let mut status = FlagStatus::default();
    for record in records {
        let text = |field: &str| record[field].as_str().unwrap_or_default().trim();
        let flag = text("flag").to_uppercase();
        let scope = text("scope").to_lowercase();
        let category = text("category").to_lowercase();
        let message = text("message").to_uppercase();
        let date = text("date");

        let set_track = |status: &mut FlagStatus, track: TrackFlag| {
            status.track = track;
            status.track_since = (track != TrackFlag::Clear).then(|| date.to_string());
        };

        if category == "sessionstatus" {
            if message.contains("FINISHED") {
                set_track(&mut status, TrackFlag::Clear);
                status.sectors.clear();
            } else if message.contains("STARTED") && status.track == TrackFlag::Red {
                // Racing has resumed, so a red flag whose TRACK CLEAR was missed is over.
                set_track(&mut status, TrackFlag::Clear);
            }
        } else if category == "safetycar" {
            if message.contains("VSC") || message.contains("VIRTUAL SAFETY CAR") {
                if message.contains("ENDING") || message.contains("ENDED") {
                    if status.track == TrackFlag::VirtualSafetyCar {
                        set_track(&mut status, TrackFlag::Clear);
                    }
                } else {
                    set_track(&mut status, TrackFlag::VirtualSafetyCar);
                }
            } else if message.contains("SAFETY CAR") && status.track != TrackFlag::SafetyCar {
                // Deployed, or still out ("IN THIS LAP"). It ends with TRACK CLEAR.
                set_track(&mut status, TrackFlag::SafetyCar);
            }
        } else if flag == "RED" && scope != "driver" {
            set_track(&mut status, TrackFlag::Red);
        } else if flag == "CLEAR" && scope == "track" {
            set_track(&mut status, TrackFlag::Clear);
            status.sectors.clear();
        } else if scope == "sector" {
            let Some(sector) = record["sector"].as_i64() else {
                continue;
            };
            let kind = match flag.as_str() {
                "YELLOW" => Some(SectorFlagKind::Yellow),
                "DOUBLE YELLOW" => Some(SectorFlagKind::DoubleYellow),
                "CLEAR" => None,
                _ => continue,
            };
            status.sectors.retain(|s| s.sector != sector);
            if let Some(flag) = kind {
                status.sectors.push(SectorFlag {
                    sector,
                    flag,
                    since: date.to_string(),
                });
            }
        }
    }
    status.sectors.sort_by_key(|s| s.sector);
    status
}
