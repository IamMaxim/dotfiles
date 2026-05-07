# Neovim Setup Documentation

## Overview

This is a minimal, keyboard-first Neovim configuration optimized for coding and technical writing. It focuses on essential tools: LSP, completion, linting, and file navigation. The setup is designed to be learnable and maintainable.

---

## Quick Start

### Opening This Documentation
- Press `<leader>?` then `:` then type `view NVIM_SETUP.md` (or use `<leader>h` for which-key help)

### Essential Daily Shortcuts

**Most Used (Muscle Memory Priority):**
- `<leader>ff` - Find files
- `<leader>fg` - Live grep (search text)
- `<leader>e` - Toggle file tree
- `<space>` + key - Most commands use space (leader) prefix

---

## Plugins Installed

### Visual & Navigation
- **monokai-pro.nvim** - Color scheme
- **nvim-tree.lua** - File explorer tree on left side
- **bufferline.nvim** - Buffer tab bar across the top
- **lualine.nvim** - Statusline with git, diagnostics, file info, and cursor position
- **telescope.nvim** - Fuzzy finder for files, text, buffers
- **which-key.nvim** - Shows available keybindings (press `<leader>?` or `<leader>h`)

### Code Intelligence
- **nvim-lspconfig** - Language server protocol support (enables goto definition, references, hover docs, renaming)
- **mason.nvim** + **mason-lspconfig.nvim** - Auto-install and manage language servers
- **rustaceanvim** - Rust language tooling backed by rust-analyzer from the active toolchain
  - Rust is intentionally not installed through Mason, to avoid toolchain mismatches
  - Installed Mason servers: Lua, Markdown
- **nvim-cmp** - Autocompletion menu
- **nvim-treesitter** - Syntax highlighting and smart indentation

### Code Quality
- **conform.nvim** - Code formatter (format on save)
  - Lua: stylua
  - Rust: rustfmt
- **nvim-lint** - Linter for markdown
  - Markdownlint (if available)

### Editing Productivity
- **Comment.nvim** - Toggle comments with `gc` (visual mode friendly)
- **kylechui/nvim-surround** - Manage surrounding characters (quotes, brackets)
- **vim-markdown** - Markdown-specific plugins with **tabular** for table formatting

### Git Integration
- **gitsigns.nvim** - Shows git change markers (added/modified/deleted lines) on the left

---

## Keybindings by Category

All main commands use `<leader>` (Space) prefix for easy discoverability.

### Finding & Navigation (Telescope)
**Note:** First use of any `<leader>f` keybinding will load Telescope (lazy-loaded for performance). All searches use **fuzzy matching** (type characters in sequence; "reqre" matches "require").

```
<leader>ff   Find files (fuzzy)
<leader>fg   Live grep (fuzzy search text in files)
<leader>fb   List open buffers
<leader>fh   Search help tags
<leader>fk   Show keymaps
<leader>fd   Show diagnostics
<leader>fs   Grep word under cursor
<leader>fr   Resume last picker
```

### File Tree (nvim-tree)
```
<leader>e    Toggle file tree
<leader>E    Reveal current file in tree
```

### Buffers
```
<leader>bb   Pick a buffer from the tab bar
<leader>bc   Close the current buffer
<leader>bn   Next buffer
<leader>bp   Previous buffer
<leader>q    Close window/buffer
<leader>w    Save buffer
```

### Code (LSP & Formatting)
```
<leader>ca   Code action (rename, refactor suggestions)
<leader>lf   Format buffer
<leader>rn   Rename symbol (LSP)
<leader>l*   LSP commands group
<leader>rc   Run rust-analyzer flyCheck manually (Rust buffers)
<leader>rx   Cancel rust-analyzer flyCheck (Rust buffers)

gd           Go to definition
gr           Show references (all usages)
K            Hover documentation
```

### Markdown
```
<leader>mf   Format markdown table
<leader>ml   Lint markdown
zg           Add word to spellfile (spell checking)
```

### UI & Configuration
```
<leader>?    Show which-key help (all keybindings)
<leader>h    Show which-key help (alternative)
<leader>sv   Reload Neovim config
<M-CR>       Open action menu (context-aware)
<M-Enter>    Open action menu (alternative)
```

### Core Vim Basics (No Leader)
```
:q           Quit
:w           Write/save
:wq          Write and quit
:e <file>    Open file
:Telescope   Open telescope (fuzzy finder)
```

---

## VS Code to Vim Transition Guide

### Command Palette Equivalent
- **VS Code:** `Ctrl+Shift+P`
- **Vim:** `:` (command mode) or `<leader>?` (which-key help to browse keybindings)
- **Example:** Type `:edit myfile.lua` to open a file

