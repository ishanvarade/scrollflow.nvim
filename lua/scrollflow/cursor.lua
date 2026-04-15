-- scrollflow/cursor.lua
-- Fully controls j/k and all scroll motion when ScrollFlow is active.
--
-- The two panes form one continuous "page". j/k ONLY move the cursor.
-- The page NEVER scrolls EXCEPT at two edges:
--   • j at bottom of RIGHT pane → page scrolls up (both panes shift up 1 line),
--     cursor stays at bottom of right pane.
--   • k at top of LEFT pane → page scrolls down (both panes shift down 1 line),
--     cursor stays at top of left pane.
--
-- Crossing:
--   • j at bottom of LEFT pane → cursor disappears from left, appears at
--     top of RIGHT pane. No scroll.
--   • k at top of RIGHT pane → cursor disappears from right, appears at
--     bottom of LEFT pane. No scroll.
--
-- We NEVER call feedkeys('j') or feedkeys('k') because Neovim's built-in
-- j/k will scroll the view when the cursor hits the window edge, which
-- fights with our sync system and breaks the illusion.

local M = {}

local _mapped = false
local _saved  = {}

-- Keys we intercept per mode. Must be saved/restored on deactivate.
-- n: all scroll keys; x: same (visual mode); i: mouse only
local _mode_keys = {
  n = { 'j', 'k', '<C-d>', '<C-u>', '<C-f>', '<C-b>', '<C-e>', '<C-y>',
        '<ScrollWheelDown>', '<ScrollWheelUp>' },
  x = { 'j', 'k', '<C-d>', '<C-u>', '<C-f>', '<C-b>', '<C-e>', '<C-y>',
        '<ScrollWheelDown>', '<ScrollWheelUp>' },
  i = { '<ScrollWheelDown>', '<ScrollWheelUp>' },
}

-- ─── helpers ────────────────────────────────────────────────────────────────

local function win_top(win)    return vim.fn.line('w0', win) end
local function win_bottom(win) return vim.fn.line('w$', win) end

local function feedkeys(key)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, true, true), 'n', false)
end

