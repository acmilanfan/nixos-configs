{
  pkgs,
  lib,
  unstable,
  secrets,
  ...
}:

let
  customPlugins = pkgs.callPackage ./neovim/plugins.nix {
    inherit (pkgs.vimUtils) buildVimPluginFrom2Nix;
  };
  jdtlsWrapped = pkgs.writeShellScriptBin "jdtls" ''
    ${unstable.jdt-language-server}/bin/jdtls \
      -data $HOME/.cache/jdtls/$PWD \
      --jvm-arg=-javaagent:${unstable.lombok}/share/java/lombok.jar
  '';
in
{
  home.packages = with pkgs; [
    (writeShellScriptBin "tmux-sessionizer" (lib.readFile ./scripts/tmux-sessionizer))
    jdtlsWrapped
    tree-sitter
    ripgrep
    gopls
    gotests
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
    # codeium
    checkstyle
    # goose-cli
    unzip
    vue-language-server
    bash-language-server
    reftools
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.vscode-json-languageserver
    nodePackages.prettier
    nodePackages.eslint
    nodePackages.graphql-language-service-cli
    nodePackages.fixjson
    # vscode-extensions.vscjava.vscode-java-test
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    # AI proxy secrets - these are set as env vars to avoid storing in /nix/store
    AI_PROXY_CLAUDE = secrets.aiProxy.claude;
    AI_PROXY_OPENAI = secrets.aiProxy.openai;
    AI_PROXY_MISTRAL_COMPLETION = secrets.aiProxy.mistralCompletion;
    AI_PROXY_API_KEY = secrets.aiProxy.apiKey;
    ANTHROPIC_API_KEY = secrets.aiProxy.claudeKey;
    ANTHROPIC_BASE_URL = secrets.aiProxy.claude;
  };

  # Place Lua configuration files in ~/.config/nvim/lua/
  xdg.configFile = {
    "nvim/lua/init.lua".source = ./neovim/lua/init.lua;
    "nvim/lua/config.lua".source = ./neovim/lua/config.lua;
    "nvim/lua/plugins".source = ./neovim/lua/plugins;
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    withNodeJs = true;
    package = unstable.neovim-unwrapped;
    extraLuaPackages =
      luaPkgs: with luaPkgs; [
        lua-curl
        mimetypes
        xml2lua
        nvim-nio
        tree-sitter-orgmode
      ];
    plugins = with unstable.vimPlugins; [
      vim-nix
      customPlugins.org-bullets
      # customPlugins.headlines-nvim
      customPlugins.nvim-macroni
      customPlugins.lsplinks-nvim
      vim-table-mode
      sniprun
      diffview-nvim
      dracula-nvim
      kanagawa-nvim
      tokyonight-nvim
      onedark-nvim
      rose-pine
      # vim-colors-solarized
      # solarized-nvim
      # nvim-solarized-lua
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
      # vim-tmux-navigator
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
      twilight-nvim
      SchemaStore-nvim
      vim-repeat
      lf-vim
      nvim-treesitter-textobjects
      nvim-treesitter.withAllGrammars
      telescope-nvim
      lualine-nvim
      orgmode
      nvim-cmp
      nvim-tree-lua
      nightfox-nvim
      nvim-web-devicons
      hop-nvim
      indent-blankline-nvim
      comment-nvim
      which-key-nvim
      noice-nvim
      inc-rename-nvim
      fidget-nvim
      gitsigns-nvim
      (go-nvim.overrideAttrs (old: {
        doCheck = false;
      }))
      (customPlugins.telescope-orgmode.overrideAttrs (old: {
        doCheck = false;
      }))
      todo-comments-nvim
      harpoon2
      none-ls-nvim
      nvim-autopairs
      highlight-undo-nvim
      nvim-surround
      refactoring-nvim
      rest-nvim
      # windsurf-nvim
      barbecue-nvim
      nvim-navbuddy
      hardtime-nvim
      actions-preview-nvim
      zen-mode-nvim
      cloak-nvim
      nvim-pqf
      snacks-nvim
      oil-nvim
      avante-nvim
      minuet-ai-nvim
    ];
    # Load the main init.lua which requires all other modules
    extraLuaConfig = ''
      require("init")
    '';
  };

}
