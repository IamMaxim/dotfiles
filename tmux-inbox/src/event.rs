//! Event model: levels, the Event struct, id generation, and expiry.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Level {
    Attn,
    Info,
    Done,
}

impl Level {
    /// Monochrome nerd-font glyph for this level (no color emoji).
    pub fn glyph(self) -> &'static str {
        match self {
            Level::Attn => "\u{f009c}", // nf-md-bell_alert
            Level::Info => "\u{f02fc}", // nf-md-information
            Level::Done => "\u{f05e0}", // nf-md-check_circle
        }
    }

    /// Default time-to-live in seconds; 0 means sticky (never auto-expire).
    pub fn default_ttl(self) -> u64 {
        match self {
            Level::Attn => 0,
            Level::Info => 300,
            Level::Done => 300,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Level::Attn => "attn",
            Level::Info => "info",
            Level::Done => "done",
        }
    }

    pub fn parse(s: &str) -> Option<Level> {
        match s {
            "attn" => Some(Level::Attn),
            "info" => Some(Level::Info),
            "done" => Some(Level::Done),
            _ => None,
        }
    }
}

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static COUNTER: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Event {
    pub id: String,
    pub time: u64, // unix seconds
    pub message: String,
    pub source: String,
    #[serde(default)]
    pub location: Option<String>, // tmux pane id, e.g. "%5"
    pub level: Level,
    pub ttl: u64, // seconds; 0 = sticky
}

pub fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Generates a lexicographically-sortable unique id (zero-padded nanos + pid + counter).
pub fn new_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let pid = std::process::id();
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{:039}-{}-{}", nanos, pid, n)
}

impl Event {
    pub fn new(message: String, source: String, location: Option<String>, level: Level, ttl: u64) -> Event {
        Event { id: new_id(), time: now_secs(), message, source, location, level, ttl }
    }

    pub fn is_expired(&self, now: u64) -> bool {
        self.ttl != 0 && now.saturating_sub(self.time) > self.ttl
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn attn_is_sticky_others_expire() {
        assert_eq!(Level::Attn.default_ttl(), 0);
        assert_eq!(Level::Info.default_ttl(), 300);
        assert_eq!(Level::Done.default_ttl(), 300);
    }

    #[test]
    fn parse_roundtrips() {
        for l in [Level::Attn, Level::Info, Level::Done] {
            assert_eq!(Level::parse(l.as_str()), Some(l));
        }
        assert_eq!(Level::parse("nope"), None);
    }

    #[test]
    fn each_level_has_distinct_glyph() {
        let g = [Level::Attn.glyph(), Level::Info.glyph(), Level::Done.glyph()];
        assert_eq!(g.iter().collect::<std::collections::HashSet<_>>().len(), 3);
    }

    #[test]
    fn ids_are_unique_and_sorted_by_creation() {
        let a = new_id();
        let b = new_id();
        assert_ne!(a, b);
        assert!(a < b, "{a} should sort before {b}");
    }

    #[test]
    fn sticky_events_never_expire() {
        let e = Event::new("hi".into(), "claude".into(), None, Level::Attn, 0);
        assert!(!e.is_expired(e.time + 1_000_000));
    }

    #[test]
    fn ttl_events_expire_after_window() {
        let mut e = Event::new("hi".into(), "build".into(), None, Level::Done, 300);
        e.time = 1000;
        assert!(!e.is_expired(1000 + 300));
        assert!(e.is_expired(1000 + 301));
    }

    #[test]
    fn event_json_roundtrips() {
        let e = Event::new("waiting".into(), "claude".into(), Some("%5".into()), Level::Attn, 0);
        let json = serde_json::to_string(&e).unwrap();
        let back: Event = serde_json::from_str(&json).unwrap();
        assert_eq!(e, back);
    }
}
