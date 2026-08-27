-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
require("config.keymaps")
require("config.options")

vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "BufEnter", "WinEnter", "CursorHold" }, {
  callback = function()
    vim.cmd("checktime")
  end,
})
