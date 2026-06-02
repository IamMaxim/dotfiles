# tmux-inbox

A notification inbox in the tmux status bar. Services (Claude Code, Codex, scripts) publish events into a spool directory; they surface as a compact status-bar badge and a persistent log you triage via tmux menu/popup.

## Install

This crate lives inside the dotfiles repo. The dotfiles bootstrap
(`scripts/setup-linux.sh` / `setup-macos.sh`) builds and installs it
automatically via `ensure_tmux_inbox`. To build/install it by hand:

    ./build.sh                 # build release -> ~/.local/bin/tmux-inbox -> cargo clean
    BIN_DIR=~/bin ./build.sh   # install to a different dir

`build.sh` relies on `cargo` being present, copies the binary onto your `$PATH`,
then runs `cargo clean` to reclaim disk. The tmux wiring lives in the repo's
`tmux/tmux.conf` (status-left widget + `prefix + i`/`prefix + I` bindings):

    set -g status-left '#(tmux-inbox status --max-width 40) '
    set -g status-left-length 44
    bind i run-shell 'tmux-inbox menu'
    bind I display-popup -E 'tmux-inbox tui'   # bound after tpm so it wins

`tmux-inbox install tmux` still prints a standalone snippet if you want to wire
up a different tmux config.

## Publish events

    tmux-inbox notify "waiting for input" --from claude --level attn
    tmux-inbox notify "build done" --from build --level done --ttl 300

Levels (each picks a monochrome nerd-font glyph, no color emoji):

| level  | meaning            | default TTL        |
|--------|--------------------|--------------------|
| `attn` | needs you          | sticky (no expiry) |
| `info` | informational      | 300s               |
| `done` | finished, FYI      | 300s               |

Location is captured from `$TMUX_PANE` (override with `--pane`), so the inbox can jump to the source. `--ttl 0` makes any event sticky; `--ttl N` expires it after N seconds. Producers with no tmux context still work — the entry just isn't jumpable.

## Status bar

The widget shows `<glyph> <count> <source> w<window>:<message>`, driven by the newest event, hard-truncated to the width budget, collapsing toward `<glyph> <count>` (or nothing when empty).

## Keys

- `prefix + i` — quick menu; select an entry to jump to its pane.
- `prefix + I` — triage popup: `j`/`k` move, `Enter` jump, `d` dismiss, `D` clear all, `q`/`Esc` close.

Jumping to an entry clears all pending entries from that source.

## Harness integration

    tmux-inbox install claude   # merges Notification + Stop hooks into ~/.claude/settings.json
    tmux-inbox install codex    # sets notify in ~/.codex/config.toml (chains any existing notifier)

Both show a diff/summary and ask before writing, and back up the original file (`.bak`). Claude's `Notification` and `Stop` hooks both map to a sticky `attn` event; Codex's `agent-turn-complete` maps to `attn`. If Codex already has a `notify` program, tmux-inbox chains it (forwards the payload after handling).

## Storage

One JSON file per event under `$XDG_RUNTIME_DIR/tmux-inbox/` (falls back to `$TMPDIR`/`/tmp`). Writes are atomic (temp file + rename), so concurrent producers never clobber each other. No daemon — expired entries are pruned lazily whenever the status bar or popup reads the spool.

## Development

    cargo test            # unit + integration tests
    cargo build --release

Module layout: `event` (model), `spool` (storage), `tmux` (shell-outs), `status` (widget render), `menu` (display-menu args), `tui` (ratatui popup), `hooks` (Claude/Codex payload parsing), `install` (config merge/chain), `config` (own config).
