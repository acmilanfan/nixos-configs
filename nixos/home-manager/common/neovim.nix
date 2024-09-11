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
    codeium
    checkstyle
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

  xdg.configFile."nvim/parser".source = "${
      pkgs.symlinkJoin {
        name = "treesitter-parsers";
        paths = (pkgs.vimPlugins.nvim-treesitter.withPlugins (plugins:
          with plugins; [
            bash
            go
            hcl
            html
            http
            java
            javascript
            typescript
            vue
            lua
            luadoc
            make
            markdown
            nix
            python
            sql
            vim
            vimdoc
            comment
            json
            yaml
            toml
            xml
            c
            terraform
            kotlin
            jsdoc
            jq
            # groovy
            graphql
            gosum
            gomod
            gitignore
            git_rebase
            git_config
            dockerfile
            diff
            css
            org
          ])).dependencies;
      }
    }/parser";

  programs.neovim = {
    enable = true;
    vimAlias = true;
    withNodeJs = true;
    package = unstable.neovim-unwrapped;
    extraLuaPackages = luaPkgs:
      with luaPkgs; [
        lua-curl
        mimetypes
        xml2lua
        nvim-nio
      ];
    plugins = with unstable.vimPlugins; [
      vim-nix
      customPlugins.telescope-orgmode
      customPlugins.org-bullets
      # customPlugins.headlines-nvim
      customPlugins.nvim-macroni
      vim-table-mode
      sniprun
      diffview-nvim
      dracula-nvim
      # dracula-vim
      kanagawa-nvim
      tokyonight-nvim
      onedark-nvim
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
      undotree
      nvim-navic
      rainbow-delimiters-nvim
      cmp-fuzzy-path
      cmp-fuzzy-buffer
      cmp-nvim-lua
      cmp-tmux
      bigfile-nvim
      vim-tmux-clipboard
      {
        plugin = nvim-treesitter;
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
        plugin = harpoon2;
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
      {
        plugin = nvim-surround;
        config = lib.readFile ./neovim/nvim-surround.lua;
      }
      {
        plugin = refactoring-nvim;
        config = lib.readFile ./neovim/refactoring.lua;
      }
      {
        plugin = rest-nvim;
        config = lib.readFile ./neovim/rest-nvim.lua;
      }
      {
        plugin = codeium-nvim;
        config = lib.readFile ./neovim/codeium.lua;
      }
      {
        plugin = barbecue-nvim;
        config = lib.readFile ./neovim/barbecue.lua;
      }
      {
        plugin = nvim-navbuddy;
        config = lib.readFile ./neovim/navbuddy.lua;
      }
      {
        plugin = hardtime-nvim;
        config = lib.readFile ./neovim/hardtime.lua;
      }
      {
        plugin = actions-preview-nvim;
        config = lib.readFile ./neovim/actions-preview.lua;
      }
    ];
    extraLuaConfig = lib.readFile ./neovim/config.lua;
  };

}
