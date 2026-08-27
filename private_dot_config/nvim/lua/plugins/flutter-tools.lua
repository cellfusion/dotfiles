-- Flutter / Dart。LazyVim の lang.dart extra は使わない。extra は dartls を
-- nvim-lspconfig 経由で設定するので、flutter-tools が立てる dartls と二重になる。
-- SDK はプロジェクト直下の .fvm/flutter_sdk を見る（fvm use していないと解決できない）。

local function map_flutter_keys(buf)
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add({ { "<leader>F", group = "flutter", buffer = buf } })
  end

  local map = function(lhs, cmd, desc)
    vim.keymap.set("n", lhs, "<cmd>" .. cmd .. "<cr>", { buffer = buf, desc = desc })
  end

  map("<leader>Fr", "FlutterRun", "Run")
  map("<leader>Fl", "FlutterReload", "Hot reload")
  map("<leader>FR", "FlutterRestart", "Restart")
  map("<leader>Fq", "FlutterQuit", "Quit")
  map("<leader>Fd", "FlutterDevices", "Devices")
  map("<leader>Fe", "FlutterEmulators", "Emulators")
  map("<leader>Fo", "FlutterOutlineToggle", "Outline toggle")
  map("<leader>FD", "FlutterDevTools", "DevTools")
  map("<leader>Fp", "FlutterPubGet", "Pub get")
  map("<leader>FL", "FlutterLogToggle", "Log toggle")
end

return {
  {
    "nvim-flutter/flutter-tools.nvim",
    ft = "dart",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = function()
      return {
        fvm = true,
        lsp = {
          capabilities = LazyVim.has("blink.cmp") and require("blink.cmp").get_lsp_capabilities() or nil,
        },
      }
    end,
    config = function(_, opts)
      require("flutter-tools").setup(opts)

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "dart",
        callback = function(ev)
          map_flutter_keys(ev.buf)
        end,
      })

      -- ft トリガーでロードされた時点で、そのバッファの FileType は発火済みのことがある。
      -- 開いている dart バッファには直接張る。
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "dart" then
          map_flutter_keys(buf)
        end
      end
    end,
  },
}
