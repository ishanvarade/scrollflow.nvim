-- scrollflow/numbers.lua
-- Fake continuous relative numbers across both panes.
--
-- Strategy: use Neovim's 'statuscolumn' option (requires Neovim ≥ 0.9).
-- Both windows get the same expression; the expression reads a single
-- global cursor line (updated by CursorMoved) so numbers are relative
-- to the cursor regardless of which pane it lives in.
--
-- Falls back to hiding numbers entirely on Neovim < 0.9.

local M = {}

-- Cached cursor line updated by CursorMoved autocmd
M._cursor_line = 1

local has_statuscolumn = vim.fn.has('nvim-0.9') == 1

-- ---------------------------------------------------------------------------
-- Statuscolumn expression – called by Neovim once per visible line per window
-- ---------------------------------------------------------------------------

-- Exposed on _G so the %{v:lua...} expression can reach it cheaply.
_G._ScrollFlowStatuscolumn = function(lnum)
  local state = require('scrollflow.split').state
  if not state.active then
    -- Inactive: show plain absolute number right-aligned
    local w = require('scrollflow.config').options.number_width
    return string.format('%' .. w .. 'd ', lnum)
  end

  local cursor = M._cursor_line
  local w      = require('scrollflow.config').options.number_width
  local rel    = lnum - cursor

  if rel == 0 then
    -- Current line: bold absolute number (just the number, highlight handles bold)
    return string.format('%' .. w .. 'd ', lnum)
  else
    return string.format('%' .. w .. 'd ', math.abs(rel))
  end
end

-- ---------------------------------------------------------------------------
-- Apply / remove statuscolumn on a window
-- ---------------------------------------------------------------------------

local SC_EXPR = "%{v:lua._ScrollFlowStatuscolumn(v:lnum)}"

local function apply_statuscolumn(win)
  if not has_statuscolumn then return end
  if not vim.api.nvim_win_is_valid(win) then return end
  vim.wo[win].statuscolumn = SC_EXPR
end

local function clear_statuscolumn(win)
  if not has_statuscolumn then return end
  if not vim.api.nvim_win_is_valid(win) then return end
  vim.wo[win].statuscolumn = ''
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

-- Called from CursorMoved / CursorMovedI to keep the cursor line up to date.
function M.update_cursor(win)
  local state = require('scrollflow.split').state
  if not state.active then return end
  if win ~= state.left_win and win ~= state.right_win then return end
  local ok, cur = pcall(vim.api.nvim_win_get_cursor, win)
  if ok then M._cursor_line = cur[1] end
end

-- Called from WinScrolled / CursorMoved to force a redraw of the number column.
function M.refresh()
  local state = require('scrollflow.split').state
  if not state.active then return end
  if has_statuscolumn then
    -- Neovim will redraw automatically; calling redraw here causes flicker.
    -- Just update the cursor line tracker (already done via CursorMoved).
    return
  end
  -- Fallback: nothing to do
end

function M.setup()
  local group = vim.api.nvim_create_augroup('ScrollFlowNumbers', { clear = true })

  vim.api.nvim_create_autocmd('User', {
    pattern  = 'ScrollFlowActivated',
    group    = group,
    callback = function()
      local state = require('scrollflow.split').state
      if not state.active then return end
      -- Seed cursor line
      local ok, cur = pcall(vim.api.nvim_win_get_cursor, state.left_win)
      if ok then M._cursor_line = cur[1] end
      apply_statuscolumn(state.left_win)
      apply_statuscolumn(state.right_win)
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    pattern  = 'ScrollFlowDeactivated',
    group    = group,
    callback = function()
      -- split.lua already cleared statuscolumn on left_win before closing right_win
    end,
  })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group    = group,
    callback = function()
      M.update_cursor(vim.api.nvim_get_current_win())
    end,
  })
end

return M
