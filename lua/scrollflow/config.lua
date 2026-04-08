-- scrollflow/config.lua
-- Default configuration and setup

local M = {}

M.defaults = {
  -- Master enable switch
  enabled = true,
  -- Show fake continuous relative numbers across panes
  fake_numbers = true,
  -- Width of the number column
  number_width = 4,
  -- Filetypes where ScrollFlow should not activate
  exclude_filetypes = {
    'help', 'qf', 'NvimTree', 'neo-tree', 'TelescopePrompt',
    'lazy', 'mason', 'noice', 'notify',
  },
  -- Buffer types where ScrollFlow should not activate
  -- Empty string = normal buffer; others are excluded
  exclude_buftypes = { 'terminal', 'prompt', 'nofile', 'quickfix', 'help' },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.defaults, opts or {})
end

return M
