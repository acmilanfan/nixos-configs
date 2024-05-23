{ lib, buildVimPluginFrom2Nix, fetchFromGitHub, fetchgit }:

{
  telescope-orgmode = buildVimPluginFrom2Nix {
    pname = "telescope-orgmode";
    version = "main";
    src = fetchFromGitHub {
      owner = "lyz-code";
      repo = "telescope-orgmode.nvim";
      rev = "02d6876ac80e7e039926fdb69e88300c04145541";
      sha256 = "0hraic67rap7idm1gqk9f5nn21vzky43g4ppx3izv1njc25pcwdf";
    };
  };

  org-bullets = buildVimPluginFrom2Nix {
    pname = "org-bullets";
    version = "main";
    src = fetchFromGitHub {
      owner = "akinsho";
      repo = "org-bullets.nvim";
      rev = "3623e86e0fa6d07f45042f7207fc333c014bf167";
      sha256 = "0il7x6bp21vxnijl96gjq2kry33jin8dqxs9yvp3r60lv3aix0b8";
    };
  };

  headlines-nvim = buildVimPluginFrom2Nix {
    pname = "headlines";
    version = "v3.3.0";
    src = fetchFromGitHub {
      owner = "lukas-reineke";
      repo = "headlines.nvim";
      rev = "618ef1b2502c565c82254ef7d5b04402194d9ce3";
      sha256 = "02zri3vmzjxv47qnlll3nf71i9ji8nhdabpvf4566i7iwwagqpym";
    };
  };

  nvim-macroni = buildVimPluginFrom2Nix {
    pname = "macroni";
    version = "master";
    src = fetchFromGitHub {
      owner = "jesseleite";
      repo = "nvim-macroni";
      rev = "0aec66f439b96f511935a9dcf2e37fca137972d2";
      sha256 = "1q5v0734ry3z2vqy2wpvnm84s0bk28vm6yxcfpla7iaxp5lwwl7l";
    };
  };

}
