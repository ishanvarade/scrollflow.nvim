-- scrollflow/highlights.lua
-- Mirrors highlights across panes for the "one document" illusion.
--
-- Search highlights (hlsearch):
--   Since both windows display the same buffer, Neovim already draws search
--   highlights in both. No extra work needed.
--
-- Visual selection:
--   Visual mode highlights are only drawn in the active window. When the user
--   selects text that spans (or is visible in) both panes, the inactive pane
--   shows no visual highlight. We fix this by adding extmark highlights in
--   the buffer namespace that mirrors the selection into the non-active window.

local M = {}

local NS = vim.api.nvim_create_namespace('scrollflow_visual_mirror')

-- ---------------------------------------------------------------------------
-- Visual mirror
-- ---------------------------------------------------------------------------

local function clear_mirror(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  end
end

local function update_visual_mirror()
  local state = require('scrollflow.split').state
  if not state.active then return end

  local mode = vim.fn.mode()
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then
    clear_mirror(state.buf)
    return
  end

  local cur_win = vim.api.nvim_get_current_win()
  if cur_win ~= state.left_win and cur_win ~= state.right_win then
    clear_mirror(state.buf)
    return
  end

  -- getpos('v') is the anchor; getpos('.') is the cursor end
  local anchor = vim.fn.getpos('v')
  local cursor = vim.fn.getpos('.')
  local s_line = math.min(anchor[2], cursor[2]) - 1   -- 0-indexed
  local e_line = math.max(anchor[2], cursor[2]) - 1

  -- The other (non-active) window
  local other_win = (cur_win == state.left_win) and state.right_win or state.left_win
  if not vim.api.nvim_win_is_valid(other_win) then
    clear_mirror(state.buf)
    return
  end

  local other_top = vim.fn.line('w0', other_win) - 1
  local other_bot = vim.fn.line('w$', other_win) - 1

  -- Only highlight lines visible in the other window AND within the selection
  local hi_start = math.max(s_line, other_top)
  local hi_end   = math.min(e_line, other_bot)

  clear_mirror(state.buf)
  if hi_start > hi_end then return end

  if mode == 'V' then
    -- Line-wise: highlight whole lines
    for l = hi_start, hi_end do
      vim.api.nvim_buf_add_highlight(state.buf, NS, 'Visual', l, 0, -1)
    end
  elseif mode == 'v' then
    -- Character-wise: highlight entire lines except possibly first/last
    for l = hi_start, hi_end do
      local col_s = (l == s_line) and (math.min(anchor[3], cursor[3]) - 1) or 0
      local col_e = (l == e_line) and  math.max(anchor[3], cursor[3])      or -1
      vim.api.nvim_buf_add_highlight(state.buf, NS, 'Visual', l, col_s, col_e)
    end
  else
    -- Block-wise: highlight columns
    local c_s = math.min(anchor[3], cursor[3]) - 1
    local c_e = math.max(anchor[3], cursor[3])
    for l = hi_start, hi_end do
      vim.api.nvim_buf_add_highlight(state.buf, NS, 'Visual', l, c_s, c_e)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Public callbacks
-- ---------------------------------------------------------------------------

-- Called from sync.lua after a scroll event.
function M.on_scroll()
  -- Search highlights auto-refresh. Visual mirror may need a repaint.
  update_visual_mirror()
end

function M.setup()
  local group = vim.api.nvim_create_augroup('ScrollFlowHighlights', { clear = true })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group    = group,
    callback = update_visual_mirror,
  })

  vim.api.nvim_create_autocmd('ModeChanged', {
    group    = group,
    callback = function()
      local new = vim.v.event.new_mode
      if new ~= 'v' and new ~= 'V' and new ~= '\22' then
        local state = require('scrollflow.split').state
        if state.active then clear_mirror(state.buf) end
      end
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    pattern  = 'ScrollFlowDeactivated',
    group    = group,
    callback = function()
      -- buf may already be nil; clear is a no-op if buf is invalid
      local state = require('scrollflow.split').state
      if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        clear_mirror(state.buf)
      end
    end,
  })
end

return M
