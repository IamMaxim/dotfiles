# tmux-inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single Rust binary that implements a tmux status-bar notification inbox: producers publish events into a spool directory, the events surface as a compact status-bar badge and a persistent log triaged via tmux menu/popup.

**Architecture:** One Rust binary (`tmux-inbox`) with subcommands. Storage is a maildir-style spool directory (one JSON file per event, atomic writes, lazy TTL pruning). No daemon. Status refresh is poll-based (`status-interval`) plus best-effort `tmux refresh-client -S` on publish. Display labels (window indices, pane existence) are resolved lazily at render time so the publish path stays fast.

**Tech Stack:** Rust, `clap` (CLI), `serde`/`serde_json` (event JSON + Claude settings), `toml` (Codex config), `ratatui`/`crossterm` (popup TUI), `dirs` (home dir), `tempfile` (dev/tests).

**Reference spec:** `docs/superpowers/specs/2026-06-02-tmux-inbox-design.md`

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Cargo.toml` | Crate manifest + dependencies |
| `src/main.rs` | clap CLI definition + dispatch to subcommand handlers |
| `src/event.rs` | `Level` enum, `Event` struct, serde, id generation, glyph/TTL mapping, expiry |
| `src/spool.rs` | Spool dir resolution, publish (atomic), list (+prune), dismiss (id/all/source) |
| `src/tmux.rs` | tmux shell-outs: current pane, refresh, pane map, jump, pane-exists |
| `src/status.rs` | Render the status-bar widget string within a width budget |
| `src/menu.rs` | Build `tmux display-menu` argument vector |
| `src/tui.rs` | ratatui popup: `TuiState` action state-machine + event loop |
| `src/hooks.rs` | `claude-hook` and `codex-hook` payload parsing → publish (+ Codex chain forward) |
| `src/install.rs` | `install claude` (settings.json merge) + `install codex` (config.toml chain) + `install tmux` snippet |
| `src/config.rs` | tmux-inbox's own config file (stores Codex chain command) |

Each `cmd_*` handler lives in `main.rs` and delegates to these modules so the modules stay free of CLI/`println!` concerns and remain unit-testable.

---

## Task 1: Project scaffold

**Files:**
- Create: `Cargo.toml`
- Create: `src/main.rs`

- [ ] **Step 1: Create `Cargo.toml`**

```toml
[package]
name = "tmux-inbox"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "tmux-inbox"
path = "src/main.rs"

[dependencies]
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"
ratatui = "0.29"
crossterm = "0.28"
dirs = "5"

[dev-dependencies]
tempfile = "3"
```

- [ ] **Step 2: Create a minimal `src/main.rs` that compiles**

```rust
mod event;
mod spool;
mod tmux;
mod status;
mod menu;
mod tui;
mod hooks;
mod install;
mod config;

fn main() {
    println!("tmux-inbox");
}
```

- [ ] **Step 3: Create empty module files so it compiles**

Create each of `src/event.rs`, `src/spool.rs`, `src/tmux.rs`, `src/status.rs`, `src/menu.rs`, `src/tui.rs`, `src/hooks.rs`, `src/install.rs`, `src/config.rs` containing only a doc comment line:

```rust
//! placeholder — implemented in a later task
```

- [ ] **Step 4: Verify it builds**

Run: `cargo build`
Expected: compiles successfully (warnings about unused modules are fine).

- [ ] **Step 5: Commit**

```bash
git add Cargo.toml src/
git commit -m "chore: scaffold tmux-inbox crate"
```

---

## Task 2: Event model — Level enum

**Files:**
- Modify: `src/event.rs`

- [ ] **Step 1: Write failing tests**

Replace `src/event.rs` contents with:

```rust
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
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test event::tests`
Expected: 3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/event.rs
git commit -m "feat: add Level enum with glyph and TTL mapping"
```

---

## Task 3: Event struct, id generation, expiry

**Files:**
- Modify: `src/event.rs`

- [ ] **Step 1: Write the failing tests** (append inside the existing `tests` module and add code above it)

Add this struct and impl above the `#[cfg(test)]` block:

```rust
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
```

Add these tests inside the `tests` module:

```rust
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
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test event::tests`
Expected: all event tests pass (7 total).

- [ ] **Step 3: Commit**

```bash
git add src/event.rs
git commit -m "feat: add Event struct with id generation and expiry"
```

---

## Task 4: Spool directory resolution + publish

**Files:**
- Modify: `src/spool.rs`

- [ ] **Step 1: Write failing tests**

Replace `src/spool.rs` with:

```rust
//! Maildir-style spool: one JSON file per event in a directory.

use crate::event::Event;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub struct Spool {
    dir: PathBuf,
}

impl Spool {
    /// Resolve the spool dir from the environment and ensure it exists.
    pub fn open() -> io::Result<Spool> {
        let dir = default_dir();
        fs::create_dir_all(&dir)?;
        Ok(Spool { dir })
    }

    /// Construct a spool over an explicit directory (used in tests).
    pub fn with_dir<P: AsRef<Path>>(dir: P) -> io::Result<Spool> {
        let dir = dir.as_ref().to_path_buf();
        fs::create_dir_all(&dir)?;
        Ok(Spool { dir })
    }

    fn path_for(&self, id: &str) -> PathBuf {
        self.dir.join(format!("{id}.json"))
    }

    /// Write the event atomically (temp file + rename).
    pub fn publish(&self, ev: &Event) -> io::Result<()> {
        let tmp = self.dir.join(format!(".tmp-{}", ev.id));
        let json = serde_json::to_vec(ev).map_err(io::Error::other)?;
        fs::write(&tmp, &json)?;
        fs::rename(&tmp, self.path_for(&ev.id))?;
        Ok(())
    }
}

/// `$XDG_RUNTIME_DIR/tmux-inbox`, else `$TMPDIR/tmux-inbox-<user>`, else `/tmp/...`.
fn default_dir() -> PathBuf {
    if let Some(rt) = std::env::var_os("XDG_RUNTIME_DIR") {
        return PathBuf::from(rt).join("tmux-inbox");
    }
    let user = std::env::var("USER").unwrap_or_else(|_| "default".into());
    let base = std::env::var_os("TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join(format!("tmux-inbox-{user}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::{Event, Level};

    #[test]
    fn publish_writes_a_json_file_and_no_temp_leftover() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = Spool::with_dir(tmp.path()).unwrap();
        let ev = Event::new("hi".into(), "claude".into(), None, Level::Attn, 0);
        spool.publish(&ev).unwrap();

        let entries: Vec<_> = fs::read_dir(tmp.path()).unwrap().map(|e| e.unwrap().file_name()).collect();
        assert_eq!(entries.len(), 1, "exactly one file, no .tmp leftover");
        assert!(entries[0].to_str().unwrap().ends_with(".json"));
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test spool::tests`
Expected: 1 test passes.

