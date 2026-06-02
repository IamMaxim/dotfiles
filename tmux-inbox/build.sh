#!/bin/sh
# Build the tmux-inbox binary, install it onto $PATH, then reclaim disk by
# running `cargo clean`. Relies on cargo being installed (https://rustup.rs).
#
# Usage:
#   ./build.sh              # build + install to ~/.local/bin, then cargo clean
#   BIN_DIR=~/bin ./build.sh   # install elsewhere
set -eu

crate_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
bin_dir=${BIN_DIR:-$HOME/.local/bin}

if ! command -v cargo >/dev/null 2>&1; then
  printf 'error: cargo not found — install Rust from https://rustup.rs first\n' >&2
  exit 1
fi

printf 'tmux-inbox: building release binary...\n'
( cd "$crate_dir" && cargo build --release )

mkdir -p "$bin_dir"
cp "$crate_dir/target/release/tmux-inbox" "$bin_dir/tmux-inbox"
printf 'tmux-inbox: installed -> %s/tmux-inbox\n' "$bin_dir"

# Release artifacts are large and unneeded once the binary is installed.
( cd "$crate_dir" && cargo clean )
printf 'tmux-inbox: ran cargo clean (build artifacts removed)\n'

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) printf 'tmux-inbox: note: %s is not on your PATH — add it so tmux can find tmux-inbox\n' "$bin_dir" ;;
esac
