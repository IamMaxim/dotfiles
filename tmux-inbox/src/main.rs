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
