-- scrollflow/init.lua
-- Entry point. Call require('scrollflow').setup({}) from your config.

local M = {}

local _setup_done = false

function M.setup(opts)
  _setup_done = true
  vim.g.scrollflow_setup_called = true

  local config     = require('scrollflow.config')
  local split      = require('scrollflow.split')
  local sync       = require('scrollflow.sync')
  local numbers    = require('scrollflow.numbers')
  local cursor_mod = require('scrollflow.cursor')
  local highlights = require('scrollflow.highlights')

  config.setup(opts)

  -- ------------------------------------------------------------------
  -- Per-module setup (registers their own autocmd groups)
  -- ------------------------------------------------------------------
  sync.setup_autocmds()
  numbers.setup()
  cursor_mod.setup()
  highlights.setup()

  -- ------------------------------------------------------------------
  -- Core lifecycle autocmds
  -- ------------------------------------------------------------------
  local group = vim.api.nvim_create_augroup('ScrollFlow', { clear = true })

  -- Attempt activation whenever a buffer is displayed in a window
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'VimResized', 'WinResized' }, {
    group    = group,
    callback = function()
      if not config.options.enabled then return end
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)
      -- Defer so the window has settled to its final dimensions
      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf) then
          split.activate(win, buf)
        end
      end, 20)
    end,
  })

  -- React to a window being closed
  vim.api.nvim_create_autocmd('WinClosed', {
    group    = group,
    callback = function(ev)
      local state = split.state
      if not state.active then return end
      local closed = tonumber(ev.match)

      if closed == state.right_win then
        -- Right pane was closed externally – tear down cleanly without
        -- trying to close it again.
        local lw = state.left_win
        state.active    = false
        state.left_win  = nil
        state.right_win = nil
        state.buf       = nil
        if lw and vim.api.nvim_win_is_valid(lw) then
          vim.wo[lw].winfixwidth  = false
          vim.wo[lw].statuscolumn = ''
        end
        vim.api.nvim_exec_autocmds('User', { pattern = 'ScrollFlowDeactivated' })

      elseif closed == state.left_win then
        -- Left pane closed – try to close the right pane too
        split.deactivate()
      end
    end,
  })

  -- Smart deactivation: user opened a second normal buffer in a new window
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group    = group,
    callback = function()
      local state = split.state
      if not state.active then return end

      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if w ~= state.left_win and w ~= state.right_win then
          local bt = vim.bo[vim.api.nvim_win_get_buf(w)].buftype
          if bt == '' then
            split.deactivate()
            return
          end
        end
      end
    end,
  })

  -- Smart deactivation: diff mode turned on
  vim.api.nvim_create_autocmd('OptionSet', {
    pattern  = 'diff',
    group    = group,
    callback = function()
      if vim.v.option_new == '1' then
        split.deactivate()
      end
    end,
  })

  -- ------------------------------------------------------------------
  -- User command
  -- ------------------------------------------------------------------
  vim.api.nvim_create_user_command('ScrollFlowToggle', function()
    split.toggle()
  end, { desc = 'Toggle ScrollFlow newspaper-column layout' })
end

-- Convenience pass-throughs
function M.toggle()
  require('scrollflow.split').toggle()
end

function M.is_active()
  return require('scrollflow.split').state.active
end

return M
