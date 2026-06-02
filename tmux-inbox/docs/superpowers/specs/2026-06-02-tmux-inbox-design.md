# tmux-inbox — Design

**Date:** 2026-06-02
**Status:** Approved (v1)

## Summary

`tmux-inbox` is a notification "inbox" rendered in the left side of the tmux
status bar. Services — primarily AI coding harnesses like Claude Code and
Codex, but also arbitrary scripts — publish events into a spool directory. The
events surface as a compact status-bar badge and accumulate into a persistent,
chronological log the user can review and triage through tmux popups.

The whole system is a single Rust binary plus tmux configuration. No daemon, no
network IPC, no background timer.

## Goals

- Let any process announce "I need your attention" (or "I finished") from
  within a tmux pane, with near-zero latency on the publish path.
- Show a minimal, width-constrained, always-visible indicator in the status bar.
- Keep a persistent log so events that arrive while the user is away aren't lost.
- Make "jump to the pane that needs me" a one-keystroke action.
- Be robust and simple: crash-safe, concurrency-safe, no process to supervise.

## Non-goals (v1)

- Read/unread tracking (items are only *pending* or *dismissed*).
- Do-not-disturb / muting.
- Per-session inbox silos (one global inbox, location-tagged).
- A background daemon or timer.
- Cross-host / networked notifications.

## Core model

**Hybrid surfacing over an append-only log.**

- Every published event is a **distinct entry** (append-only; no coalescing by
  source). The inbox is a chronological feed.
- Entries are **persistent** until dismissed or auto-expired by TTL.
- The status bar surfaces a **count + the newest entry** (the "live" feel);
  the full log lives behind popups.

### Event anatomy

| field      | origin                                   | notes |
|------------|------------------------------------------|-------|
| `message`  | required                                 | the text, e.g. "waiting for input" |
| `source`   | `--from` (default: `note`)               | short label: `claude`, `codex`, `build`; hooks always pass `--from` explicitly |
| `location` | auto from `$TMUX_PANE`; overridable      | `session:window.pane`; enables jump-to-source. Absent ⇒ not jumpable |
| `level`    | `--level` (default `info`)               | `info` / `attn` / `done` — selects the glyph and default TTL |
| `ttl`      | `--ttl` (default by level)               | seconds until lazy auto-expiry; `0` = sticky until dismissed |
| `id`       | auto                                      | unique; also the spool filename |
| `time`     | auto                                      | creation timestamp |

### Levels

| level  | meaning              | default TTL | glyph (nerd font) |
|--------|----------------------|-------------|-------------------|
| `attn` | needs you            | `0` (sticky)| `` (nf-md-bell_alert / U+F009C) |
| `info` | informational        | 300s        | `` (nf-md-information / U+F02FC) |
| `done` | finished, FYI        | 300s        | `` (nf-md-check_circle / U+F05E0) |

Glyphs are monochrome nerd-font symbols (no color emoji). Exact codepoints may
be tuned during implementation; the binary owns the mapping.

## Architecture

Single Rust binary (`tmux-inbox`) with subcommands. `ratatui` for the popup TUI.
Rust chosen for fast cold start (the status renderer runs on every status
refresh) and a self-contained binary bundling CLI + status renderer + TUI +
installers — no `fzf` or other runtime dependency.

### Storage: spool directory (maildir-style)

- Location: `$XDG_RUNTIME_DIR/tmux-inbox/` (fallback `$TMPDIR` / `/tmp/tmux-inbox-$UID`).
- One file per event, named by `id` (sortable, e.g. `<unix_nanos>-<rand>.json`),
  containing the event fields as JSON.
- **Publish** = write a temp file then atomically `rename(2)` into place.
- **Dismiss** = delete (or move to a short-lived `dismissed/` tomb, then unlink).
- **List** = read the directory, sort by id/time.
- Concurrency-safe by construction: every producer writes a uniquely-named file;
  no shared mutable file, no locking.

### Expiry

Lazy. Any reader (status renderer or popup) prunes files whose `ttl != 0` and
`now - time > ttl` as it scans. No timer, no daemon. `attn` (ttl `0`) never
auto-expires.

### Status refresh

- **Baseline:** tmux `status-interval` (~2s) re-runs the status renderer.
- **Instant push (best-effort):** the publish path calls `tmux refresh-client -S`
  after writing, so new events appear immediately when a client is attached.

## Subcommands

| subcommand                     | role |
|--------------------------------|------|
| `notify <message> [flags]`     | publish an event (the producer interface) |
| `status`                       | render the status-bar widget string (called by tmux) |
| `menu`                         | emit a `display-menu` spec / drive the quick menu |
| `tui`                          | the popup TUI (run inside `display-popup`) |
| `dismiss <id> \| --all \| --source S` | remove entries (also used by jump) |
| `jump <id>`                    | switch tmux to the entry's location, then dismiss that source's pending entries |
| `install claude \| codex`      | configure the respective harness (confirm/diff) |
| `codex-hook`                   | internal: parse Codex's JSON arg → `notify` (+ chain-forward) |

