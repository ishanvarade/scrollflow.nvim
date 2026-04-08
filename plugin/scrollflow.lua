-- plugin/scrollflow.lua
-- Bootstrap file. Neovim sources this automatically on startup.
-- If the user calls require('scrollflow').setup() in their config,
-- vim.g.scrollflow_setup_called is set and we skip auto-setup.
-- Otherwise we auto-initialise with defaults on VimEnter.

if vim.g.loaded_scrollflow then return end
vim.g.loaded_scrollflow = true

-- Register the command immediately so it works even before VimEnter.
vim.api.nvim_create_user_command('ScrollFlowToggle', function()
  -- Will trigger setup with defaults if not already set up.
  if not vim.g.scrollflow_setup_called then
    require('scrollflow').setup()
  end
  require('scrollflow').toggle()
end, { desc = 'Toggle ScrollFlow newspaper-column layout' })

-- Auto-setup with defaults if the user never called .setup()
vim.api.nvim_create_autocmd('VimEnter', {
  once     = true,
  callback = function()
    if not vim.g.scrollflow_setup_called then
      require('scrollflow').setup()
    end
  end,
})