### File Explorer
- **VS Code:** `Ctrl+B` toggles sidebar
- **Vim:** `<leader>e` toggles file tree

### Find & Replace
- **VS Code:** `Ctrl+H`
- **Vim:** `:s/old/new/g` (current line) or `:%s/old/new/g` (whole file)
- **Vim Alternative:** `<leader>fg` (live grep to find) + `<leader>rn` (rename symbol for code)

### Search File
- **VS Code:** `Ctrl+P`
- **Vim:** `<leader>ff`

### Search in Project
- **VS Code:** `Ctrl+Shift+F`
- **Vim:** `<leader>fg`

### Go to Definition
- **VS Code:** `F12` or `Ctrl+Click`
- **Vim:** `gd`

### Find All References
- **VS Code:** `Shift+Alt+F12` or right-click → References
- **Vim:** `gr`

### Rename Symbol
- **VS Code:** `F2`
- **Vim:** `<leader>rn`

### Code Actions
- **VS Code:** `Ctrl+.`
- **Vim:** `<leader>ca`

### Format Code
- **VS Code:** `Shift+Alt+F`
- **Vim:** `<leader>lf` (formats on save automatically)

### Comment Toggle
- **VS Code:** `Ctrl+/`
- **Vim:** `gc` in visual mode, or `gcc` on current line

### Delete Line
- **VS Code:** `Ctrl+Shift+K`
- **Vim:** `dd`

### Duplicate Line
- **VS Code:** `Ctrl+D` or `Alt+Down`
- **Vim:** `yyp` (copy line, paste below)

### Move Line Up/Down
- **VS Code:** `Alt+Up/Down`
- **Vim:** `ddkP` (delete, move up, paste) or `:m-2` (move line up)

---

## Essential Vim Commands

### Movement
```
h j k l      Left, down, up, right (use this, not arrows)
w            Jump to start of next word
b            Jump to start of previous word
e            Jump to end of word
0            Jump to start of line
$            Jump to end of line
gg           Jump to start of file
G            Jump to end of file
{number}G    Jump to line number (e.g., 42G goes to line 42)
Ctrl+f       Page down
Ctrl+b       Page up
```

### Editing
```
i            Insert mode (before cursor)
a            Insert mode (after cursor)
I            Insert at beginning of line
A            Insert at end of line
o            New line below and insert
O            New line above and insert
x            Delete character
dd           Delete line
d{motion}    Delete (e.g., dw = delete word, d$ = delete to end of line)
c{motion}    Change/replace (e.g., cw = change word)
y            Yank/copy
p            Paste after cursor
P            Paste before cursor
u            Undo
Ctrl+r       Redo
.            Repeat last command
```

### Visual Mode
```
v            Enter visual mode (character selection)
V            Enter visual mode (line selection)
Ctrl+v       Enter visual mode (block selection)
d            Delete selection
y            Copy selection
p            Paste
~            Toggle case
```

### Search & Replace
```
/            Search forward
?            Search backward
n            Next match
N            Previous match
:s/old/new   Replace on current line
:s/old/new/g Replace all on current line
:%s/old/new/g Replace all in file
```

### Registers & Marks
```
"a           Use register 'a' (e.g., "ay to copy to register a)
ma           Set mark 'a' at current position
'a           Jump to mark 'a'
```

### Window Navigation
```
Ctrl+w + w   Cycle through windows
Ctrl+w + h/j/k/l Split navigation
:split       Split horizontally
:vsplit      Vertical split
:q           Close current window
```

---

## Configuration Files

All configuration is in `~/.config/nvim/lua/`:

- **init.lua** - Entry point, loads config
- **config/options.lua** - Vim settings (numbers, tabs, search behavior)
- **config/keymaps.lua** - Custom keybindings
- **config/autocmds.lua** - Auto-commands (spell check in markdown, etc.)
- **plugins/core.lua** - All plugin definitions
- **plugins/gitsigns.lua** - Git integration

Reload config with `<leader>sv` or manually: `:source ~/.config/nvim/init.lua`

---

## LSP (Language Server) Setup

Three language servers installed:
- **lua_ls** - Lua development
- **rust-analyzer** - Rust development through rustaceanvim and the active Rust toolchain
- **marksman** - Markdown intelligence

### LSP Keybindings (When in a File With LSP)
```
gd           Go to definition
gr           Show references
K            Hover documentation
<leader>rn   Rename symbol
<leader>ca   Code action
<leader>lf   Format code
```

### Large Rust Workspace Workflow