### Publish example

```
tmux-inbox notify "waiting for input" --from claude --level attn
```
`location` (from `$TMUX_PANE`) and `ttl` (from `level`) fill themselves in.
Producers with no tmux context still work — the entry just isn't jumpable.

## UX

### Status-bar widget (always visible, minimal)

Count badge + newest entry, hard-truncated; collapses toward `<glyph> N` or
nothing when width is tight. No color emoji; nerd-font glyphs only.

```
 3 claude w3:waiting…    │ session … 12:04
```

When the inbox is empty the widget renders empty (or a single dim idle glyph).

### Quick jump — `display-menu` (`prefix + i`)

Fast native menu; each entry jumps to its source pane on select.

```
┌─ inbox (3) ──────────────────┐
│ claude  w3  waiting for input │
│ codex   w1  tests 2/3 passed  │
│ build   w5  done · 0 errs     │
│───────────────────────────────│
│ Clear all                     │
└───────────────────────────────┘
```

### Full triage — `display-popup` + ratatui (`prefix + I`)

```
┌─ inbox ───────────────────────────── 3 ─┐
│ ❯  claude  w3  waiting for input   12:03 │
│    codex   w1  tests 2/3 passed    12:01 │
│    build   w5  done · 0 errs       11:58 │
│                                          │
│ enter jump · d dismiss · D all · q close │
└──────────────────────────────────────────┘
```

Keys: `j/k` navigate, `Enter` jump-to-source, `d` dismiss one, `D` dismiss all,
`q` close. A filter key narrows to the current session (`--here`).

### Auto-dismiss on jump

Jumping to a source clears that source's pending entries. This keeps triage
cheap under the append-only model, where an away-from-keyboard harness can leave
several `attn` entries (each finished turn maps to `attn`).

## Integrations

### Claude Code (`tmux-inbox install claude`)

Merges hooks into `~/.claude/settings.json`. Hooks receive JSON on stdin and
inherit `$TMUX_PANE`.

| hook           | inbox event       |
|----------------|-------------------|
| `Notification` | `attn` (sticky)   |
| `Stop`         | `attn` (sticky)   |

`SubagentStop` / `SessionStart` are skipped as noise.

### Codex (`tmux-inbox install codex`)

Codex exposes a single global `notify` program slot in `~/.codex/config.toml`,
invoked with a JSON *argument*, firing on `agent-turn-complete` → `attn`.
`$TMUX_PANE` is inherited.

```toml
notify = ["tmux-inbox", "codex-hook"]
```

If a `notify` program already exists, **chain** it: tmux-inbox becomes the
`notify` program, handles the event, then forwards the original JSON arg to the
previously-configured command (recorded in our config). Falls back to
refuse-and-warn if the existing command can't be parsed.

### Install UX (both)

Auto-edit with a **confirm/diff**: show exactly what will be added, back up the
target file, ask for confirmation, then merge.

## Data flow

```
producer (hook/script)
   └─ tmux-inbox notify ...           write temp → atomic rename into spool/
        └─ tmux refresh-client -S     best-effort instant status refresh

tmux status-interval (~2s)
   └─ tmux-inbox status               scan spool (prune expired) → badge string

prefix+i → display-menu  → tmux-inbox menu → select → tmux-inbox jump <id>
prefix+I → display-popup → tmux-inbox tui  → d/D/Enter → dismiss / jump

jump: switch-client/select-window/select-pane to location,
      then dismiss that source's pending entries.
```

## Error handling

- **No tmux context:** `notify` still writes the entry (no `location`); status
  push is skipped. Entry is non-jumpable.
- **Spool unwritable / missing:** create on demand; on hard failure, `notify`
  exits nonzero but must never block or crash the calling harness (fast, quiet).
- **Corrupt/partial spool file:** readers skip unparseable files (atomic rename
  on write makes partials unlikely).
- **Stale location (pane gone):** `jump` reports the target no longer exists and
  offers to dismiss the entry.
- **Install conflicts:** Claude merge is additive with backup; Codex chains or
  refuses (never silently clobbers an existing `notify`).

## Testing

- **Unit:** event (de)serialization, filename/id ordering, TTL/expiry logic,
  level→glyph/TTL mapping, status-string truncation/width budget, Codex JSON
  parsing.
- **Integration (spool):** publish→list→dismiss round-trips; concurrent
  publishes from multiple processes; lazy pruning of expired entries; atomic
  write leaves no partials.
- **Install:** Claude settings.json merge (idempotent, backup created); Codex
  config.toml fresh-install and chain-existing cases.
- **Manual/TUI:** ratatui popup navigation and dismiss/jump against a seeded
  spool; status widget rendering across width budgets inside real tmux.
```
