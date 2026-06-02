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

    // Refuse to clobber a notify value we don't understand (spec: never silently clobber).
    if let Some(v) = doc.get("notify") {
        if !v.is_array() {
            println!(
                "Codex `notify` in {} is set to a non-array value we can't safely chain:\n  {}\n\
                 Refusing to overwrite. Resolve it manually, then re-run `{bin} install codex`.",
                path.display(),
                v
            );
            return Ok(());
        }
    }

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;

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

    #[test]
    fn non_array_notify_is_detected_as_unsafe() {
        let doc: toml::Table = toml::from_str("notify = \"my-script\"").unwrap();
        let v = doc.get("notify").unwrap();
        assert!(!v.is_array(), "string notify must be flagged non-array");

        let doc2: toml::Table = toml::from_str("notify = [\"a\", \"b\"]").unwrap();
        assert!(doc2.get("notify").unwrap().is_array(), "array notify is safe to chain");
    }
}
