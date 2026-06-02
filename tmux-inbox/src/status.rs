//! Render the always-visible status-bar widget within a width budget.

use crate::event::Event;
use crate::tmux::PaneInfo;
use std::collections::HashMap;

/// Idle glyph shown when the inbox is empty: a hollow bell, the resting
/// counterpart to the attn bell_alert. Keeps the inbox anchored and visible
/// in the status bar even with nothing pending.
pub const IDLE_GLYPH: &str = "\u{f009a}"; // nf-md-bell_outline

/// Build the status string. Empty inbox -> a dim idle glyph.
/// Layout: `<glyph> <count> <source> w<win>:<message>`, truncated to `max_width`.
/// On overflow the trailing message is ellipsized; if even the head won't fit,
/// it collapses to `<glyph> <count>`.
pub fn render(events: &[Event], panes: &HashMap<String, PaneInfo>, max_width: usize) -> String {
    if events.is_empty() {
        return IDLE_GLYPH.to_string();
    }
    let count = events.len();
    let newest = events.last().unwrap();
    let glyph = newest.level.glyph();

    let loc = newest
        .location
        .as_deref()
        .and_then(|p| panes.get(p))
        .map(|i| format!(" w{}:", i.window))
        .unwrap_or_else(|| " ".to_string());

    let head = format!("{glyph} {count} {}{}", newest.source, loc);
    let full = format!("{head}{}", newest.message);

    if width(&full) <= max_width {
        return full;
    }
    // Try ellipsizing the message tail.
    if width(&head) < max_width {
        let budget = max_width - width(&head) - 1; // room for '…'
        let msg: String = newest.message.chars().take(budget).collect();
        return format!("{head}{msg}\u{2026}");
    }
    // Head alone too wide: collapse to glyph + count.
    format!("{glyph} {count}")
}

fn width(s: &str) -> usize {
    s.chars().count()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::{Event, Level};

    fn ev(msg: &str, source: &str, level: Level) -> Event {
        Event::new(msg.into(), source.into(), None, level, 0)
    }

    #[test]
    fn empty_inbox_renders_idle_glyph() {
        let r = render(&[], &HashMap::new(), 40);
        assert_eq!(r, IDLE_GLYPH);
    }

    #[test]
    fn shows_glyph_count_source_and_message() {
        let events = vec![ev("waiting", "claude", Level::Attn)];
        let r = render(&events, &HashMap::new(), 40);
        assert!(r.contains("claude"), "got: {r}");
        assert!(r.contains("waiting"), "got: {r}");
        assert!(r.starts_with(Level::Attn.glyph()), "lead glyph from newest, got: {r}");
        assert!(r.contains('1'), "count, got: {r}");
    }

    #[test]
    fn count_reflects_all_events_newest_drives_text() {
        let events = vec![ev("old", "codex", Level::Info), ev("new", "claude", Level::Attn)];
        let r = render(&events, &HashMap::new(), 40);
        assert!(r.contains('2'));
        assert!(r.contains("claude") && r.contains("new"));
        assert!(!r.contains("codex"));
    }

    #[test]
    fn includes_window_label_when_pane_known() {
        let mut events = vec![ev("waiting", "claude", Level::Attn)];
        events[0].location = Some("%5".into());
        let mut panes = HashMap::new();
        panes.insert("%5".to_string(), PaneInfo { session: "main".into(), window: "3".into(), pane: "0".into() });
        let r = render(&events, &panes, 40);
        assert!(r.contains("w3:"), "got: {r}");
    }

    #[test]
    fn long_message_is_ellipsized_within_budget() {
        let events = vec![ev("this is a very long message that should be cut", "claude", Level::Attn)];
        let r = render(&events, &HashMap::new(), 20);
        assert!(width(&r) <= 20, "width {} > 20: {r}", width(&r));
        assert!(r.ends_with('\u{2026}'));
    }

    fn width(s: &str) -> usize { s.chars().count() }
}
