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
    // Empty inbox renders the idle glyph (hollow bell), not nothing.
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "\u{f009a}");
}
