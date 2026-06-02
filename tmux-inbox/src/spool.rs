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
}
