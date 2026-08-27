return {
  "folke/snacks.nvim",
  -- @type snacks.Config
  opts = {
    picker = {
      sources = {
        explorer = {
          ignored = true,
          hidden = true,
          auto_close = true, -- ファイルを開いたら自動的に閉じる
          -- フローティングレイアウトに変更
          layout = {
            preset = "default", -- サイドバーではなくフローティングレイアウトを使用
            preview = true, -- 右側にプレビューを表示
          },
        },
        files = {
          hidden = true, -- 隠しファイル（.で始まるファイル）を表示
          ignored = false, -- .gitignore で無視されたファイル（node_modules 等）は除外
        },
        grep = {
          hidden = true, -- grep でも隠しファイルを検索対象に含める
        },
      },
    },
    image = {},
  },
  keys = {
    {
      "<leader>gg",
      function()
        if vim.env.TMUX then
          local git_root = vim.fn
            .system("git -C " .. vim.fn.shellescape(vim.fn.expand("%:p:h")) .. " rev-parse --show-toplevel 2>/dev/null")
            :gsub("\n", "")
          if vim.v.shell_error ~= 0 or git_root == "" then
            git_root = vim.fn.getcwd()
          end
          vim.fn.system({ "tmux", "new-window", "-c", git_root, "lazygit" })
        else
          Snacks.lazygit({ cwd = LazyVim.root.git() })
        end
      end,
      desc = "Lazygit (Root Dir)",
    },
    {
      "<leader>gG",
      function()
        if vim.env.TMUX then
          vim.fn.system({
            "tmux", "new-window", "-c", vim.fn.getcwd(), "lazygit",
          })
        else
          Snacks.lazygit()
        end
      end,
      desc = "Lazygit (cwd)",
    },
  },
}
