-- plugin/scrollflow.lua
-- Bootstrap file. Neovim sources this automatically on startup.
-- If the user calls require('scrollflow').setup() in their config,
-- vim.g.scrollflow_setup_called is set and we skip auto-setup.
-- Otherwise we auto-initialise with defaults on VimEnter.

if vim.g.loaded_scrollflow then return end
vim.g.loaded_scrollflow = true

-- BUG-K fix: wrap require in pcall so load errors show a clean message
-- instead of a raw Lua traceback that blocks startup.
local function safe_setup(opts)
  local ok, err = pcall(function()
    require('scrollflow').setup(opts)
  end)
  if not ok then
    vim.notify('ScrollFlow failed to load: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

-- Register the command immediately so it works even before VimEnter.
vim.api.nvim_create_user_command('ScrollFlowToggle', function()
  if not vim.g.scrollflow_setup_called then
    safe_setup()
  end
  local ok, err = pcall(function() require('scrollflow').toggle() end)
  if not ok then
    vim.notify('ScrollFlowToggle error: ' .. tostring(err), vim.log.levels.ERROR)
  end
end, { desc = 'Toggle ScrollFlow newspaper-column layout' })

-- Auto-setup with defaults if the user never called .setup()
vim.api.nvim_create_autocmd('VimEnter', {
  once     = true,
  callback = function()
    if not vim.g.scrollflow_setup_called then
      safe_setup()
    end
  end,
})
