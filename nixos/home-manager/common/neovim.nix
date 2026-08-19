{
  pkgs,
  lib,
  unstable,
  secrets,
  ...
}:

let
  customPlugins = pkgs.callPackage ./neovim/plugins.nix {
    inherit (pkgs.vimUtils) buildVimPlugin;
  };
  jdtlsWrapped = pkgs.writeShellScriptBin "jdtls" ''
    ${unstable.jdt-language-server}/bin/jdtls \
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
    typescript
    typescript-language-server
    vscode-json-languageserver
    prettier
    eslint
    graphql-language-service-cli
    fixjson
    glow
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
    # ANTHROPIC_API_KEY = secrets.aiProxy.claudeKey;
    # ANTHROPIC_BASE_URL = secrets.aiProxy.claude;
    # opencode: self-hosted model via the internal AI proxy.
    # Prefers an explicit secrets.aiProxy.selfHosted, else derives it from the
    # Claude endpoint so no company host needs a new secrets key right away.
    SELF_HOSTED_BASE_URL =
      secrets.aiProxy.selfHosted or (
        lib.replaceStrings [ "/proxy-api/anthropic" ] [ "/proxy-api/self-hosted/v1" ] secrets.aiProxy.claude
      );
    SELF_HOSTED_API_KEY = secrets.aiProxy.selfHostedKey or secrets.aiProxy.apiKey;
    # opencode: github/sonarqube MCP servers (work only; harmless empty string on mac-home).
    GITHUB_PERSONAL_ACCESS_TOKEN = (secrets.github or { }).token or "";
    SONAR_API_KEY = (secrets.sonar or { }).apiKey or "";
    SONAR_URL = (secrets.sonar or { }).url or "";
    # opencode: internal RAG/scorecard MCP servers (work only; company URLs stay
    # in the secrets submodule, never literally in opencode.json).
    RAG_MCP_URL = (secrets.mcp or { }).ragUrl or "";
    SCORECARD_MCP_URL = (secrets.mcp or { }).scorecardUrl or "";
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
      pkgs.vimPlugins.refactoring-nvim
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
      glow-nvim
    ];
    # Load the main init.lua which requires all other modules
    initLua = ''
      require("init")
    '';
  };

}
