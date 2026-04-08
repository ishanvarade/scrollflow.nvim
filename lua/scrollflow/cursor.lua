-- scrollflow/cursor.lua
-- Fully controls j/k behavior when ScrollFlow is active.
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

-- ─── helpers ────────────────────────────────────────────────────────────────

local function win_top(win)    return vim.fn.line('w0', win) end
local function win_bottom(win) return vim.fn.line('w$', win) end

-- Move cursor to (line, col) in a window without scrolling the view.
local function set_cursor_no_scroll(win, line, col)
  local view = vim.api.nvim_win_call(win, function() return vim.fn.winsaveview() end)
  local text = vim.api.nvim_buf_get_lines(
    vim.api.nvim_win_get_buf(win), line - 1, line, false)[1] or ''
  local safe_col = math.max(0, math.min(col, math.max(0, #text - 1)))
  vim.api.nvim_win_set_cursor(win, { line, safe_col })
  -- Restore the view's topline so the page doesn't shift
  vim.api.nvim_win_call(win, function()
    vim.fn.winrestview({ topline = view.topline, leftcol = view.leftcol })
  end)
end

-- Scroll both panes by `delta` lines (positive = content moves up / see later lines).
-- Cursor line stays the same (it effectively "sticks" to its position).
local function scroll_both(state, delta)
  local sync = require('scrollflow.sync')

  local lw_top = win_top(state.left_win)
  local new_lw_top = lw_top + delta

  local line_count = vim.api.nvim_buf_line_count(state.buf)
  local lw_height  = vim.api.nvim_win_get_height(state.left_win)
  local rw_height  = vim.api.nvim_win_get_height(state.right_win)

  -- Clamp: can't scroll past beginning
  if new_lw_top < 1 then new_lw_top = 1 end
  -- Clamp: the right pane's bottom must not go past the last buffer line
  local new_rw_top = new_lw_top + lw_height
  if new_rw_top + rw_height - 1 > line_count then
    -- Can't scroll further down
    return false
  end
  if new_lw_top == lw_top then return false end  -- nothing changed

  -- Tell sync module what we expect so it doesn't fight us
  sync.set_expected(new_lw_top, new_rw_top)

  vim.api.nvim_win_call(state.left_win, function()
    vim.fn.winrestview({ topline = new_lw_top })
  end)
  vim.api.nvim_win_call(state.right_win, function()
    vim.fn.winrestview({ topline = new_rw_top })
  end)
  return true
end

-- ─── j handler ──────────────────────────────────────────────────────────────

local function handle_j()
  local state = require('scrollflow.split').state
  if not state.active then
    -- Not active: pass through to normal j
    local count = vim.v.count
    local seq = (count > 0 and tostring(count) or '') .. 'j'
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes(seq, true, true, true), 'n', false)
    return
  end

  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local cur_line = cursor[1]
  local cur_col  = cursor[2]

  if win == state.left_win then
    local bottom = win_bottom(state.left_win)
    if cur_line < bottom then
      -- Normal case: just move cursor down, no scroll
      set_cursor_no_scroll(state.left_win, cur_line + 1, cur_col)
    else
      -- At bottom of left pane → cross to top of right pane, no scroll
      local right_top = win_top(state.right_win)
      vim.api.nvim_set_current_win(state.right_win)
      set_cursor_no_scroll(state.right_win, right_top, cur_col)
    end

  elseif win == state.right_win then
    local bottom = win_bottom(state.right_win)
    if cur_line < bottom then
      -- Normal case: just move cursor down, no scroll
      set_cursor_no_scroll(state.right_win, cur_line + 1, cur_col)
    else
      -- At bottom of right pane → scroll page up by 1 line, cursor stays
      scroll_both(state, 1)
      -- After scroll, re-place cursor at the new bottom of right pane
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
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes(seq, true, true, true), 'n', false)
    return
  end

  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local cur_line = cursor[1]
  local cur_col  = cursor[2]

  if win == state.right_win then
    local top = win_top(state.right_win)
    if cur_line > top then
      -- Normal case: just move cursor up, no scroll
      set_cursor_no_scroll(state.right_win, cur_line - 1, cur_col)
    else
      -- At top of right pane → cross to bottom of left pane, no scroll
      local left_bottom = win_bottom(state.left_win)
      vim.api.nvim_set_current_win(state.left_win)
      set_cursor_no_scroll(state.left_win, left_bottom, cur_col)
    end

  elseif win == state.left_win then
    local top = win_top(state.left_win)
    if cur_line > top then
      -- Normal case: just move cursor up, no scroll
      set_cursor_no_scroll(state.left_win, cur_line - 1, cur_col)
    else
      -- At top of left pane → scroll page down by 1 line, cursor stays
      scroll_both(state, -1)
      -- After scroll, re-place cursor at the new top of left pane
      local new_top = win_top(state.left_win)
      set_cursor_no_scroll(state.left_win, new_top, cur_col)
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

  _saved = {
    n = { j = save_mapping('n', 'j'), k = save_mapping('n', 'k') },
    x = { j = save_mapping('x', 'j'), k = save_mapping('x', 'k') },
  }

  local opts = { noremap = true, silent = true }
  vim.keymap.set('n', 'j', handle_j, vim.tbl_extend('force', opts, { desc = 'ScrollFlow j' }))
  vim.keymap.set('n', 'k', handle_k, vim.tbl_extend('force', opts, { desc = 'ScrollFlow k' }))
  vim.keymap.set('x', 'j', handle_j, vim.tbl_extend('force', opts, { desc = 'ScrollFlow j (visual)' }))
  vim.keymap.set('x', 'k', handle_k, vim.tbl_extend('force', opts, { desc = 'ScrollFlow k (visual)' }))
end

function M.remove_mappings()
  if not _mapped then return end
  _mapped = false
  for _, mode in ipairs({ 'n', 'x' }) do
    restore_mapping(mode, 'j', _saved[mode] and _saved[mode].j)
    restore_mapping(mode, 'k', _saved[mode] and _saved[mode].k)
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
