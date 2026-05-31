#!/bin/sh
# pane-label.sh — styled tmux pane-border labels, color-coded by command.
#
# Modes:
#   label <cmd> <active> <path> <zoomed> <title> <host>
#   color <cmd>     -> prints "#RRGGBB" for the active pane's border line
#
# Color + icon are chosen from the foreground command. The text is the pane's
# title when it's meaningful (your Prefix+T names AND Claude Code task
# summaries), otherwise the cwd basename + git branch. Monitors stay
# path-free. On the active pane the identity is in its command color (bold)
# and context is neutral gray; inactive panes recede to a single dim gray.
#
# Nerd Font glyphs are stored as octal-escaped UTF-8 (kept pure-ASCII so they
# survive editing) and rebuilt at runtime with `printf %b`.

mode="$1"
cmd="$2"

# Rebuild a glyph from its octal-escaped UTF-8.
g() { printf '%b' "$1"; }

# --- command -> color + icon + kind ----------------------------------------
# kind: other (cmd + cwd + branch) | shell (cwd + branch) | monitor (cmd only)
color='#939293'; icon='\0357\0200\0223'; kind='other'   # fallback: dim gray, cog
case "$cmd" in
  nvim|vim|vi|vimdiff)                  color='#FFD866'; icon='\0356\0230\0253' ;;  # vim (yellow)
  hx|helix|nano|micro|kak|emacs)        color='#FFD866'; icon='\0357\0201\0204' ;;  # edit
  zsh|bash|sh|dash|ksh|fish|nu)         color='#A9DC76'; icon='\0357\0222\0211'; kind='shell' ;;  # terminal (green)
  git|tig|gh|jj|lazygit|gitui)          color='#FC9867'; icon='\0356\0234\0245' ;;  # branch (orange)
  htop|btop|top|glances|bmon|nvtop)     color='#FF6188'; icon='\0357\0203\0244'; kind='monitor' ;;  # dashboard (pink)
  watch|journalctl|tail|dmesg)          color='#FF6188'; icon='\0357\0201\0256'; kind='monitor' ;;  # eye
  ping|mtr|dig)                         color='#FF6188'; icon='\0357\0200\0222'; kind='monitor' ;;  # signal
  python|python3|ipython)               color='#78DCE8'; icon='\0356\0234\0274' ;;  # python (cyan)
  node|deno|bun)                        color='#78DCE8'; icon='\0356\0234\0230' ;;  # node
  ruby|irb)                             color='#78DCE8'; icon='\0356\0234\0271' ;;  # ruby
  lua|luajit|julia|R|php|perl|ghci)     color='#78DCE8'; icon='\0357\0204\0241' ;;  # code
  ssh|mosh|kubectl|k9s|helm|terraform|ansible|vagrant) color='#AB9DF2'; icon='\0357\0210\0263' ;;  # server (purple)
  docker|podman)                        color='#AB9DF2'; icon='\0357\0214\0210' ;;  # docker
  less|man|bat|more)                    color='#939293'; icon='\0357\0200\0255'; kind='monitor' ;;  # book (gray)
  claude)                               color='#D97757'; icon='\0357\0203\0220'; kind='agent' ;;  # magic (coral)
  codex)                                color='#2BC4A0'; icon='\0357\0204\0241'; kind='agent' ;;  # code (teal)
esac

# --- color mode (active border) --------------------------------------------
if [ "$mode" = "color" ]; then
  printf '%s' "$color"
  exit 0
fi

# --- label mode ------------------------------------------------------------
active="$3"; path="$4"; zoomed="$5"; title="$6"; host="$7"

icon="$(g "$icon")"
GF="$(g '\0357\0201\0274')"   # cwd (folder)
GB="$(g '\0356\0234\0245')"   # git branch
GZ="$(g '\0357\0201\0245')"   # zoom (expand)

# Style sets: identity (main) vs context (dim).
if [ "$active" = "1" ]; then
  main="#[fg=${color},bold]"
  dim="#[fg=#939293,nobold]"
else
  main="#[fg=#727072,nobold]"
  dim="#[fg=#727072,nobold]"
fi

# Escape literal '#' so titles like "Fix #42" aren't read as tmux markup.
esc() { printf '%s' "$1" | sed 's/#/##/g'; }

# Stale "/path (deleted)" -> "/path", then basename.
path="${path% (deleted)}"
base="${path##*/}"
[ -z "$base" ] && base='/'

if [ -n "$title" ] && [ "$title" != "$host" ]; then
  # Meaningful title (Prefix+T name or Claude task summary). Truncate long ones.
  if [ "${#title}" -gt 48 ]; then
    title="$(printf '%.47s' "$title")…"
  fi
  body="${main}${icon} $(esc "$title")"
else
  branch=''
  [ "$kind" != "monitor" ] && branch="$(git -C "$path" symbolic-ref --short -q HEAD 2>/dev/null)"
  base="$(esc "$base")"
  case "$kind" in
    shell)
      body="${main}${icon} ${base}"
      [ -n "$branch" ] && body="${body} ${dim}${GB} ${branch}"
      ;;
    monitor)
      body="${main}${icon} ${cmd}"
      ;;
    *)
      body="${main}${icon} ${cmd} ${dim}${GF} ${base}"
      [ -n "$branch" ] && body="${body}  ${GB} ${branch}"
      ;;
  esac
fi

# Zoom badge.
[ "$zoomed" = "1" ] && body="${body} ${main}${GZ}"

printf ' %s #[default]' "$body"
