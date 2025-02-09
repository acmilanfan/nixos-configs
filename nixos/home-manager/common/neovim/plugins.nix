{ lib, buildVimPluginFrom2Nix, fetchFromGitHub, fetchgit }:

{
  telescope-orgmode = buildVimPluginFrom2Nix {
    pname = "telescope-orgmode";
    version = "main";
    src = fetchFromGitHub {
      owner = "nvim-orgmode";
      repo = "telescope-orgmode.nvim";
      rev = "2cd2ea778726c6e44429fef82f23b63197dbce1b";
      sha256 = "16qj9adc9ggzrbsf9c25g3wnhk7sm3j35glz5bcq99x2av5rvqf9";
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

  # headlines-nvim = buildVimPluginFrom2Nix {
  #   pname = "headlines";
  #   version = "v3.3.0";
  #   src = fetchFromGitHub {
  #     owner = "lukas-reineke";
  #     repo = "headlines.nvim";
  #     rev = "618ef1b2502c565c82254ef7d5b04402194d9ce3";
  #     sha256 = "02zri3vmzjxv47qnlll3nf71i9ji8nhdabpvf4566i7iwwagqpym";
  #   };
  # };

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

  lsplinks-nvim = buildVimPluginFrom2Nix {
    pname = "macroni";
    version = "master";
    src = fetchFromGitHub {
      owner = "icholy";
      repo = "lsplinks.nvim";
      rev = "088c91e7aa0eaa24508db77ccf827440ca72760f";
      sha256 = "0inkgzbhgsd8rbca2smhm3znrqwlj0lvrh4k4kqb77v91p9zffjc";
    };
  };

}
