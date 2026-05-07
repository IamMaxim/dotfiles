#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)

. "$repo_root/scripts/common.sh"

case "$(uname -s)" in
  Darwin) ;;
  *)
    die "setup-macos.sh must be run on macOS"
    ;;
esac

ensure_symlink "$HOME/.config/nvim" "$repo_root/config/nvim"
ensure_symlink "$HOME/.tmux.conf" "$repo_root/tmux/tmux.conf"
ensure_symlink "$HOME/.tmux" "$repo_root/tmux/tmux"
ensure_tmux_plugins "$repo_root/tmux/tmux/plugins"

chmod +x "$repo_root/tmux/tmux/battery-status.sh"
chmod +x "$script_dir/setup-macos.sh" "$script_dir/setup-linux.sh" "$repo_root/scripts/common.sh"

log "macOS dotfiles bootstrap complete"
