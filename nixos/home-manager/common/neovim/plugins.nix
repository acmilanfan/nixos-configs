{ lib, buildVimPluginFrom2Nix, fetchFromGitHub, fetchgit }:

{
  telescope-orgmode = buildVimPluginFrom2Nix {
    pname = "telescope-orgmode";
    version = "main";
    src = fetchFromGitHub {
      owner = "seflue";
      repo = "telescope-orgmode.nvim";
      rev = "6e2a0876f27d0e991f325d0c443e2f1fe1765216";
      sha256 = "0z6cflpbj79fppfyl60n008149qpwiqbk6aidy4xarm07w37aywx";
    };
  };

  org-bullets = buildVimPluginFrom2Nix {
    pname = "org-bullets";
    version = "main";
    src = fetchFromGitHub {
      owner = "akinsho";
      repo = "org-bullets.nvim";
      rev = "6e0d60e901bb939eb526139cb1f8d59065132fd9";
      sha256 = "0z5nijd8lm0hb9rsjhcg0c9qg56yy8ha3ls1333vwlhzv1cvi967";
    };
  };

  headlines-nvim = buildVimPluginFrom2Nix {
    pname = "headlines";
    version = "v3.3.0";
    src = fetchFromGitHub {
      owner = "lukas-reineke";
      repo = "headlines.nvim";
      rev = "ddef41b2664f0ce25fe76520d708e2dc9dfebd70";
      sha256 = "02zri3vmzjxv47qnlll3nf71i9ji8nhdabpvf4566i7iwwagqpym";
    };
  };

}
