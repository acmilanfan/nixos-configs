{ pkgs, config, lib, unstable, ... }:

let
  customPlugins = pkgs.callPackage ./neovim/plugins.nix {
    inherit (pkgs.vimUtils) buildVimPluginFrom2Nix;
  };
in {
  home.sessionVariables = { EDITOR = "nvim"; };
  programs.neovim = {
    enable = true;
    vimAlias = true;
    withNodeJs = true;
    package = unstable.neovim-unwrapped;
    plugins = with unstable.vimPlugins; [
      {
        plugin = (nvim-treesitter.withPlugins (plugins: with plugins; [
          tree-sitter-bash
          tree-sitter-go
          tree-sitter-hcl
          tree-sitter-html
          tree-sitter-http
          tree-sitter-java
          tree-sitter-javascript
          tree-sitter-lua
          tree-sitter-make
          tree-sitter-markdown
          tree-sitter-nix
          tree-sitter-python
          tree-sitter-sql
          tree-sitter-org-nvim
        ]));
        config = lib.readFile ./neovim/treesitter.lua;
      }
      vim-nix
      customPlugins.telescope-orgmode
      {
        plugin = telescope-nvim;
        config = lib.readFile ./neovim/telescope.lua;
      }
      vim-table-mode
      sniprun
      customPlugins.org-bullets
      customPlugins.headlines-nvim
      legendary-nvim
      diffview-nvim
      nord-nvim
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
        plugin = wilder-nvim;
        config = lib.readFile ./neovim/wilder.lua;
      }
      {
        plugin = which-key-nvim;
        config = lib.readFile ./neovim/which-key.lua;
      }
    ];
    extraConfig = ''
      nnoremap yy "+yy
      vnoremap y "+y
      nnoremap p "+p
      vnoremap p "+p
      nnoremap P "+P
      vnoremap P "+P
      nnoremap dd "+dd
      vnoremap d "+d

      set clipboard+=unnamedplus
      set nu rnu
      set conceallevel=2
      set shiftwidth=2
      set tabstop=2
      set autoindent
      set smartindent

      let mapleader = " "

      nnoremap <leader>ff <cmd>Telescope find_files<cr>
      nnoremap <leader>fg <cmd>Telescope live_grep<cr>
      nnoremap <leader>fb <cmd>Telescope buffers<cr>
      nnoremap <leader>fh <cmd>Telescope help_tags<cr>
      nnoremap <leader>nw <cmd>set wrap!<cr>
      nnoremap <C-I> <C-I>
    '';
  };

}
