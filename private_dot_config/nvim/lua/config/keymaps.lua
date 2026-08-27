-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })

if vim.g.vscode then
  local keymap = vim.keymap.set
  local opts = { noremap = true, silent = true }
  local vscode = require("vscode")

  -- remap leader key
  keymap("n", "<Space>", "", opts)

  -- yank to system clipboard
  keymap({ "n", "v" }, "<leader>y", '"+y', opts)

  -- paste from system clipboard
  keymap({ "n", "v" }, "<leader>p", '"+p', opts)

  -- better indent handling
  keymap("v", "<", "<gv", opts)
  keymap("v", ">", ">gv", opts)

  -- move text up and down
  keymap("v", "J", ":m .+1<CR>==", opts)
  keymap("v", "K", ":m .-2<CR>==", opts)
  keymap("x", "J", ":move '>+1<CR>gv-gv", opts)
  keymap("x", "K", ":move '<-2<CR>gv-gv", opts)

  -- paste preserves primal yanked piece
  keymap("v", "p", '"_dP', opts)

  -- removes highlighting after escaping vim search
  keymap("n", "<Esc>", "<Esc>:noh<CR>", opts)

  -- focus VSCode explorer view
  -- keymap("n", "<leader>e", function()
  --     vscode.action("workbench.view.explorer")
  -- end, opts)

  -- focus VSCode source control view
  -- keymap("n", "<leader>gg", function()
  --     vscode.action("workbench.view.scm")
  -- end, opts)

  -- focus chat view
  -- keymap("n", "<leader>ac", function()
  --     -- vscode.action("chatgpt.sidebarView.focus")
  --     vscode.action("workbench.panel.chat")
  -- end, opts)

  -- send selected text to Codex AI
  -- keymap("v", "<leader>ac", function()
  --     vscode.action("chatgpt.addToThread")
  -- end, opts)

  -- -- focus terminal in VSCode
  -- keymap("n", "<leader>ft", function()
  --     vscode.action("workbench.action.terminal.focus")
  -- end, opts)

  -- -- focus output panel in VSCode
  -- keymap("n", "<leader>cl", function()
  --     vscode.action("workbench.panel.output.focus")
  -- end, opts)

  -- -- quick switch windows
  -- keymap("n", "<leader>ws", function()
  --     vscode.action("workbench.action.quickSwitchWindow")
  -- end, opts)

  -- -- focus open editors view(buffer list)
  -- keymap("n", "<leader>fb", function()
  --     vscode.action("workbench.files.action.focusOpenEditorsView")
  -- end, opts)

  -- -- find files in VSCode
  -- keymap("n", "<leader><space>", function()
  --     vscode.action("workbench.action.quickOpen")
  -- end, opts)

  -- -- focus diagnostics panel
  -- keymap("n", "<leader>sd", function()
  --     vscode.action("workbench.actions.view.problems")
  -- end, opts)

  -- -- grep
  -- keymap("n", "<leader>sg", function()
  --     vscode.action("workbench.action.findInFiles")
  -- end, opts)

  -- code action
  -- keymap("n", "<leader>ca", function()
  --     vscode.action("editor.action.quickFix")
  -- end, opts)

  -- rename
  keymap("n", "<leader>cr", function()
    vscode.action("editor.action.rename")
  end, opts)

  -- signature help
  keymap("n", "gk", function()
    vscode.action("editor.action.triggerParameterHints")
  end, opts)

  -- References
  keymap("n", "gr", function()
    vscode.action("editor.action.goToReferences")
  end, opts)

  -- next buffer
  -- keymap("n", "<S-l>", function()
  --     vscode.action("workbench.action.nextEditor")
  -- end, opts)
  -- keymap("n", "]b", function()
  --     vscode.action("workbench.action.previousEditor")
  -- end, opts)

  -- previous buffer
  -- keymap("n", "<S-h>", function()
  --     vscode.action("workbench.action.previousEditor")
  -- end, opts)
  -- keymap("n", "[b", function()
  --     vscode.action("workbench.action.previousEditor")
  -- end, opts)
else
  -- Seamless Vim <-> multiplexer split navigation.
  -- <C-w>h/j/k/l moves between Neovim splits; at a split edge it hands off to the
  -- surrounding multiplexer so focus crosses into the neighbouring pane. This
  -- overrides LazyVim's plain <C-w>h/j/k/l (splits only) with a pane-aware version.
  -- The bare <C-h/j/k/l> chords are NOT usable here: herdr claims all four
  -- (ctrl+h/l for tabs, ctrl+j/k for workspaces) before the pane sees them.
  -- tmux is kept as a fallback so an old tmux session still works.
  -- Uses the LazyVimKeymaps autocmd to re-assert after every M.load("keymaps").
  if vim.env.HERDR_PANE_ID or vim.env.TMUX then
    local function setup_nav()
      local function navigate(wincmd, herdr_dir, tmux_flag)
        return function()
          local prev = vim.api.nvim_get_current_win()
          vim.cmd("wincmd " .. wincmd)
          if vim.api.nvim_get_current_win() ~= prev then
            return -- moved within Neovim
          end
          -- At a split edge: cross into the surrounding multiplexer.
          if vim.env.HERDR_PANE_ID and vim.env.HERDR_PANE_ID ~= "" then
            local herdr = vim.env.HERDR_BIN_PATH
            if herdr == nil or herdr == "" then
              herdr = "herdr"
            end
            vim.fn.system({ herdr, "pane", "focus", "--direction", herdr_dir, "--current" })
          elseif vim.env.TMUX and vim.env.TMUX ~= "" then
            vim.fn.system({ "tmux", "select-pane", "-" .. tmux_flag })
          end
        end
      end

      vim.keymap.set("n", "<C-w>h", navigate("h", "left", "L"), { silent = true, desc = "Navigate Left (herdr/tmux-aware)" })
      vim.keymap.set("n", "<C-w>j", navigate("j", "down", "D"), { silent = true, desc = "Navigate Down (herdr/tmux-aware)" })
      vim.keymap.set("n", "<C-w>k", navigate("k", "up", "U"), { silent = true, desc = "Navigate Up (herdr/tmux-aware)" })
      vim.keymap.set("n", "<C-w>l", navigate("l", "right", "R"), { silent = true, desc = "Navigate Right (herdr/tmux-aware)" })
    end

    setup_nav()
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyVimKeymaps",
      callback = setup_nav,
    })
  end
end