- [ ] **Step 3: Commit**

```bash
git add src/spool.rs
git commit -m "feat: spool dir resolution and atomic publish"
```

---

## Task 5: Spool list + lazy prune

**Files:**
- Modify: `src/spool.rs`

- [ ] **Step 1: Write failing tests**

Add to the `impl Spool` block:

```rust
    /// Return non-expired events sorted oldest→newest by id, deleting expired files.
    pub fn list(&self, now: u64) -> io::Result<Vec<Event>> {
        let mut out = Vec::new();
        for entry in fs::read_dir(&self.dir)? {
            let entry = entry?;
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if !name.ends_with(".json") {
                continue; // skip .tmp-* and anything else
            }
            let path = entry.path();
            let data = match fs::read(&path) {
                Ok(d) => d,
                Err(_) => continue,
            };
            let ev: Event = match serde_json::from_slice(&data) {
                Ok(e) => e,
                Err(_) => continue, // skip corrupt/partial files
            };
            if ev.is_expired(now) {
                let _ = fs::remove_file(&path);
                continue;
            }
            out.push(ev);
        }
        out.sort_by(|a, b| a.id.cmp(&b.id));
        Ok(out)
    }
```

Add these tests:

```rust
    #[test]
    fn list_returns_sorted_non_expired() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = Spool::with_dir(tmp.path()).unwrap();
        let a = Event::new("first".into(), "x".into(), None, Level::Attn, 0);
        let b = Event::new("second".into(), "x".into(), None, Level::Attn, 0);
        spool.publish(&a).unwrap();
        spool.publish(&b).unwrap();

        let got = spool.list(now()).unwrap();
        assert_eq!(got.len(), 2);
        assert_eq!(got[0].message, "first");
        assert_eq!(got[1].message, "second");
    }

    #[test]
    fn list_prunes_expired_files() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = Spool::with_dir(tmp.path()).unwrap();
        let mut old = Event::new("old".into(), "x".into(), None, Level::Done, 10);
        old.time = 100;
        spool.publish(&old).unwrap();

        let got = spool.list(1000).unwrap();
        assert!(got.is_empty(), "expired event pruned");
        let remaining = fs::read_dir(tmp.path()).unwrap().count();
        assert_eq!(remaining, 0, "expired file deleted from disk");
    }

    fn now() -> u64 {
        crate::event::now_secs()
    }
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test spool::tests`
Expected: 3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/spool.rs
git commit -m "feat: spool list with lazy expiry pruning"
```

---

## Task 6: Spool dismiss (id / all / source)

**Files:**
- Modify: `src/spool.rs`

- [ ] **Step 1: Write failing tests**

Add to the `impl Spool` block:

```rust
    /// Remove a single event by id. Returns true if a file was removed.
    pub fn dismiss_id(&self, id: &str) -> io::Result<bool> {
        let path = self.path_for(id);
        match fs::remove_file(&path) {
            Ok(()) => Ok(true),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// Remove every event. Returns the count removed.
    pub fn dismiss_all(&self) -> io::Result<usize> {
        let ids: Vec<String> = self.list(crate::event::now_secs())?.into_iter().map(|e| e.id).collect();
        let mut n = 0;
        for id in ids {
            if self.dismiss_id(&id)? {
                n += 1;
            }
        }
        Ok(n)
    }

    /// Remove every pending event whose source matches. Returns the count removed.
    pub fn dismiss_source(&self, source: &str) -> io::Result<usize> {
        let ids: Vec<String> = self
            .list(crate::event::now_secs())?
            .into_iter()
            .filter(|e| e.source == source)
            .map(|e| e.id)
            .collect();
        let mut n = 0;
        for id in ids {
            if self.dismiss_id(&id)? {
                n += 1;
            }
        }
        Ok(n)
    }
```

Add these tests:

```rust
    #[test]
    fn dismiss_id_removes_one() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = Spool::with_dir(tmp.path()).unwrap();
        let a = Event::new("a".into(), "x".into(), None, Level::Attn, 0);
        spool.publish(&a).unwrap();
        assert!(spool.dismiss_id(&a.id).unwrap());
        assert!(!spool.dismiss_id(&a.id).unwrap(), "second remove is a no-op");
        assert!(spool.list(now()).unwrap().is_empty());
    }

    #[test]
    fn dismiss_source_only_removes_matching() {
        let tmp = tempfile::tempdir().unwrap();
        let spool = Spool::with_dir(tmp.path()).unwrap();
        spool.publish(&Event::new("a".into(), "claude".into(), None, Level::Attn, 0)).unwrap();
        spool.publish(&Event::new("b".into(), "codex".into(), None, Level::Attn, 0)).unwrap();
        assert_eq!(spool.dismiss_source("claude").unwrap(), 1);
        let left = spool.list(now()).unwrap();
        assert_eq!(left.len(), 1);
        assert_eq!(left[0].source, "codex");
    }
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test spool::tests`
Expected: 5 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/spool.rs
git commit -m "feat: spool dismiss by id, all, and source"
```

---

## Task 7: tmux helpers

**Files:**
- Modify: `src/tmux.rs`

`pane_map` is the lazy display/jump resolver. Functions that shell out are thin wrappers; the parser (`parse_pane_map`) is the unit-tested part.

- [ ] **Step 1: Write failing tests**

Replace `src/tmux.rs` with:

```rust
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
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test tmux::tests`
Expected: 2 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/tmux.rs
git commit -m "feat: tmux helpers and pane-map parser"
```

---

## Task 8: Status renderer

**Files:**
- Modify: `src/status.rs`

- [ ] **Step 1: Write failing tests**

Replace `src/status.rs` with:

```rust
//! Render the always-visible status-bar widget within a width budget.

use crate::event::Event;
use crate::tmux::PaneInfo;
use std::collections::HashMap;

/// Build the status string. Empty inbox -> empty string.
/// Layout: `<glyph> <count> <source> w<win>:<message>`, truncated to `max_width`.
/// On overflow the trailing message is ellipsized; if even the head won't fit,
/// it collapses to `<glyph> <count>`.
pub fn render(events: &[Event], panes: &HashMap<String, PaneInfo>, max_width: usize) -> String {
    if events.is_empty() {
        return String::new();
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
    fn empty_inbox_renders_empty() {
        let r = render(&[], &HashMap::new(), 40);
        assert_eq!(r, "");
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
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test status::tests`
Expected: 5 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/status.rs
git commit -m "feat: status-bar renderer with width budget"
```

---

## Task 9: Menu builder

**Files:**
- Modify: `src/menu.rs`

- [ ] **Step 1: Write failing tests**

Replace `src/menu.rs` with:

```rust
//! Build the argument vector for `tmux display-menu`.

use crate::event::Event;
use crate::tmux::PaneInfo;
use std::collections::HashMap;

/// Build args (excluding the leading "display-menu") for tmux.
/// Each event becomes a selectable line that runs `tmux-inbox jump <id>`;
/// a trailing "Clear all" entry runs `tmux-inbox dismiss --all`.
pub fn build_menu_args(events: &[Event], panes: &HashMap<String, PaneInfo>, bin: &str) -> Vec<String> {
    let mut args = vec!["-T".to_string(), "#[align=centre] inbox ".to_string()];
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
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test menu::tests`
Expected: 1 test passes.

- [ ] **Step 3: Commit**

```bash
git add src/menu.rs
git commit -m "feat: tmux display-menu argument builder"
```

---

## Task 10: TUI state machine

**Files:**
- Modify: `src/tui.rs`

The interactive loop is thin; the testable part is `TuiState` mapping keys to `Action`s.

- [ ] **Step 1: Write failing tests**

Replace `src/tui.rs` with:

```rust
//! ratatui popup: a small key->action state machine plus the event loop.

use crate::event::Event;

#[derive(Debug, PartialEq, Eq)]
pub enum Action {
    Jump(String),       // event id
    Dismiss(String),    // event id
    DismissAll,
    Quit,
    None,
}

pub struct TuiState {
    pub events: Vec<Event>, // newest last
    pub selected: usize,    // index into events
}

impl TuiState {
    pub fn new(mut events: Vec<Event>) -> TuiState {
        events.sort_by(|a, b| a.id.cmp(&b.id));
        let selected = events.len().saturating_sub(1); // start on newest
        TuiState { events, selected }
    }

    pub fn down(&mut self) {
        if self.selected + 1 < self.events.len() {
            self.selected += 1;
        }
    }

    pub fn up(&mut self) {
        self.selected = self.selected.saturating_sub(1);
    }

    fn current_id(&self) -> Option<String> {
        self.events.get(self.selected).map(|e| e.id.clone())
    }

    /// Map a single character keypress to an action.
    pub fn on_key(&mut self, c: char) -> Action {
        match c {
            'j' => { self.down(); Action::None }
            'k' => { self.up(); Action::None }
            '\n' | '\r' => self.current_id().map(Action::Jump).unwrap_or(Action::None),
            'd' => self.current_id().map(Action::Dismiss).unwrap_or(Action::None),
            'D' => Action::DismissAll,
            'q' => Action::Quit,
            _ => Action::None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::{Event, Level};

    fn evs() -> Vec<Event> {
        vec![
            Event::new("a".into(), "codex".into(), None, Level::Info, 0),
            Event::new("b".into(), "claude".into(), None, Level::Attn, 0),
        ]
    }

    #[test]
    fn starts_on_newest() {
        let s = TuiState::new(evs());
        assert_eq!(s.events[s.selected].message, "b");
    }

    #[test]
    fn navigation_clamps() {
        let mut s = TuiState::new(evs());
        s.down(); // already at last
        assert_eq!(s.selected, 1);
        s.up();
        s.up(); // clamp at 0
        assert_eq!(s.selected, 0);
    }

    #[test]
    fn enter_jumps_current() {
        let mut s = TuiState::new(evs());
        let id = s.events[s.selected].id.clone();
        assert_eq!(s.on_key('\n'), Action::Jump(id));
    }

    #[test]
    fn d_dismisses_current_shift_d_all_q_quits() {
        let mut s = TuiState::new(evs());
        let id = s.events[s.selected].id.clone();
        assert_eq!(s.on_key('d'), Action::Dismiss(id));
        assert_eq!(s.on_key('D'), Action::DismissAll);
        assert_eq!(s.on_key('q'), Action::Quit);
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test tui::tests`
Expected: 4 tests pass.

- [ ] **Step 3: Add the rendering + event loop** (not unit-tested; exercised manually in Task 17)

Append to `src/tui.rs`:

```rust
use crate::spool::Spool;
use crate::tmux;
use crossterm::event::{self as cevent, Event as CEvent, KeyCode};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::execute;
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, List, ListItem, ListState};
use std::io;
use std::time::Duration;

/// Run the popup against the live spool. `here` filters to the current session.
pub fn run(spool: &Spool, bin: &str, here: bool) -> io::Result<()> {
    let panes = tmux::pane_map();
    let mut events = spool.list(crate::event::now_secs())?;
    if here {
        if let Some(cur) = tmux::current_pane().and_then(|p| panes.get(&p).map(|i| i.session.clone())) {
            events.retain(|e| {
                e.location.as_deref().and_then(|p| panes.get(p)).map(|i| i.session == cur).unwrap_or(false)
            });
        }
    }
    let mut state = TuiState::new(events);

    enable_raw_mode()?;
    let mut out = io::stdout();
    execute!(out, EnterAlternateScreen)?;
    let mut term = Terminal::new(CrosstermBackend::new(out))?;

    let result = event_loop(&mut term, &mut state, &panes, spool, bin);

    disable_raw_mode()?;
    execute!(term.backend_mut(), LeaveAlternateScreen)?;
    term.show_cursor()?;
    result
}

fn event_loop<B: Backend>(
    term: &mut Terminal<B>,
    state: &mut TuiState,
    panes: &std::collections::HashMap<String, tmux::PaneInfo>,
    spool: &Spool,
    bin: &str,
) -> io::Result<()> {
    let _ = bin;
    loop {
        term.draw(|f| draw(f, state, panes))?;
        if !cevent::poll(Duration::from_millis(250))? {
            continue;
        }
        if let CEvent::Key(k) = cevent::read()? {
            let c = match k.code {
                KeyCode::Char(c) => c,
                KeyCode::Enter => '\n',
                KeyCode::Down => 'j',
                KeyCode::Up => 'k',
                KeyCode::Esc => 'q',
                _ => continue,
            };
            match state.on_key(c) {
                Action::Quit => return Ok(()),
                Action::Jump(id) => {
                    if let Some(ev) = state.events.iter().find(|e| e.id == id) {
                        if let Some(pane) = ev.location.clone() {
                            let _ = tmux::jump_to(&pane);
                            let _ = spool.dismiss_source(&ev.source);
                        }
                    }
                    return Ok(());
                }
                Action::Dismiss(id) => {
                    let _ = spool.dismiss_id(&id);
                    state.events.retain(|e| e.id != id);
                    if state.selected >= state.events.len() {
                        state.selected = state.events.len().saturating_sub(1);
                    }
                    if state.events.is_empty() {
                        return Ok(());
                    }
                }
                Action::DismissAll => {
                    let _ = spool.dismiss_all();
                    return Ok(());
                }
                Action::None => {}
            }
        }
    }
}

fn draw(f: &mut Frame, state: &TuiState, panes: &std::collections::HashMap<String, tmux::PaneInfo>) {
    let items: Vec<ListItem> = state.events.iter().rev().map(|e| {
        let loc = e.location.as_deref().and_then(|p| panes.get(p)).map(|i| format!("w{}", i.window)).unwrap_or_default();
        ListItem::new(format!("{} {:<6} {:<4} {}", e.level.glyph(), e.source, loc, e.message))
    }).collect();
    let title = format!(" inbox  {} ", state.events.len());
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(title))
        .highlight_symbol("\u{276f} ");
    let mut ls = ListState::default();
    // events render newest-first (reversed), so translate selected index.
    if !state.events.is_empty() {
        ls.select(Some(state.events.len() - 1 - state.selected));
    }
    f.render_stateful_widget(list, f.area(), &mut ls);
}
```

- [ ] **Step 4: Verify it builds**

Run: `cargo build`
Expected: compiles (the TUI loop is not unit-tested).

- [ ] **Step 5: Commit**

```bash
git add src/tui.rs
git commit -m "feat: ratatui popup state machine and event loop"
```

---

## Task 11: tmux-inbox config (Codex chain storage)

**Files:**
- Modify: `src/config.rs`

- [ ] **Step 1: Write failing tests**

Replace `src/config.rs` with:

```rust
//! tmux-inbox's own config (currently: the Codex notify command we chain to).

use serde::{Deserialize, Serialize};
use std::fs;
use std::io;
use std::path::PathBuf;

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Config {
    /// The pre-existing Codex `notify` program we forward to, if any.
    #[serde(default)]
    pub codex_chain: Option<Vec<String>>,
}

pub fn config_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("tmux-inbox")
        .join("config.toml")
}

pub fn load_from(path: &std::path::Path) -> Config {
    match fs::read_to_string(path) {
        Ok(s) => toml::from_str(&s).unwrap_or_default(),
        Err(_) => Config::default(),
    }
}

pub fn save_to(path: &std::path::Path, cfg: &Config) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let s = toml::to_string(cfg).map_err(io::Error::other)?;
    fs::write(path, s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrips_chain() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("config.toml");
        let cfg = Config { codex_chain: Some(vec!["my-notify".into(), "--flag".into()]) };
        save_to(&path, &cfg).unwrap();
        assert_eq!(load_from(&path), cfg);
    }

    #[test]
    fn missing_file_is_default() {
        let tmp = tempfile::tempdir().unwrap();
        assert_eq!(load_from(&tmp.path().join("none.toml")), Config::default());
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test config::tests`
Expected: 2 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/config.rs
git commit -m "feat: tmux-inbox config file for Codex chain"
```

---

## Task 12: Hook payload parsing

**Files:**
- Modify: `src/hooks.rs`

These pure functions turn harness payloads into an `Event`; the CLI handlers (Task 15) publish them and forward the Codex chain.

- [ ] **Step 1: Write failing tests**

Replace `src/hooks.rs` with:

```rust
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
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test hooks::tests`
Expected: 5 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/hooks.rs
git commit -m "feat: Claude and Codex hook payload parsing"
```

---

## Task 13: Claude installer (settings.json merge)

**Files:**
- Modify: `src/install.rs`

- [ ] **Step 1: Write failing tests**

Replace `src/install.rs` with:

```rust
//! Installers: merge hooks into Claude settings.json and chain Codex notify.

use serde_json::{json, Value};

/// The hook command strings tmux-inbox installs into Claude settings.
fn claude_hook_block(bin: &str, event_arg: &str) -> Value {
    json!({
        "hooks": [ { "type": "command", "command": format!("{bin} claude-hook {event_arg}") } ]
    })
}

/// Merge our Notification + Stop hooks into an existing settings JSON object.
/// Idempotent: running twice does not duplicate our entries. Returns true if changed.
pub fn merge_claude(settings: &mut Value, bin: &str) -> bool {
    if !settings.is_object() {
        *settings = json!({});
    }
    let obj = settings.as_object_mut().unwrap();
    let hooks = obj.entry("hooks").or_insert_with(|| json!({}));
    if !hooks.is_object() {
        *hooks = json!({});
    }
    let hooks = hooks.as_object_mut().unwrap();

    let mut changed = false;
    for (event_name, event_arg) in [("Notification", "notification"), ("Stop", "stop")] {
        let marker = format!("{bin} claude-hook {event_arg}");
        let arr = hooks.entry(event_name).or_insert_with(|| json!([]));
        if !arr.is_array() {
            *arr = json!([]);
        }
        let arr = arr.as_array_mut().unwrap();
        let already = arr.iter().any(|group| {
            group.get("hooks").and_then(|h| h.as_array()).map(|hs| {
                hs.iter().any(|h| h.get("command").and_then(|c| c.as_str()) == Some(marker.as_str()))
            }).unwrap_or(false)
        });
        if !already {
            arr.push(claude_hook_block(bin, event_arg));
            changed = true;
        }
    }
    changed
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merge_into_empty_adds_both_hooks() {
        let mut s = json!({});
        assert!(merge_claude(&mut s, "tmux-inbox"));
        let text = serde_json::to_string(&s).unwrap();
        assert!(text.contains("claude-hook notification"));
        assert!(text.contains("claude-hook stop"));
    }

    #[test]
    fn merge_is_idempotent() {
        let mut s = json!({});
        merge_claude(&mut s, "tmux-inbox");
        let changed_second = merge_claude(&mut s, "tmux-inbox");
        assert!(!changed_second, "second merge makes no change");
        let count = serde_json::to_string(&s).unwrap().matches("claude-hook notification").count();
        assert_eq!(count, 1, "no duplicate notification hook");
    }

    #[test]
    fn merge_preserves_existing_unrelated_hooks() {
        let mut s = json!({ "hooks": { "Notification": [ { "hooks": [ { "type": "command", "command": "other-tool" } ] } ] } });
        merge_claude(&mut s, "tmux-inbox");
        let text = serde_json::to_string(&s).unwrap();
        assert!(text.contains("other-tool"), "existing hook kept");
        assert!(text.contains("claude-hook notification"), "ours added");
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test install::tests`
Expected: 3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/install.rs
git commit -m "feat: Claude settings.json hook merge"
```

---

## Task 14: Codex installer (config.toml chain)

**Files:**
- Modify: `src/install.rs`

- [ ] **Step 1: Write failing tests**

Add to `src/install.rs` (above the `tests` module):

```rust
use crate::config::Config;

/// Outcome of computing the Codex install edit.
#[derive(Debug, PartialEq, Eq)]
pub struct CodexPlan {
    /// New value for the `notify` key in config.toml.
    pub notify: Vec<String>,
    /// Updated tmux-inbox config (records a chained command if one existed).
    pub config: Config,
}

/// Compute how to edit Codex config: install our notify program, chaining any existing one.
/// `existing_notify` is the current `notify` array from config.toml (if present).
pub fn plan_codex(bin: &str, existing_notify: Option<Vec<String>>, mut cfg: Config) -> CodexPlan {
    let ours = vec![bin.to_string(), "codex-hook".to_string()];
    match existing_notify {
        // Already us (possibly already chaining): leave chain as-is.
        Some(ref cur) if cur.first().map(|s| s.as_str()) == Some(bin) => {
            CodexPlan { notify: ours, config: cfg }
        }
        // A different existing notifier: record it as the chain target.
        Some(other) if !other.is_empty() => {
            cfg.codex_chain = Some(other);
            CodexPlan { notify: ours, config: cfg }
        }
        // None or empty: fresh install.
        _ => CodexPlan { notify: ours, config: cfg },
    }
}
```

Add these tests inside the `tests` module:

```rust
    use crate::config::Config;

    #[test]
    fn fresh_codex_install_sets_notify_no_chain() {
        let plan = plan_codex("tmux-inbox", None, Config::default());
        assert_eq!(plan.notify, vec!["tmux-inbox", "codex-hook"]);
        assert_eq!(plan.config.codex_chain, None);
    }

    #[test]
    fn existing_notifier_is_chained() {
        let plan = plan_codex("tmux-inbox", Some(vec!["my-notify".into(), "-x".into()]), Config::default());
        assert_eq!(plan.notify, vec!["tmux-inbox", "codex-hook"]);
        assert_eq!(plan.config.codex_chain, Some(vec!["my-notify".to_string(), "-x".to_string()]));
    }

    #[test]
    fn reinstall_does_not_chain_ourselves() {
        let plan = plan_codex("tmux-inbox", Some(vec!["tmux-inbox".into(), "codex-hook".into()]), Config::default());
        assert_eq!(plan.config.codex_chain, None, "never chain to ourselves");
    }
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cargo test install::tests`
Expected: 6 tests pass (3 from Task 13 + 3 new).

- [ ] **Step 3: Commit**

```bash
git add src/install.rs
git commit -m "feat: Codex notify chain planning"
```

---

## Task 15: CLI wiring — define commands and dispatch

**Files:**
- Modify: `src/main.rs`

This task connects every module to the CLI. Handlers are kept thin.

- [ ] **Step 1: Replace `src/main.rs` with the full CLI**

```rust
mod event;
mod spool;
mod tmux;
mod status;
mod menu;
mod tui;
mod hooks;
mod install;
mod config;

use clap::{Parser, Subcommand};
use event::{Event, Level};
use spool::Spool;
use std::io::Read;
use std::process::Command;

#[derive(Parser)]
#[command(name = "tmux-inbox", about = "A notification inbox for the tmux status bar")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Publish an event into the inbox.
    Notify {
        message: String,
        #[arg(long, default_value = "note")]
        from: String,
        #[arg(long, default_value = "info")]
        level: String,
        #[arg(long)]
        ttl: Option<u64>,
        #[arg(long)]
        pane: Option<String>,
    },
    /// Render the status-bar widget string.
    Status {
        #[arg(long, default_value_t = 40)]
        max_width: usize,
    },
    /// Open the quick `display-menu`.
    Menu,
    /// Open the full triage popup (run inside display-popup).
    Tui {
        #[arg(long)]
        here: bool,
    },
    /// Remove events by id, all, or source.
    Dismiss {
        id: Option<String>,
        #[arg(long)]
        all: bool,
        #[arg(long)]
        source: Option<String>,
    },
    /// Jump to an event's source pane and clear that source's events.
    Jump { id: String },
    /// Configure a harness or print tmux bindings.
    Install {
        #[arg(value_parser = ["claude", "codex", "tmux"])]
        target: String,
    },
    /// Internal: handle a Claude hook (reads JSON on stdin).
    ClaudeHook {
        #[arg(value_parser = ["notification", "stop"])]
        event: String,
    },
    /// Internal: handle a Codex notify payload (JSON arg) and forward the chain.
    CodexHook { payload: String },
}

fn main() {
    let cli = Cli::parse();
    let code = match run(cli.cmd) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("tmux-inbox: {e}");
            1
        }
    };
    std::process::exit(code);
}

fn run(cmd: Cmd) -> anyhow::Result<()> {
    match cmd {
        Cmd::Notify { message, from, level, ttl, pane } => cmd_notify(message, from, level, ttl, pane),
        Cmd::Status { max_width } => cmd_status(max_width),
        Cmd::Menu => cmd_menu(),
        Cmd::Tui { here } => cmd_tui(here),
        Cmd::Dismiss { id, all, source } => cmd_dismiss(id, all, source),
        Cmd::Jump { id } => cmd_jump(id),
        Cmd::Install { target } => cmd_install(&target),
        Cmd::ClaudeHook { event } => cmd_claude_hook(&event),
        Cmd::CodexHook { payload } => cmd_codex_hook(&payload),
    }
}

fn bin_name() -> String {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
        .unwrap_or_else(|| "tmux-inbox".to_string())
}

fn cmd_notify(message: String, from: String, level: String, ttl: Option<u64>, pane: Option<String>) -> anyhow::Result<()> {
    let level = Level::parse(&level).ok_or_else(|| anyhow::anyhow!("invalid level: {level}"))?;
    let location = pane.or_else(tmux::current_pane);
    let ttl = ttl.unwrap_or_else(|| level.default_ttl());
    let ev = Event::new(message, from, location, level, ttl);
    Spool::open()?.publish(&ev)?;
    tmux::refresh_status();
    Ok(())
}

fn cmd_status(max_width: usize) -> anyhow::Result<()> {
    let spool = Spool::open()?;
    let events = spool.list(event::now_secs())?;
    let panes = tmux::pane_map();
    print!("{}", status::render(&events, &panes, max_width));
    Ok(())
}

fn cmd_menu() -> anyhow::Result<()> {
    let spool = Spool::open()?;
    let events = spool.list(event::now_secs())?;
    if events.is_empty() {
        return Ok(());
    }
    let panes = tmux::pane_map();
    let args = menu::build_menu_args(&events, &panes, &bin_name());
    let mut cmd = Command::new("tmux");
    cmd.arg("display-menu");
    cmd.args(args);
    cmd.status()?;
    Ok(())
}

fn cmd_tui(here: bool) -> anyhow::Result<()> {
    let spool = Spool::open()?;
    tui::run(&spool, &bin_name(), here)?;
    Ok(())
}

fn cmd_dismiss(id: Option<String>, all: bool, source: Option<String>) -> anyhow::Result<()> {
    let spool = Spool::open()?;
    if all {
        spool.dismiss_all()?;
    } else if let Some(s) = source {
        spool.dismiss_source(&s)?;
    } else if let Some(id) = id {
        spool.dismiss_id(&id)?;
    } else {
        anyhow::bail!("dismiss needs an id, --all, or --source");
    }
    tmux::refresh_status();
    Ok(())
}

fn cmd_jump(id: String) -> anyhow::Result<()> {
    let spool = Spool::open()?;
    let events = spool.list(event::now_secs())?;
    let ev = events.iter().find(|e| e.id == id);
    match ev {
        Some(ev) => {
            if let Some(pane) = ev.location.clone() {
                let jumped = tmux::jump_to(&pane).unwrap_or(false);
                if !jumped {
                    eprintln!("tmux-inbox: target pane {pane} no longer exists; dismissing entry");
                    spool.dismiss_id(&id)?;
                } else {
                    spool.dismiss_source(&ev.source)?;
                }
            } else {
                spool.dismiss_id(&id)?;
            }
        }
        None => spool.dismiss_id(&id).map(|_| ())?,
    }
    tmux::refresh_status();
    Ok(())
}

fn cmd_claude_hook(event: &str) -> anyhow::Result<()> {
    let mut stdin = String::new();
    let _ = std::io::stdin().read_to_string(&mut stdin);
    let location = tmux::current_pane();
    let ev = hooks::claude_event(event, &stdin, location);
    Spool::open()?.publish(&ev)?;
    tmux::refresh_status();
    Ok(())
}

fn cmd_codex_hook(payload: &str) -> anyhow::Result<()> {
    let location = tmux::current_pane();
    if let Some(ev) = hooks::codex_event(payload, location) {
        Spool::open()?.publish(&ev)?;
        tmux::refresh_status();
    }
    // Forward to a chained notifier if configured.
    let cfg = config::load_from(&config::config_path());
    if let Some(chain) = cfg.codex_chain {
        if let Some((prog, rest)) = chain.split_first() {
            let _ = Command::new(prog).args(rest).arg(payload).status();
        }
    }
    Ok(())
}

fn cmd_install(target: &str) -> anyhow::Result<()> {
    match target {
        "claude" => install::run_claude(&bin_name()),
        "codex" => install::run_codex(&bin_name()),
        "tmux" => {
            print!("{}", install::tmux_snippet(&bin_name()));
            Ok(())
        }
        _ => anyhow::bail!("unknown target {target}"),
    }
}
```

- [ ] **Step 2: Add the install runners + tmux snippet to `src/install.rs`**

Add above the `tests` module in `src/install.rs`:

```rust
use crate::config;
use std::fs;
use std::io::{self, Write};

/// Prompt the user to confirm a change after showing a diff/summary.
fn confirm(prompt: &str) -> bool {
    print!("{prompt} [y/N] ");
    let _ = io::stdout().flush();
    let mut line = String::new();
    if io::stdin().read_line(&mut line).is_err() {
        return false;
    }
    matches!(line.trim(), "y" | "Y" | "yes")
}

pub fn run_claude(bin: &str) -> anyhow::Result<()> {
    let path = dirs::home_dir()
        .ok_or_else(|| anyhow::anyhow!("cannot resolve home dir"))?
        .join(".claude")
        .join("settings.json");

    let mut settings: Value = match fs::read_to_string(&path) {
        Ok(s) => serde_json::from_str(&s).unwrap_or_else(|_| serde_json::json!({})),
        Err(_) => serde_json::json!({}),
    };

    let before = serde_json::to_string_pretty(&settings).unwrap_or_default();
    if !merge_claude(&mut settings, bin) {
        println!("Claude hooks already installed at {}", path.display());
        return Ok(());
    }
    let after = serde_json::to_string_pretty(&settings).unwrap_or_default();
    println!("Will update {}:\n--- before\n{before}\n--- after\n{after}", path.display());
    if !confirm("Apply?") {
        println!("Aborted.");
        return Ok(());
    }
    if path.exists() {
        let _ = fs::copy(&path, path.with_extension("json.bak"));
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, format!("{after}\n"))?;
    println!("Installed. Backup (if any) at settings.json.bak");
    Ok(())
}

pub fn run_codex(bin: &str) -> anyhow::Result<()> {
    let path = dirs::home_dir()
        .ok_or_else(|| anyhow::anyhow!("cannot resolve home dir"))?
        .join(".codex")
        .join("config.toml");

    let mut doc: toml::Table = match fs::read_to_string(&path) {
        Ok(s) => toml::from_str(&s).unwrap_or_default(),
        Err(_) => toml::Table::new(),
    };

    let existing: Option<Vec<String>> = doc.get("notify").and_then(|v| {
        v.as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(|s| s.to_string())).collect())
    });

    let cfg = config::load_from(&config::config_path());
    let plan = plan_codex(bin, existing, cfg);

    println!("Will set Codex notify = {:?} in {}", plan.notify, path.display());
    if let Some(ref chain) = plan.config.codex_chain {
        println!("Existing notifier will be chained: {chain:?}");
    }
    if !confirm("Apply?") {
        println!("Aborted.");
        return Ok(());
    }

    if path.exists() {
        let _ = fs::copy(&path, path.with_extension("toml.bak"));
    }
    let notify_arr: toml::Value = toml::Value::Array(plan.notify.iter().map(|s| toml::Value::String(s.clone())).collect());
    doc.insert("notify".to_string(), notify_arr);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, toml::to_string(&doc).map_err(|e| anyhow::anyhow!(e))?)?;
    config::save_to(&config::config_path(), &plan.config)?;
    println!("Installed. Backup (if any) at config.toml.bak");
    Ok(())
}

