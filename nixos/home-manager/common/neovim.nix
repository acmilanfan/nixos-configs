{ pkgs, lib, unstable, ... }:

let
  customPlugins = pkgs.callPackage ./neovim/plugins.nix {
    inherit (pkgs.vimUtils) buildVimPluginFrom2Nix;
  };
in {
  home.sessionVariables = {
    EDITOR = "nvim";
  };
  programs.neovim = {
    enable = true;
    vimAlias = true;
    withNodeJs = true;
    package = unstable.neovim-unwrapped;
    extraPackages = with pkgs; [
      tree-sitter
      ripgrep
      gopls
      lua-language-server
      nil
      sqls
      lazygit
      go
      fzf
      fd
      nodePackages.volar
      nodePackages.typescript
      nodePackages.typescript-language-server
      nodePackages.vscode-json-languageserver
    ];
    plugins = with unstable.vimPlugins; [
      vim-nix
      customPlugins.telescope-orgmode
      vim-table-mode
      sniprun
      customPlugins.org-bullets
      customPlugins.headlines-nvim
      legendary-nvim
      diffview-nvim
      nord-nvim
      nvim-notify
      luasnip
      trouble-nvim
      lazygit-nvim
      plenary-nvim
      telescope-symbols-nvim
      vim-sleuth
      telescope-fzf-native-nvim
      nvim-lspconfig
      cmp-nvim-lsp
      firenvim
      vim-tmux-navigator
      {
        plugin = (nvim-treesitter.withPlugins (plugins: with plugins; [
          tree-sitter-bash
          tree-sitter-go
          tree-sitter-hcl
          tree-sitter-html
          tree-sitter-http
          tree-sitter-java
          tree-sitter-javascript
          tree-sitter-typescript
          tree-sitter-vue
          tree-sitter-lua
          tree-sitter-make
          tree-sitter-markdown
          tree-sitter-nix
          tree-sitter-python
          tree-sitter-sql
          tree-sitter-org-nvim
          tree-sitter-vim
          tree-sitter-comment
        ]));
        config = lib.readFile ./neovim/treesitter.lua;
      }
      {
        plugin = telescope-nvim;
        config = lib.readFile ./neovim/telescope.lua;
      }
      {
        plugin = lualine-nvim;
        config = lib.readFile ./neovim/lualine.lua;
      }
      {
        plugin = orgmode;
        config = lib.readFile ./neovim/orgmode.lua;
      }
      {
        plugin = nvim-cmp;
        config = lib.readFile ./neovim/cmp.lua;
      }
      {
        plugin = nvim-tree-lua;
        config = lib.readFile ./neovim/nvim-tree.lua;
      }
      {
        plugin = nightfox-nvim;
        config = lib.readFile ./neovim/nightfox.lua;
      }
      {
        plugin = nvim-web-devicons;
        config = lib.readFile ./neovim/nvim-web-devicons.lua;
      }
      {
        plugin = hop-nvim;
        config = lib.readFile ./neovim/hop.lua;
      }
      {
        plugin = indent-blankline-nvim;
        config = lib.readFile ./neovim/indent-blankline.lua;
      }
      {
        plugin = comment-nvim;
        config = lib.readFile ./neovim/comment.lua;
      }
      {
        plugin = which-key-nvim;
        config = lib.readFile ./neovim/which-key.lua;
      }
      {
        plugin = noice-nvim;
        config = lib.readFile ./neovim/noice.lua;
      }
      {
        plugin = inc-rename-nvim;
        config = lib.readFile ./neovim/inc-rename.lua;
      }
      {
        plugin = fidget-nvim;
        config = lib.readFile ./neovim/fidget.lua;
      }
      {
        plugin = gitsigns-nvim;
        config = lib.readFile ./neovim/gitsigns.lua;
      }
      {
        plugin = go-nvim;
        config = lib.readFile ./neovim/go.lua;
      }
      {
        plugin = todo-comments-nvim;
        config = lib.readFile ./neovim/todo-comments.lua;
      }
      {
        plugin = harpoon;
        config = lib.readFile ./neovim/harpoon.lua;
      }
      {
        plugin = none-ls-nvim;
        config = lib.readFile ./neovim/null-ls.lua;
      }
      {
        plugin = nvim-autopairs;
        config = lib.readFile ./neovim/autopairs.lua;
      }
      {
        plugin = highlight-undo-nvim;
        config = lib.readFile ./neovim/highlight-undo.lua;
      }
    ];
    extraLuaConfig = lib.readFile ./neovim/config.lua;
  };

}
