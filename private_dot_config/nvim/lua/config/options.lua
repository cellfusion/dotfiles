-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
local opt = vim.opt

opt.backup = false
opt.swapfile = false

opt.iminsert = 0
opt.imsearch = 0

opt.spell = false
opt.spelllang = { "en", "cjk" }

-- clear statusline
opt.laststatus = 0
opt.statusline = "─"
opt.fillchars:append({ stl = "─", stlnc = "─" })

-- picker
-- vim.g.lazyvim_picker = "telescope"

-- window title
vim.o.title = true
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function()
    -- 現在の絶対パスを取得
    local fullpath = vim.fn.expand("%:p")
    if fullpath == "" then
      vim.o.titlestring = "NVIM"
      return
    end

    -- git root (.git があるディレクトリ) を探す
    local git_root = vim.fs.root(0, ".git")
    local relpath = fullpath

    -- git root が取得できていて、パスの先頭が一致したら
    if type(git_root) == "string" then
      -- 先頭の git_root + "/" を消す
      relpath = fullpath:gsub("^" .. vim.pesc(git_root) .. "/", "")
    end

    -- タイトルにセット
    vim.o.titlestring = relpath .. " - NVIM"
  end,
})
-- 終了時にタイトルを空に
vim.api.nvim_create_autocmd("VimLeave", {
  callback = function()
    -- ターミナルタイトルクリアのエスケープ
    vim.fn.system("printf '\\033]2;\\007'")
  end,
})