For large Rust workspaces, keep one Neovim process alive inside tmux so buffers share one rust-analyzer process:

```bash
mkdir -p ~/.cache/nvim
cd ~/work/your-repo
tmux new -s rust-dev
nvim --listen ~/.cache/nvim/rust-dev.sock .
```

From another SSH terminal, open files into the same Neovim process:

```bash
nvim --server ~/.cache/nvim/rust-dev.sock --remote ~/work/your-repo/services/api/src/main.rs
nvim --server ~/.cache/nvim/rust-dev.sock --remote ~/work/your-repo/services/billing/src/lib.rs
```

Scope rust-analyzer to the projects relevant to the current feature with `RA_LINKED_PROJECTS`. Values are colon-separated and can be either directories containing `Cargo.toml` or direct `Cargo.toml` paths. Relative entries are resolved from the directory where Neovim was started, not from the Rust file's repo root:

```bash
export RA_LINKED_PROJECTS='services/api:services/billing:crates/shared-types'
nvim --listen ~/.cache/nvim/rust-dev.sock .
```

If `RA_LINKED_PROJECTS` is unset, rust-analyzer uses its normal project discovery.

`rustaceanvim` is intentionally configured as `lazy = false`, but it is a filetype plugin. That means it is installed and available at startup, while Rust-specific commands such as `:RustLsp` appear after a Rust buffer initializes.

Optional CPU tuning:

```bash
export RA_NUM_THREADS=6
export RA_CACHE_PRIMING_THREADS=4
```

This config disables rust-analyzer check-on-save for Rust. Use manual checks instead:

```vim
<leader>rc   " run rust-analyzer flyCheck
<leader>rx   " cancel rust-analyzer flyCheck
```

For compile checks, use a separate tmux pane:

```bash
cargo check -p api -p billing -p shared-types --keep-going
cargo check --workspace --all-targets --keep-going
```

To verify rust-analyzer process reuse:

```bash
pgrep -af 'rust-analyzer|lspmux|ra-multiplex'
```

You should normally see one rust-analyzer for the active repo/profile. If you see one per service, root detection is probably wrong. If you see one per independent Neovim process, use the persistent `--listen` workflow above or add lspmux later.

---

## Spell Checking

Markdown files have spell checking enabled automatically.

### Adding Custom Words
**Quick Method (Recommended):**
1. While viewing a misspelled word, press `zg` to add it to spellfile
2. Press `zw` to mark as wrong (undo of `zg`)

**Manual Method:**
```bash
# Edit your custom words file
nvim ~/.config/nvim/spell/en.utf-8.add
# One word per line, then inside Vim:
:mkspell! ~/.config/nvim/spell/en.utf-8.add
```

---

## Troubleshooting

### Completions Not Showing
- Ensure LSP is running: `:LspInfo`
- Try `:Mason` to check if Lua/Markdown language servers are installed
- For Rust, ensure `rust-analyzer` is available in the active Rust toolchain or on `$PATH`

### Formatter Not Working
- Check `:ConformInfo` for formatter status
- Ensure formatters are installed (stylua for Lua, rustfmt for Rust)

### File Tree Not Showing
- Try `:NvimTreeToggle` or press `<leader>e`

### Keybindings Not Working
- Check for conflicts: `:map <leader>ff` (shows what's mapped)
- Reload config: `<leader>sv`
- View all bindings: `<leader>?`

---

## Performance Notes

- Plugins use lazy-loading (only load when needed)
- Treesitter provides fast syntax highlighting
- LSP runs asynchronously (won't block editing)
- Git integration is lightweight
- Rust uses rustaceanvim with check-on-save disabled and optional `RA_LINKED_PROJECTS` scoping for large workspaces

---

## What's NOT Included

Intentionally minimal setup. Some popular Vim additions NOT here:
- Terminal emulator (use external terminal instead)
- Git UI (use `git` commands or external tools like lazygit)
- DAP/debugging (use command line or language-specific tools)
- Multiple file operations (use file tree navigation)

This keeps the config maintainable and prevents cognitive overload for learning.

---

## Tips for Learning

1. **Start with movement:** Master `hjkl`, `w`, `b`, `e`, `0`, `$`, `G`
2. **Learn one command per day:** Don't try to memorize everything
3. **Use which-key:** Press `<leader>?` often to see available commands
4. **Practice motions with operators:** `d` (delete), `c` (change), `y` (copy) + motion
5. **Vim mantra:** Prefer native Vim motions over plugins when learning
6. **External reference:** `:help <topic>` inside Vim is excellent

---

*Last Updated: Run `:set modelines=0` if editing this file and wondering about metadata.*
