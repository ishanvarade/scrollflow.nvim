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
      -- Defer so the window has settled to its final dimensions.
      -- Re-check that win still shows buf: rapid buffer changes (or stale
      -- callbacks from a previous BufWinEnter) must not activate with a
      -- buffer that is no longer in the window.
      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)
            and vim.api.nvim_win_get_buf(win) == buf then
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
        -- Right pane was closed externally: deactivate without trying to
        -- close it again. BUG-B fix: deactivate() now fires the event
        -- before clearing state, so handlers can still read state.buf etc.
        split.deactivate({ skip_close = true })

      elseif closed == state.left_win then
        -- Left pane closed: close right pane too (right_win is still open)
        split.deactivate()
      end
    end,
  })

  -- BUG-L fix: deactivate when the user switches to a different tabpage.
  -- Single state table can't track multiple tabs; deactivate on tab leave.
  vim.api.nvim_create_autocmd('TabEnter', {
    group    = group,
    callback = function()
      local state = split.state
      if not state.active then return end
      if vim.api.nvim_get_current_tabpage() ~= state.tabpage then
        split.deactivate()
      end
    end,
  })

  -- Smart deactivation: buffer changed in one of our panes (e.g. :e otherfile)
  -- or user opened a second normal buffer in a new window
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group    = group,
    callback = function()
      local state = split.state
      if not state.active then return end

      -- BUG-3 fix: detect :e in left pane — buffer swapped under us
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)
      if (win == state.left_win or win == state.right_win) and buf ~= state.buf then
        split.deactivate()
        return
      end

      -- BUG-10 fix: validate window before accessing its buffer
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if w ~= state.left_win and w ~= state.right_win then
          if vim.api.nvim_win_is_valid(w) then
            local bt = vim.bo[vim.api.nvim_win_get_buf(w)].buftype
            if bt == '' then
              split.deactivate()
              return
            end
          end
        end
      end
    end,
  })

  -- Smart deactivation: file shrank below window height after deletions
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group    = group,
    callback = function()
      local state = split.state
      if not state.active then return end
      if not vim.api.nvim_win_is_valid(state.left_win) then return end
      local line_count = vim.api.nvim_buf_line_count(state.buf)
      local height     = vim.api.nvim_win_get_height(state.left_win)
      if line_count <= height then
        split.deactivate()
      end
    end,
  })

  -- Smart deactivation: diff mode turned on
  vim.api.nvim_create_autocmd('OptionSet', {
    pattern  = 'diff',
    group    = group,
    callback = function()
      -- BUG-5 fix: v:option_new is a number (0/1) for boolean options, not '1'
      local v = vim.v.option_new
      if v == 1 or v == true or v == '1' then
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