/// tmux.conf lines the user adds to wire up the inbox.
pub fn tmux_snippet(bin: &str) -> String {
    format!(
        "# tmux-inbox — add to ~/.tmux.conf\n\
         set -g status-interval 2\n\
         set -g status-left '#({bin} status --max-width 40) '\n\
         set -g status-left-length 50\n\
         bind i run-shell '{bin} menu'\n\
         bind I display-popup -E '{bin} tui'\n"
    )
}
```

- [ ] **Step 3: Verify it builds and all tests pass**

Run: `cargo build && cargo test`
Expected: builds; all unit tests from Tasks 2–14 pass.

- [ ] **Step 4: Commit**

```bash
git add src/main.rs src/install.rs
git commit -m "feat: wire up CLI dispatch and install runners"
```

---

## Task 16: End-to-end smoke test (publish → status → dismiss)

**Files:**
- Create: `tests/cli.rs`

- [ ] **Step 1: Write the failing integration test**

```rust
//! End-to-end CLI test using an isolated spool dir via XDG_RUNTIME_DIR.

use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_tmux-inbox")
}

#[test]
fn notify_then_status_then_dismiss_all() {
    let tmp = tempfile::tempdir().unwrap();

    // publish (no tmux context: refresh + pane map fail silently)
    let out = Command::new(bin())
        .args(["notify", "build finished", "--from", "build", "--level", "done"])
        .env("XDG_RUNTIME_DIR", tmp.path())
        .env_remove("TMUX_PANE")
        .output()
        .unwrap();
    assert!(out.status.success(), "notify failed: {}", String::from_utf8_lossy(&out.stderr));

    // status shows the event
    let out = Command::new(bin())
        .args(["status"])
        .env("XDG_RUNTIME_DIR", tmp.path())
        .output()
        .unwrap();
    let s = String::from_utf8_lossy(&out.stdout);
    assert!(s.contains("build"), "status missing source: {s:?}");
    assert!(s.contains('1'), "status missing count: {s:?}");

    // dismiss all empties it
    Command::new(bin())
        .args(["dismiss", "--all"])
        .env("XDG_RUNTIME_DIR", tmp.path())
        .output()
        .unwrap();
    let out = Command::new(bin())
        .args(["status"])
        .env("XDG_RUNTIME_DIR", tmp.path())
        .output()
        .unwrap();
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "");
}
```

- [ ] **Step 2: Run the test**

Run: `cargo test --test cli`
Expected: passes (the spool lives under the temp `XDG_RUNTIME_DIR`; tmux shell-outs fail harmlessly off-tmux).

- [ ] **Step 3: Commit**

```bash
git add tests/cli.rs
git commit -m "test: end-to-end notify/status/dismiss CLI smoke test"
```

---

## Task 17: Manual verification in real tmux + README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Build release binary**

Run: `cargo build --release`
Expected: produces `target/release/tmux-inbox`.

- [ ] **Step 2: Wire it into the live tmux config**

Run: `./target/release/tmux-inbox install tmux`
Add the printed lines to `~/.tmux.conf` (point `status-left` at the absolute path of the release binary, or put the binary on `$PATH`), then `tmux source-file ~/.tmux.conf`.

- [ ] **Step 3: Manually verify the full loop**

From inside a tmux pane:
```bash
tmux-inbox notify "waiting for input" --from claude --level attn
```
Confirm each of:
- The status bar shows the badge with the bell glyph, count `1`, source, window label, and message (truncated to budget).
- `prefix + i` opens the menu; selecting the entry switches to this pane.
- `prefix + I` opens the popup; `j/k` navigate, `d` dismisses, `D` clears all, `q`/`Esc` close.
- After jumping, that source's entries are cleared (publish two `attn` from the same pane, jump once, confirm both gone).
- Publish an `info` with `--ttl 2`, wait 3s, run a status refresh, confirm it auto-expired.

- [ ] **Step 4: Optionally install the harness hooks**

Run: `tmux-inbox install claude` and `tmux-inbox install codex`, review each diff, apply. Trigger a Claude `Stop`/`Notification` and a Codex turn completion; confirm entries appear.

- [ ] **Step 5: Write `README.md`**

```markdown
# tmux-inbox

