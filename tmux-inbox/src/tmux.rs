//! Thin tmux shell-outs plus the pane-info parser used for display + jump.

use std::collections::HashMap;
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PaneInfo {
    pub session: String,
    pub window: String,
    pub pane: String,
}

/// Pane id from `$TMUX_PANE` (set inside any tmux pane), e.g. "%5".
pub fn current_pane() -> Option<String> {
    std::env::var("TMUX_PANE").ok().filter(|s| !s.is_empty())
}

/// Best-effort: ask tmux to redraw status lines now. Ignores all errors.
pub fn refresh_status() {
    let _ = Command::new("tmux").args(["refresh-client", "-S"]).status();
}

/// Map pane id -> PaneInfo by querying tmux. Empty map on any failure.
pub fn pane_map() -> HashMap<String, PaneInfo> {
    let out = Command::new("tmux")
        .args(["list-panes", "-a", "-F", "#{pane_id} #{session_name} #{window_index} #{pane_index}"])
        .output();
    match out {
        Ok(o) if o.status.success() => parse_pane_map(&String::from_utf8_lossy(&o.stdout)),
        _ => HashMap::new(),
    }
}

/// Parse the `list-panes` output. One pane per line: `<id> <session> <window> <pane>`.
pub fn parse_pane_map(text: &str) -> HashMap<String, PaneInfo> {
    let mut map = HashMap::new();
    for line in text.lines() {
        let mut it = line.splitn(4, ' ');
        if let (Some(id), Some(s), Some(w), Some(p)) = (it.next(), it.next(), it.next(), it.next()) {
            map.insert(
                id.to_string(),
                PaneInfo { session: s.to_string(), window: w.to_string(), pane: p.to_string() },
            );
        }
    }
    map
}

/// Switch the attached client to the given pane id. Returns Ok only if tmux succeeds.
pub fn jump_to(pane_id: &str) -> std::io::Result<bool> {
    let status = Command::new("tmux")
        .args(["switch-client", "-t", pane_id])
        .status()?;
    if !status.success() {
        return Ok(false);
    }
    let _ = Command::new("tmux").args(["select-window", "-t", pane_id]).status();
    let _ = Command::new("tmux").args(["select-pane", "-t", pane_id]).status();
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_pane_map_reads_all_fields() {
        let text = "%5 main 3 0\n%6 other 1 2\n";
        let map = parse_pane_map(text);
        assert_eq!(map.len(), 2);
        assert_eq!(map["%5"], PaneInfo { session: "main".into(), window: "3".into(), pane: "0".into() });
        assert_eq!(map["%6"].window, "1");
    }

    #[test]
    fn parse_pane_map_skips_malformed_lines() {
        let map = parse_pane_map("garbage\n%9 s 2 1\n");
        assert_eq!(map.len(), 1);
        assert!(map.contains_key("%9"));
    }
}