-- Move cursor to (line, col) in a window without scrolling the view.
-- BUG-P fix: perform cursor set and view restore inside one nvim_win_call so
-- that any scrolloff-triggered intermediate scroll is overwritten by
-- winrestview before Neovim flushes WinScrolled events.
local function set_cursor_no_scroll(win, line, col)
  local text = vim.api.nvim_buf_get_lines(
    vim.api.nvim_win_get_buf(win), line - 1, line, false)[1] or ''
  local safe_col = math.max(0, math.min(col, math.max(0, #text - 1)))
  vim.api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    vim.api.nvim_win_set_cursor(0, { line, safe_col })
    vim.fn.winrestview({ topline = view.topline, leftcol = view.leftcol })
  end)
end

-- Scroll both panes by `delta` lines (positive = content moves up / see later lines).
-- Returns true if scroll happened, false at document boundaries.
local function scroll_both(state, delta)
  local sync = require('scrollflow.sync')

  local lw_top     = win_top(state.left_win)
  local new_lw_top = lw_top + delta

  local line_count = vim.api.nvim_buf_line_count(state.buf)
  local lw_height  = vim.api.nvim_win_get_height(state.left_win)
  local rw_height  = vim.api.nvim_win_get_height(state.right_win)

  -- Clamp: can't scroll past beginning
  if new_lw_top < 1 then new_lw_top = 1 end
  -- Clamp: the right pane's bottom must not go past the last buffer line
  local new_rw_top = new_lw_top + lw_height
  if new_rw_top + rw_height - 1 > line_count then return false end
  if new_lw_top == lw_top then return false end

  sync.set_expected(new_lw_top, new_rw_top)

  -- For each pane: set topline and clamp the cursor into the new visible
  -- range so Neovim does not reset the topline to keep an out-of-view cursor
  -- visible. The NON-active pane gets its cursor pinned to its new topline —
  -- the active pane cursor is repositioned by the caller via place_cursor_in_pane().
  local active_win = vim.api.nvim_get_current_win()

  vim.api.nvim_win_call(state.left_win, function()
    if state.left_win == active_win then
      -- Active pane: clamp cursor to new visible range, but keep it in place if possible
      local cur = vim.api.nvim_win_get_cursor(0)[1]
      local lnum = math.max(new_lw_top, math.min(cur, new_lw_top + lw_height - 1))
      vim.fn.winrestview({ topline = new_lw_top, lnum = lnum })
    else
      -- Inactive pane: pin cursor to topline to avoid Neovim adjusting topline
      vim.fn.winrestview({ topline = new_lw_top, lnum = new_lw_top })
    end
  end)
  vim.api.nvim_win_call(state.right_win, function()
    if state.right_win == active_win then
      local cur = vim.api.nvim_win_get_cursor(0)[1]
      local lnum = math.max(new_rw_top, math.min(cur, new_rw_top + rw_height - 1))
      vim.fn.winrestview({ topline = new_rw_top, lnum = lnum })
    else
      vim.fn.winrestview({ topline = new_rw_top, lnum = new_rw_top })
    end
  end)
  return true
end

-- Place cursor at abs_line in whichever pane it falls in (left wins ties).
local function place_cursor_in_pane(state, abs_line, col)
  local lw_top    = win_top(state.left_win)
  local lw_bottom = win_bottom(state.left_win)
  local rw_top    = win_top(state.right_win)
  local rw_bottom = win_bottom(state.right_win)
  if abs_line <= lw_bottom then
    local line = math.max(lw_top, math.min(abs_line, lw_bottom))
    vim.api.nvim_set_current_win(state.left_win)
    set_cursor_no_scroll(state.left_win, line, col)
  else
    local line = math.max(rw_top, math.min(abs_line, rw_bottom))
    vim.api.nvim_set_current_win(state.right_win)
    set_cursor_no_scroll(state.right_win, line, col)
  end
end

-- ─── j handler ──────────────────────────────────────────────────────────────

local function handle_j()
  local state = require('scrollflow.split').state
  if not state.active then
    local count = vim.v.count
    local seq = (count > 0 and tostring(count) or '') .. 'j'
    feedkeys(seq)
    return
  end

  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local cur_line = cursor[1]
  local cur_col  = cursor[2]

  -- BUG-F fix: don't cross pane boundaries in visual mode.
  -- nvim_set_current_win in visual mode can corrupt the selection anchor.
  local mode = vim.fn.mode()
  local in_visual = (mode == 'v' or mode == 'V' or mode == '\22')

  if win == state.left_win then
    local bottom = win_bottom(state.left_win)
    if cur_line < bottom then
      set_cursor_no_scroll(state.left_win, cur_line + 1, cur_col)
    elseif not in_visual then
      -- Cross to top of right pane (normal mode only)
      local right_top = win_top(state.right_win)
      vim.api.nvim_set_current_win(state.right_win)
      set_cursor_no_scroll(state.right_win, right_top, cur_col)
    end
    -- In visual mode at left pane bottom: stay put (no crossing)

  elseif win == state.right_win then
    local bottom = win_bottom(state.right_win)
    if cur_line < bottom then
      set_cursor_no_scroll(state.right_win, cur_line + 1, cur_col)
    else
      -- Scroll page up, cursor stays at bottom of right pane
      scroll_both(state, 1)
      local new_bottom = win_bottom(state.right_win)
      set_cursor_no_scroll(state.right_win, new_bottom, cur_col)
    end
  end
end

-- ─── k handler ──────────────────────────────────────────────────────────────

local function handle_k()
  local state = require('scrollflow.split').state
  if not state.active then
    local count = vim.v.count
    local seq = (count > 0 and tostring(count) or '') .. 'k'
    feedkeys(seq)
    return
  end

  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local cur_line = cursor[1]
  local cur_col  = cursor[2]

  -- BUG-F fix: don't cross pane boundaries in visual mode
  local mode = vim.fn.mode()
  local in_visual = (mode == 'v' or mode == 'V' or mode == '\22')

  if win == state.right_win then
    local top = win_top(state.right_win)
    if cur_line > top then
      set_cursor_no_scroll(state.right_win, cur_line - 1, cur_col)
    elseif not in_visual then
      -- Cross to bottom of left pane (normal mode only)
      local left_bottom = win_bottom(state.left_win)
      vim.api.nvim_set_current_win(state.left_win)
      set_cursor_no_scroll(state.left_win, left_bottom, cur_col)
    end
    -- In visual mode at right pane top: stay put (no crossing)

  elseif win == state.left_win then
    local top = win_top(state.left_win)
    if cur_line > top then
      set_cursor_no_scroll(state.left_win, cur_line - 1, cur_col)
    else
      -- Scroll page down, cursor stays at top of left pane
      scroll_both(state, -1)
      local new_top = win_top(state.left_win)
      set_cursor_no_scroll(state.left_win, new_top, cur_col)
    end
  end
end

-- ─── page-scroll handlers ───────────────────────────────────────────────────

-- Returns (state, win, cur_line, cur_col) if active in a managed pane, else nil.
local function scroll_precheck(key)
  local state = require('scrollflow.split').state
  if not state.active then feedkeys(key) return nil end
  local win = vim.api.nvim_get_current_win()
  if win ~= state.left_win and win ~= state.right_win then
    feedkeys(key) return nil
  end
  local cur = vim.api.nvim_win_get_cursor(win)
  return state, win, cur[1], cur[2]
end

-- Re-anchor expected toplines after cursor placement (BUG-P safety net).
-- place_cursor_in_pane may trigger intermediate WinScrolled events (e.g. due
-- to 'scrolloff') that shift the views before the sync handler can see the
-- final state.  Calling this afterwards resets _expected to the actual current
-- toplines so subsequent deferred WinScrolled events are treated as no-ops.
local function reanchor(state)
  require('scrollflow.sync').set_expected(
    win_top(state.left_win), win_top(state.right_win))
end

-- <C-d>: scroll down half page, cursor follows
local function handle_ctrl_d()
  local state, win, cur_line, cur_col = scroll_precheck('<C-d>')
  if not state then return end
  local delta = math.floor(vim.api.nvim_win_get_height(state.left_win) / 2)
  if scroll_both(state, delta) then
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    place_cursor_in_pane(state, math.min(cur_line + delta, line_count), cur_col)
  else
    place_cursor_in_pane(state, win_bottom(state.right_win), cur_col)
  end
  reanchor(state)
end

-- <C-u>: scroll up half page, cursor follows
local function handle_ctrl_u()
  local state, win, cur_line, cur_col = scroll_precheck('<C-u>')
  if not state then return end
  local delta = math.floor(vim.api.nvim_win_get_height(state.left_win) / 2)
  if scroll_both(state, -delta) then
    place_cursor_in_pane(state, math.max(cur_line - delta, 1), cur_col)
  else
    place_cursor_in_pane(state, win_top(state.left_win), cur_col)
  end
  reanchor(state)
end

-- <C-f>: scroll down full page, cursor to top of new view
local function handle_ctrl_f()
  local state, win, cur_line, cur_col = scroll_precheck('<C-f>')
  if not state then return end
  local height = vim.api.nvim_win_get_height(state.left_win)
  if scroll_both(state, height) then
    place_cursor_in_pane(state, win_top(state.left_win), cur_col)
  else
    place_cursor_in_pane(state, win_bottom(state.right_win), cur_col)
  end
  reanchor(state)
end

-- <C-b>: scroll up full page, cursor to bottom of new view
local function handle_ctrl_b()
  local state, win, cur_line, cur_col = scroll_precheck('<C-b>')
  if not state then return end
  local height = vim.api.nvim_win_get_height(state.left_win)
  if scroll_both(state, -height) then
    place_cursor_in_pane(state, win_bottom(state.right_win), cur_col)
  else
    place_cursor_in_pane(state, win_top(state.left_win), cur_col)
  end
  reanchor(state)
end

-- <C-e>: scroll down 1 line, cursor stays (clamps to new top if scrolled off)
local function handle_ctrl_e()
  local state, win, cur_line, cur_col = scroll_precheck('<C-e>')
  if not state then return end
  scroll_both(state, 1)
  -- If cursor scrolled above the new top of its pane, clamp it down
  local lw_top = win_top(state.left_win)
  if win == state.left_win and cur_line < lw_top then
    set_cursor_no_scroll(state.left_win, lw_top, cur_col)
  elseif win == state.right_win then
    local rw_top = win_top(state.right_win)
    if cur_line < rw_top then
      set_cursor_no_scroll(state.right_win, rw_top, cur_col)
    end
  end
end

-- <C-y>: scroll up 1 line, cursor stays (clamps to new bottom if scrolled off)
local function handle_ctrl_y()
  local state, win, cur_line, cur_col = scroll_precheck('<C-y>')
  if not state then return end
  scroll_both(state, -1)
  -- If cursor scrolled below the new bottom of its pane, clamp it up
  local rw_bottom = win_bottom(state.right_win)
  if win == state.right_win and cur_line > rw_bottom then
    set_cursor_no_scroll(state.right_win, rw_bottom, cur_col)
  elseif win == state.left_win then
    local lw_bottom = win_bottom(state.left_win)
    if cur_line > lw_bottom then
      set_cursor_no_scroll(state.left_win, lw_bottom, cur_col)
    end
  end
end

-- Mouse wheel: scroll 3 lines, cursor clamps to visible area
local function handle_scroll_down()
  local state, win, cur_line, cur_col = scroll_precheck('<ScrollWheelDown>')
  if not state then return end
  scroll_both(state, 3)
  local lw_top = win_top(state.left_win)
  if win == state.left_win and cur_line < lw_top then
    set_cursor_no_scroll(state.left_win, lw_top, cur_col)
  elseif win == state.right_win then
    local rw_top = win_top(state.right_win)
    if cur_line < rw_top then
      set_cursor_no_scroll(state.right_win, rw_top, cur_col)
    end
  end
end

local function handle_scroll_up()
  local state, win, cur_line, cur_col = scroll_precheck('<ScrollWheelUp>')
  if not state then return end
  scroll_both(state, -3)
  local rw_bottom = win_bottom(state.right_win)
  if win == state.right_win and cur_line > rw_bottom then
    set_cursor_no_scroll(state.right_win, rw_bottom, cur_col)
  elseif win == state.left_win then
    local lw_bottom = win_bottom(state.left_win)
    if cur_line > lw_bottom then
      set_cursor_no_scroll(state.left_win, lw_bottom, cur_col)
    end
  end
end

-- ─── mapping management ─────────────────────────────────────────────────────

local function save_mapping(mode, key)
  local m = vim.fn.maparg(key, mode, false, true)
  return (m and m.lhs ~= nil) and m or nil
end

local function restore_mapping(mode, key, saved)
  if saved then
    vim.fn.mapset(mode, false, saved)
  else
    pcall(vim.keymap.del, mode, key)
  end
end

function M.set_mappings()
  if _mapped then return end
  _mapped = true

  -- Save all existing mappings for every (mode, key) pair we will override
  _saved = {}
  for mode, keys in pairs(_mode_keys) do
    _saved[mode] = {}
    for _, key in ipairs(keys) do
      _saved[mode][key] = save_mapping(mode, key)
    end
  end

  local opts = { noremap = true, silent = true }

  local key_fn = {
    j                  = handle_j,
    k                  = handle_k,
    ['<C-d>']          = handle_ctrl_d,
    ['<C-u>']          = handle_ctrl_u,
    ['<C-f>']          = handle_ctrl_f,
    ['<C-b>']          = handle_ctrl_b,
    ['<C-e>']          = handle_ctrl_e,
    ['<C-y>']          = handle_ctrl_y,
    ['<ScrollWheelDown>'] = handle_scroll_down,
    ['<ScrollWheelUp>']   = handle_scroll_up,
  }

  -- BUG-G fix: map scroll keys in visual mode as well
  -- BUG-H fix: map mouse scroll in insert mode
  for mode, keys in pairs(_mode_keys) do
    for _, key in ipairs(keys) do
      local fn = key_fn[key]
      if fn then
        vim.keymap.set(mode, key, fn,
          vim.tbl_extend('force', opts, { desc = 'ScrollFlow ' .. key }))
      end
    end
  end
end

function M.remove_mappings()
  if not _mapped then return end
  _mapped = false

  for mode, keys in pairs(_mode_keys) do
    for _, key in ipairs(keys) do
      restore_mapping(mode, key, _saved[mode] and _saved[mode][key])
    end
  end
  _saved = {}
end

function M.setup()
  local group = vim.api.nvim_create_augroup('ScrollFlowCursor', { clear = true })
  vim.api.nvim_create_autocmd('User', {
    pattern  = 'ScrollFlowActivated',
    group    = group,
    callback = M.set_mappings,
  })
  vim.api.nvim_create_autocmd('User', {
    pattern  = 'ScrollFlowDeactivated',
    group    = group,
    callback = M.remove_mappings,
  })
end

return M