A notification inbox in the tmux status bar. Services (Claude Code, Codex, scripts) publish events into a spool directory; they surface as a compact status-bar badge and a persistent log you triage via tmux menu/popup.

## Install

    cargo build --release
    ./target/release/tmux-inbox install tmux   # prints ~/.tmux.conf lines

Put `tmux-inbox` on your `$PATH`, add the printed lines to `~/.tmux.conf`, and `tmux source-file ~/.tmux.conf`.

## Publish events

    tmux-inbox notify "waiting for input" --from claude --level attn
    tmux-inbox notify "build done" --from build --level done --ttl 300

Levels: `attn` (sticky, needs you), `info`, `done` (both auto-expire after 5 min by default). Location is captured from `$TMUX_PANE` so the inbox can jump to the source.

## Keys

- `prefix + i` — quick menu; select an entry to jump to its pane.
- `prefix + I` — triage popup: `j/k` move, `Enter` jump, `d` dismiss, `D` clear all, `q` close.

Jumping to an entry clears all pending entries from that source.

## Harness integration

    tmux-inbox install claude   # merges Notification + Stop hooks into ~/.claude/settings.json
    tmux-inbox install codex    # sets notify in ~/.codex/config.toml (chains any existing notifier)

Both show a diff and ask before writing, and back up the original file.

