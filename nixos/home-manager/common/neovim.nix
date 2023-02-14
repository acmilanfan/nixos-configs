{ pkgs, config, ... }: 

  let 
    lua = text: ''
      lua << EOF
      ${text}
      EOF
    '';
  in {
    home.sessionVariables = { EDITOR = "nvim"; };
    programs.neovim = {
      enable = true;
      vimAlias = true;
      plugins = with pkgs.vimPlugins; [
        (nvim-treesitter.withPlugins (plugins: with plugins; [ 
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
          tree-sitter-norg 
          tree-sitter-python 
          tree-sitter-sql 
        ]))
        vim-nix
        telescope-nvim 
        nvim-cmp
        {
          # requires node.js
          plugin = nvim-treesitter;
          config = lua ''
            local parser_configs = require('nvim-treesitter.parsers').get_parser_configs()
            parser_configs.norg_meta = {
                install_info = {
                    url = "https://github.com/nvim-neorg/tree-sitter-norg-meta",
                    files = { "src/parser.c" },
                    branch = "main"
                },
            }
            parser_configs.norg_table = {
                install_info = {
                    url = "https://github.com/nvim-neorg/tree-sitter-norg-table",
                    files = { "src/parser.c" },
                    branch = "main"
                },
            }
            require'nvim-treesitter.configs'.setup {
              -- One of "all", "maintained" (parsers with maintainers), or a list of languages
              ensure_installed = "all",
              -- Install languages synchronously (only applied to `ensure_installed`)
              sync_install = false,
              -- List of parsers to ignore installing
              --ignore_install = { "javascript" },
              highlight = {
                -- `false` will disable the whole extension
                enable = true,
                -- list of language that will be disabled
                --disable = { "c", "rust" },
                -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
                -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
                -- Using this option may slow down your editor, and you may see some duplicate highlights.
                -- Instead of true it can also be a list of languages
                additional_vim_regex_highlighting = false,
              },
            }
          '';
        }
        {
          # neorg requires plenary, and requires that treesitter is loaded before neorg
          plugin = neorg;
          config = lua ''
            require('neorg').setup {
              -- Tell Neorg what modules to load
              load = {
                  ["core.defaults"] = {}, -- Load all the default modules
                  ["core.gtd.base"] = {
                      config = {
                          -- workspace =   "example_gtd" , -- assign the workspace,
                          workspace = "home",
                          exclude = { "notes/" }, -- Optional: all excluded files from the workspace are not part of the gtd workflow
                          projects = {
                            show_completed_projects = false,
                            show_projects_without_tasks = false,
                          },
                          custom_tag_completion = true,
                      },
                  },
                  ["core.norg.completion"] = { config = { engine = "nvim-cmp" } },
                  ["core.norg.concealer"] = {}, -- Allows for use of icons
                  ["core.norg.dirman"] = { -- Manage your directories with Neorg
                      config = {
                          workspaces = {
                              home = "~/neorg",
                              notes = "~/neorg/notes"
                          },
                          index = "index.norg"
                      }
                  }
              },
            }
            local neorg_callbacks = require("neorg.callbacks")
            local neorg = require('neorg')
            local function load_completion()
                neorg.modules.load_module("core.norg.completion", nil, {
                    engine = "nvim-cmp" -- Choose your completion engine here
                })
            end
            -- If Neorg is loaded already then don't hesitate and load the completion
            if neorg.is_loaded() then
                load_completion()
            else -- Otherwise wait until Neorg gets started and load the completion module then
                neorg.callbacks.on_event("core.started", load_completion)
            end
          '';
        }
      ];
      extraConfig = ''
#        nnoremap yy "+yy
#        vnoremap y "+y
#        nnoremap p "+p
#        vnoremap p "+p
#        nnoremap P "+P
#        vnoremap P "+P
#        nnoremap dd "+dd
#        vnoremap d "+d
        set clipboard+=unnamedplus
        set nu rnu
      '';
    };

}
