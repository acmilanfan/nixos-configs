{ lib, buildVimPlugin, inputs }:

# Sources are non-flake inputs in flake.nix, pinned by flake.lock; bump them
# with `pins update <name>`.
let
  plugin = pname: src: buildVimPlugin {
    inherit pname src;
    version =
      let d = src.lastModifiedDate;
      in "unstable-${lib.substring 0 4 d}-${lib.substring 4 2 d}-${lib.substring 6 2 d}";
  };
in
{
  telescope-orgmode = plugin "telescope-orgmode" inputs.telescope-orgmode;
  org-bullets = plugin "org-bullets" inputs.org-bullets;

  # headlines-nvim = buildVimPlugin {
  #   pname = "headlines";
  #   version = "v3.3.0";
  #   src = fetchFromGitHub {
  #     owner = "lukas-reineke";
  #     repo = "headlines.nvim";
  #     rev = "618ef1b2502c565c82254ef7d5b04402194d9ce3";
  #     sha256 = "02zri3vmzjxv47qnlll3nf71i9ji8nhdabpvf4566i7iwwagqpym";
  #   };
  # };

  nvim-macroni = plugin "macroni" inputs.nvim-macroni;
  lsplinks-nvim = plugin "lsplinks" inputs.lsplinks-nvim;
  nvim-java = plugin "nvim-java" inputs.nvim-java;
  spring-boot-nvim = plugin "spring-boot-nvim" inputs.spring-boot-nvim;
  lua-async-await = plugin "lua-async-await" inputs.lua-async;
  nvim-java-refactor = plugin "nvim-java-refactor" inputs.nvim-java-refactor;
  nvim-java-core = plugin "nvim-java-core" inputs.nvim-java-core;
  nvim-java-test = plugin "nvim-java-test" inputs.nvim-java-test;
  nvim-java-dap = plugin "nvim-java-dap" inputs.nvim-java-dap;
}