## Storage

One JSON file per event under `$XDG_RUNTIME_DIR/tmux-inbox/`. No daemon. Expired entries are pruned lazily on read.
```

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: add README and manual verification notes"
```

---

## Self-Review Notes (for the implementer)

- **Spec coverage:** hybrid model + append-only log (Tasks 4–6), event anatomy & levels/glyphs (Tasks 2–3), spool storage + lazy expiry (Tasks 4–5), status widget (Task 8), quick menu + popup (Tasks 9–10), auto-dismiss on jump (Tasks 10, 15 `cmd_jump`), Claude hooks (Tasks 12–13), Codex chain (Tasks 12, 14), confirm/diff install (Task 15), best-effort refresh (Task 7 + handlers), error handling for missing tmux/corrupt files/stale panes (Tasks 5, 7, 15).
- **Type consistency:** `Spool` methods (`publish`/`list`/`dismiss_id`/`dismiss_all`/`dismiss_source`), `Level::{glyph,default_ttl,parse,as_str}`, `Event::{new,is_expired}`, `tmux::{current_pane,refresh_status,pane_map,jump_to,PaneInfo}`, `status::render`, `menu::build_menu_args`, `tui::{TuiState,Action,run}`, `hooks::{claude_event,codex_event}`, `install::{merge_claude,plan_codex,run_claude,run_codex,tmux_snippet}`, `config::{Config,load_from,save_to,config_path}` are referenced consistently across tasks.
- **YAGNI:** no read/unread, no DND, no daemon — all deferred per spec.
```
