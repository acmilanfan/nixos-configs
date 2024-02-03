{ pkgs, lib, unstable, ... }:

let
  customPlugins = pkgs.callPackage ./neovim/plugins.nix {
    inherit (pkgs.vimUtils) buildVimPluginFrom2Nix;
  };
  jdtlsWrapped = pkgs.writeShellScriptBin "jdtls" ''
    ${unstable.jdt-language-server}/bin/jdtls \
      -data $HOME/.cache/jdtls/$PWD \
      --jvm-arg=-javaagent:${unstable.lombok}/share/java/lombok.jar
  '';
in {
  home.packages = with pkgs; [
    (writeShellScriptBin "tmux-sessionizer"
      (lib.readFile ./scripts/tmux-sessionizer))
    jdtlsWrapped
    tree-sitter
    ripgrep
    gopls
    lua-language-server
    nil
    sqls
    lazygit
    fzf
    fd
    tmux-sessionizer
    go
    lombok
    maven
    stylua
    kotlin-language-server
    terraform-ls
    yaml-language-server
    yamllint
    yamlfix
    statix
    google-java-format
    golines
    goimports-reviser
    lemminx
    nodePackages.volar
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.vscode-json-languageserver
    nodePackages.prettier
    nodePackages.eslint
    nodePackages.graphql-language-service-cli
    nodePackages.fixjson
    vscode-extensions.vscjava.vscode-java-test
  ];

  home.sessionVariables = { EDITOR = "nvim"; };
  programs.neovim = {
    enable = true;
    vimAlias = true;
    withNodeJs = true;
    package = unstable.neovim-unwrapped;
    plugins = with unstable.vimPlugins; [
      vim-nix
      customPlugins.telescope-orgmode
      customPlugins.org-bullets
      customPlugins.headlines-nvim
      customPlugins.nvim-macroni
      vim-table-mode
      sniprun
      diffview-nvim
      nord-nvim
      dracula-nvim
      # dracula-vim
      kanagawa-nvim
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
      nvim-jdtls
      cmp-emoji
      friendly-snippets
      FTerm-nvim
      telescope-ui-select-nvim
      actions-preview-nvim
      {
        plugin = (nvim-treesitter.withPlugins (plugins:
          with plugins; [
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
            tree-sitter-luadoc
            tree-sitter-make
            tree-sitter-markdown
            tree-sitter-nix
            tree-sitter-python
            tree-sitter-sql
            tree-sitter-org-nvim
            tree-sitter-vim
            tree-sitter-vimdoc
            tree-sitter-comment
            tree-sitter-json
            tree-sitter-yaml
            tree-sitter-toml
            tree-sitter-xml
            tree-sitter-c
            tree-sitter-terraform
            tree-sitter-kotlin
            tree-sitter-jsdoc
            tree-sitter-jq
            tree-sitter-groovy
            tree-sitter-graphql
            tree-sitter-gosum
            tree-sitter-gomod
            tree-sitter-gitignore
            tree-sitter-gitcommit
            tree-sitter-gitattributes
            tree-sitter-git_rebase
            tree-sitter-git_config
            tree-sitter-dockerfile
            tree-sitter-diff
            tree-sitter-css
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
        config = lib.readFile ./neovim/colorscheme.lua;
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
