# ScrollFlow

A Neovim plugin that makes long files feel like a single infinite page displayed
in newspaper columns — two vertical panes, one buffer, one cursor.

```
┌──────────────────────┬──────────────────────┐
│   1 local M = {}     │  51 end              │
│   2                  │  52                  │
│   3 function M.setup │  53 function M.other │
│  ...                 │  ...                 │
│  50 end              │ 100 end              │
└──────────────────────┴──────────────────────┘
          one buffer · one cursor · one document
```

## Features

| Feature | Description |
|---|---|
| **Auto-split on overflow** | When a file is taller than the window, a right pane appears automatically showing the continuation |
| **Seamless `j` / `k`** | Full cursor and scroll control — see [Cursor behavior](#cursor-behavior) |
| **Continuous relative numbers** | Fake relative numbers via `statuscolumn` — calculated globally from the single cursor position across both panes (Neovim ≥ 0.9) |
| **Scroll sync** | Both panes always stay locked: `right_topline = left_topline + height` |
| **Search highlights** | `hlsearch` matches appear in both panes automatically (same buffer) |
| **Visual selection mirror** | Selections spanning the pane boundary are mirrored into the other pane |
| **Smart deactivation** | Auto-disables in diff mode, with multi-window layouts, or via `:ScrollFlowToggle` |

## Requirements

- Neovim ≥ 0.8 (≥ 0.9 for continuous relative numbers via `statuscolumn`)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim) (recommended)

```lua
{
  'ishanvarade/scrollflow.nvim',
  lazy = false,
  config = function()
    require('scrollflow').setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'ishanvarade/scrollflow.nvim',
  config = function()
    require('scrollflow').setup()
  end,
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'ishanvarade/scrollflow.nvim'
```

Then add to your `init.lua`:

```lua
require('scrollflow').setup()
```

### Manual

Clone anywhere on your `runtimepath`:

```bash
git clone https://github.com/ishanvarade/scrollflow.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/scrollflow.nvim
```

Then add `require('scrollflow').setup()` to your `init.lua`.

## Configuration

All options with their defaults:

```lua
require('scrollflow').setup({
  -- Master switch
  enabled = true,

  -- Continuous relative numbers across both panes (requires Neovim >= 0.9)
  fake_numbers = true,

  -- Width of the number column
  number_width = 4,

  -- Filetypes where ScrollFlow will not activate
  exclude_filetypes = {
    'help', 'qf', 'NvimTree', 'neo-tree', 'TelescopePrompt',
    'lazy', 'mason', 'noice', 'notify',
  },

  -- Buffer types where ScrollFlow will not activate
  exclude_buftypes = { 'terminal', 'prompt', 'nofile', 'quickfix', 'help' },
})
```

## Commands

| Command | Description |
|---|---|
| `:ScrollFlowToggle` | Enable / disable ScrollFlow for the current session |

## Cursor behavior

ScrollFlow fully owns `j` and `k` so the page never scrolls unexpectedly:

| Situation | `j` | `k` |
|---|---|---|
| Cursor anywhere mid-pane | Move cursor down, **page stays still** | Move cursor up, **page stays still** |
| Cursor at **bottom of left pane** | Cursor jumps to **top of right pane**, page stays still | — |
| Cursor at **top of right pane** | — | Cursor jumps to **bottom of left pane**, page stays still |
| Cursor at **bottom of right pane** | **Page scrolls up** (new lines appear below), cursor stays at bottom | — |
| Cursor at **top of left pane** | — | **Page scrolls down** (earlier lines appear above), cursor stays at top |

## How it works

1. **Overflow detection** — on `BufWinEnter` / `VimResized` / `WinResized`, if
   `line_count > win_height` the plugin creates a `vsplit` of the same buffer.

2. **Scroll lock** — a `WinScrolled` autocmd keeps
   `right_topline = left_topline + left_height` at all times.

3. **Cursor control** — `j` / `k` are remapped (original bindings saved and
   restored on deactivation). The handlers use `nvim_win_set_cursor` +
   `winrestview` so cursor movement never triggers an unwanted page scroll.

4. **Fake relative numbers** — `statuscolumn` is set to a Lua expression on
   both windows. It reads a single `cursor_line` variable updated by
   `CursorMoved`, giving continuous relative numbers across both panes.

5. **Visual mirror** — in visual mode, `nvim_buf_add_highlight` repaints the
   selection into the non-active pane so the selection looks continuous.

## Differences from scroll-it.nvim

`scroll-it.nvim` syncs two *independent* windows. ScrollFlow makes them feel
like *one document*: the cursor crosses pane boundaries, numbers are globally
relative, and the page only scrolls at the exact moments you'd expect.

## Structure

```
scrollflow.nvim/
├── lua/scrollflow/
│   ├── init.lua        ← entry point, lifecycle autocmds
│   ├── config.lua      ← defaults and user options
│   ├── split.lua       ← split creation / teardown / shared state
│   ├── sync.lua        ← scroll synchronisation
│   ├── numbers.lua     ← continuous relative numbers via statuscolumn
│   ├── cursor.lua      ← j/k cursor and scroll control
│   └── highlights.lua  ← visual selection mirror
└── plugin/
    └── scrollflow.lua  ← bootstrap / auto-setup on VimEnter
```

## License

MIT
