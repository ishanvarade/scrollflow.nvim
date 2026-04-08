-- scrollflow/split.lua
-- Manages the virtual split: detecting overflow, creating/removing panes,
-- and tracking shared state that all other modules read.

local M = {}

-- Shared state for all modules
M.state = {
  active       = false,
  left_win     = nil,
  right_win    = nil,
  buf          = nil,
  -- Set to true when the user explicitly disables via :ScrollFlowToggle
  user_disabled = false,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function buf_is_eligible(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end

  local bt = vim.bo[buf].buftype
  if bt ~= '' then return false end   -- only normal buffers

  local ft  = vim.bo[buf].filetype
  local cfg = require('scrollflow.config').options
  for _, excluded in ipairs(cfg.exclude_filetypes) do
    if ft == excluded then return false end
  end

  return true
end

-- Count visible-height windows showing normal buffers on the current tabpage.
local function normal_win_count()
  local count = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].buftype == '' then count = count + 1 end
  end
  return count
end

-- ---------------------------------------------------------------------------
-- Public: should we activate for this win/buf right now?
-- ---------------------------------------------------------------------------

function M.should_activate(win, buf)
  if M.state.active        then return false end
  if M.state.user_disabled then return false end
  if not require('scrollflow.config').options.enabled then return false end
  if not buf_is_eligible(buf) then return false end

  -- Don't activate when the user already has a multi-window layout
  if normal_win_count() > 1 then return false end

  -- Don't activate in diff mode
  if vim.wo[win].diff then return false end

  -- Only activate when the file is taller than the window
  local height     = vim.api.nvim_win_get_height(win)
  local line_count = vim.api.nvim_buf_line_count(buf)
  return line_count > height
end

-- ---------------------------------------------------------------------------
-- Public: create the paired split
-- ---------------------------------------------------------------------------

function M.activate(win, buf)
  if not M.should_activate(win, buf) then return end

  -- Switch to the target window so the split opens relative to it
  vim.api.nvim_set_current_win(win)
  vim.cmd('vsplit')

  -- After vsplit the new (right) window is current
  local right_win = vim.api.nvim_get_current_win()

  -- Equal widths; lock them so user resize of one doesn't throw sync off
  vim.cmd('wincmd =')
  vim.wo[win].winfixwidth       = true
  vim.wo[right_win].winfixwidth = true

  -- Turn off built-in numbers on both (fake numbers module takes over)
  vim.wo[win].number            = false
  vim.wo[win].relativenumber    = false
  vim.wo[right_win].number      = false
  vim.wo[right_win].relativenumber = false

  -- Override scrolloff to 0 on both panes so the cursor can physically reach
  -- the last/first visible line. Without this, scrolloff (e.g. 8) creates a
  -- dead zone: cursor stops N lines from the edge, the view scrolls, and
  -- crossing never fires at the real pane boundary.
  -- We save the current window-local value (-1 means "inherit global") and
  -- restore it on deactivation.
  M.state.saved_scrolloff_left  = vim.wo[win].scrolloff
  M.state.saved_scrolloff_right = vim.wo[right_win].scrolloff
  vim.wo[win].scrolloff       = 0
  vim.wo[right_win].scrolloff = 0

  -- Scroll right window to show the continuation of left window
  local height     = vim.api.nvim_win_get_height(win)
  local topline    = vim.fn.line('w0', win)
  local right_top  = math.max(1, math.min(topline + height,
                               vim.api.nvim_buf_line_count(buf)))

  vim.api.nvim_win_call(right_win, function()
    vim.fn.winrestview({ topline = right_top, lnum = right_top })
  end)

  -- Return focus to the left window
  vim.api.nvim_set_current_win(win)

  M.state.active    = true
  M.state.left_win  = win
  M.state.right_win = right_win
  M.state.buf       = buf

  vim.api.nvim_exec_autocmds('User', { pattern = 'ScrollFlowActivated' })
end

-- ---------------------------------------------------------------------------
-- Public: close the paired split and reset state
-- ---------------------------------------------------------------------------

function M.deactivate()
  if not M.state.active then return end

  -- Restore window options before we possibly close the window
  if M.state.left_win and vim.api.nvim_win_is_valid(M.state.left_win) then
    vim.wo[M.state.left_win].winfixwidth    = false
    vim.wo[M.state.left_win].statuscolumn   = ''
    -- Restore scrolloff: -1 means "inherit from global option"
    vim.wo[M.state.left_win].scrolloff =
      M.state.saved_scrolloff_left ~= nil and M.state.saved_scrolloff_left or -1
  end

  if M.state.right_win and vim.api.nvim_win_is_valid(M.state.right_win) then
    -- Closing right_win – no need to restore its options
    vim.api.nvim_win_close(M.state.right_win, false)
  end

  M.state.active    = false
  M.state.left_win  = nil
  M.state.right_win = nil
  M.state.buf       = nil

  vim.api.nvim_exec_autocmds('User', { pattern = 'ScrollFlowDeactivated' })
end

-- ---------------------------------------------------------------------------
-- Public: user-facing toggle
-- ---------------------------------------------------------------------------

function M.toggle()
  if M.state.active then
    M.state.user_disabled = true
    M.deactivate()
  else
    M.state.user_disabled = false
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    M.activate(win, buf)
  end
end

return M
