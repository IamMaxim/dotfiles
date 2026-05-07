#!/bin/sh

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

timestamp() {
  date +"%Y%m%d-%H%M%S"
}

backup_path() {
  printf '%s.bak.%s.%s' "$1" "$(timestamp)" "$$"
}

ensure_symlink() {
  target=$1
  source=$2
  parent=$(dirname "$target")

  mkdir -p "$parent"

  if [ -L "$target" ]; then
    current=$(readlink "$target")
    if [ "$current" = "$source" ]; then
      log "ok: $target -> $source"
      return 0
    fi
  elif [ -e "$target" ]; then
    backup=$(backup_path "$target")
    mv "$target" "$backup"
    log "backup: $target -> $backup"
  fi

  ln -s "$source" "$target"
  log "link: $target -> $source"
}

ensure_git_clone() {
  repo_url=$1
  dest=$2

  if git -C "$dest" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "ok: $dest"
    return 0
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup=$(backup_path "$dest")
    mv "$dest" "$backup"
    log "backup: $dest -> $backup"
  fi

  mkdir -p "$(dirname "$dest")"
  git clone "$repo_url" "$dest"
  log "clone: $repo_url -> $dest"
}

ensure_tmux_plugins() {
  plugin_dir=$1
  ensure_git_clone https://github.com/tmux-plugins/tpm "$plugin_dir/tpm"
  ensure_git_clone https://github.com/tmux-plugins/tmux-sensible "$plugin_dir/tmux-sensible"
}
