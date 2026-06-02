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
