//! Build the argument vector for `tmux display-menu`.

use crate::event::Event;
use crate::tmux::PaneInfo;
use std::collections::HashMap;

/// Build args (excluding the leading "display-menu") for tmux.
/// Each event becomes a selectable line that runs `tmux-inbox jump <id>`;
/// a trailing "Clear all" entry runs `tmux-inbox dismiss --all`.
pub fn build_menu_args(events: &[Event], panes: &HashMap<String, PaneInfo>, bin: &str) -> Vec<String> {
    let mut args = vec!["-T".to_string(), "#[align=centre] inbox ".to_string()];
    if events.is_empty() {
        // A `-`-prefixed name is a dimmed, non-selectable label in display-menu.
        args.push("-No notifications".to_string());
        args.push("".to_string());
        args.push("".to_string());
        return args;
    }
    for ev in events.iter().rev() {
        let loc = ev
            .location
            .as_deref()
            .and_then(|p| panes.get(p))
            .map(|i| format!("w{} ", i.window))
            .unwrap_or_default();
        let label = format!("{} {}{}", ev.source, loc, ev.message);
        args.push(label);
        args.push("".to_string()); // no key shortcut
        args.push(format!("run-shell '{bin} jump {}'", ev.id));
    }
    args.push("".to_string()); // separator
    args.push("".to_string());
    args.push("".to_string());
    args.push("Clear all".to_string());
    args.push("".to_string());
    args.push(format!("run-shell '{bin} dismiss --all'"));
    args
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::{Event, Level};

    #[test]
    fn newest_first_and_has_jump_and_clear() {
        let a = Event::new("old".into(), "codex".into(), None, Level::Info, 0);
        let b = Event::new("new".into(), "claude".into(), None, Level::Attn, 0);
        let args = build_menu_args(&[a.clone(), b.clone()], &HashMap::new(), "tmux-inbox");
        let joined = args.join("\n");
        // newest (b) appears before oldest (a)
        let pos_new = joined.find("new").unwrap();
        let pos_old = joined.find("old").unwrap();
        assert!(pos_new < pos_old, "newest first");
        assert!(joined.contains(&format!("jump {}", b.id)));
        assert!(joined.contains("dismiss --all"));
    }

    #[test]
    fn empty_inbox_shows_no_notifications_label() {
        let args = build_menu_args(&[], &HashMap::new(), "tmux-inbox");
        let joined = args.join("\n");
        assert!(joined.contains("No notifications"), "got: {joined}");
        assert!(!joined.contains("dismiss --all"), "nothing to clear when empty");
    }
}
