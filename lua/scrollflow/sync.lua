-- scrollflow/sync.lua
-- Keeps both panes locked together: right_topline = left_topline + left_height.
-- Uses a "last-known" tracking table to break the sync feedback loop.

local M = {}

-- Track the toplines we last programmatically set so we can skip no-op events.
local _expected = { left = nil, right = nil }

-- ---------------------------------------------------------------------------
-- Core sync helpers
-- ---------------------------------------------------------------------------

-- Called when the left pane scrolled; push the change to the right pane.
local function sync_right_from_left(state)
  local left_top    = vim.fn.line('w0', state.left_win)
  local left_height = vim.api.nvim_win_get_height(state.left_win)
  local right_top   = left_top + left_height
  local line_count  = vim.api.nvim_buf_line_count(state.buf)
  right_top = math.max(1, math.min(right_top, line_count))

  if _expected.right == right_top then return end   -- already correct, skip
  _expected.left  = left_top
  _expected.right = right_top

  vim.api.nvim_win_call(state.right_win, function()
    vim.fn.winrestview({ topline = right_top })
  end)
end

-- Called when the right pane scrolled (e.g. user Ctrl+E in right window);
-- push the inverse change back to the left pane.
local function sync_left_from_right(state)
  local right_top   = vim.fn.line('w0', state.right_win)
  if _expected.right == right_top then return end   -- this was our own write

  local left_height = vim.api.nvim_win_get_height(state.left_win)
  local left_top    = math.max(1, right_top - left_height)
  local right_should = left_top + left_height
  local line_count  = vim.api.nvim_buf_line_count(state.buf)
  right_should = math.max(1, math.min(right_should, line_count))

  _expected.left  = left_top
  _expected.right = right_should

  vim.api.nvim_win_call(state.left_win, function()
    vim.fn.winrestview({ topline = left_top })
  end)
  -- Re-align right in case line_count clamp moved it
  if right_should ~= right_top then
    vim.api.nvim_win_call(state.right_win, function()
      vim.fn.winrestview({ topline = right_should })
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

-- Called after any scroll event; decides which direction to sync.
function M.on_win_scrolled(win_id)
  local state = require('scrollflow.split').state
  if not state.active then return end
  if not vim.api.nvim_win_is_valid(state.left_win)  then return end
  if not vim.api.nvim_win_is_valid(state.right_win) then return end

  if win_id == state.left_win then
    sync_right_from_left(state)
  elseif win_id == state.right_win then
    sync_left_from_right(state)
  end
end

-- Reset expected toplines (called on activate so stale values don't block sync).
function M.reset()
  _expected.left  = nil
  _expected.right = nil
end

-- Called by cursor.lua before it scrolls both panes so the WinScrolled handler
-- knows the resulting toplines are intentional and won't try to re-sync.
function M.set_expected(left_top, right_top)
  _expected.left  = left_top
  _expected.right = right_top
end

function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup('ScrollFlowSync', { clear = true })

  vim.api.nvim_create_autocmd('WinScrolled', {
    group    = group,
    callback = function(ev)
      local win_id = tonumber(ev.match)
      M.on_win_scrolled(win_id)
      -- Let numbers and highlights refresh after any scroll
      require('scrollflow.numbers').refresh()
      require('scrollflow.highlights').on_scroll()
    end,
  })

  -- When ScrollFlow activates, reset expected values
  vim.api.nvim_create_autocmd('User', {
    pattern  = 'ScrollFlowActivated',
    group    = group,
    callback = M.reset,
  })
end

return M
