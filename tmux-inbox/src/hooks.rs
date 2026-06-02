//! Parse Claude (stdin JSON) and Codex (argv JSON) hook payloads into events.

use crate::event::{Event, Level};

/// Claude `Notification`/`Stop` hooks → an `attn` (sticky) event.
/// `event` is "notification" or "stop". `stdin` is the hook's JSON (may be empty).
/// `location` is the captured pane id.
pub fn claude_event(event: &str, stdin: &str, location: Option<String>) -> Event {
    let parsed: serde_json::Value = serde_json::from_str(stdin).unwrap_or(serde_json::Value::Null);
    let message = match event {
        "notification" => parsed
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("needs your attention")
            .to_string(),
        _ => "response ready".to_string(), // stop
    };
    Event::new(message, "claude".into(), location, Level::Attn, 0)
}

/// Codex `notify` payload (a JSON string arg) → an `attn` event for turn completion.
/// Returns None for event types we ignore.
pub fn codex_event(payload: &str, location: Option<String>) -> Option<Event> {
    let parsed: serde_json::Value = serde_json::from_str(payload).ok()?;
    let kind = parsed.get("type").and_then(|v| v.as_str()).unwrap_or("");
    if kind != "agent-turn-complete" {
        return None;
    }
    let message = parsed
        .get("last-assistant-message")
        .and_then(|v| v.as_str())
        .map(|s| truncate(s, 60))
        .unwrap_or_else(|| "turn complete".to_string());
    Some(Event::new(message, "codex".into(), location, Level::Attn, 0))
}

fn truncate(s: &str, n: usize) -> String {
    let t: String = s.chars().take(n).collect();
    if t.chars().count() < s.chars().count() {
        format!("{t}\u{2026}")
    } else {
        t
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn claude_notification_uses_message_field() {
        let e = claude_event("notification", r#"{"message":"Permission needed"}"#, Some("%1".into()));
        assert_eq!(e.source, "claude");
        assert_eq!(e.level, Level::Attn);
        assert_eq!(e.message, "Permission needed");
        assert_eq!(e.location.as_deref(), Some("%1"));
    }

    #[test]
    fn claude_stop_has_default_message() {
        let e = claude_event("stop", "", None);
        assert_eq!(e.message, "response ready");
        assert_eq!(e.level, Level::Attn);
    }

    #[test]
    fn codex_turn_complete_produces_event() {
        let e = codex_event(r#"{"type":"agent-turn-complete","last-assistant-message":"done"}"#, None).unwrap();
        assert_eq!(e.source, "codex");
        assert_eq!(e.message, "done");
    }

    #[test]
    fn codex_other_types_are_ignored() {
        assert!(codex_event(r#"{"type":"something-else"}"#, None).is_none());
        assert!(codex_event("not json", None).is_none());
    }

    #[test]
    fn codex_long_message_truncated() {
        let long = "x".repeat(100);
        let payload = format!(r#"{{"type":"agent-turn-complete","last-assistant-message":"{long}"}}"#);
        let e = codex_event(&payload, None).unwrap();
        assert!(e.message.ends_with('\u{2026}'));
        assert!(e.message.chars().count() <= 61);
    }
}
