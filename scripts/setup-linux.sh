#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)

. "$repo_root/scripts/common.sh"

case "$(uname -s)" in
  Linux) ;;
  *)
    die "setup-linux.sh must be run on Linux"
    ;;
esac

ensure_symlink "$HOME/.config/nvim" "$repo_root/config/nvim"
ensure_symlink "$HOME/.config/starship.toml" "$repo_root/config/starship.toml"
# Common, cross-machine zsh settings. The machine-specific ~/.zshrc stays local
# (uncommitted) and should `source ~/.zshrc.max-dotfiles`.
ensure_symlink "$HOME/.zshrc.max-dotfiles" "$repo_root/zsh/.zshrc.max-dotfiles"
ensure_symlink "$HOME/.tmux.conf" "$repo_root/tmux/tmux.conf"
ensure_symlink "$HOME/.tmux" "$repo_root/tmux/tmux"
ensure_tmux_plugins "$repo_root/tmux/tmux/plugins"

chmod +x "$repo_root/tmux/tmux/battery-status.sh"
chmod +x "$script_dir/setup-macos.sh" "$script_dir/setup-linux.sh" "$repo_root/scripts/common.sh"

log "Linux dotfiles bootstrap complete"
