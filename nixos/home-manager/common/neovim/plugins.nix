{ lib, buildVimPluginFrom2Nix, fetchFromGitHub, fetchgit }:

{
  telescope-orgmode = buildVimPluginFrom2Nix {
    pname = "telescope-orgmode";
    version = "main";
    src = fetchFromGitHub {
      owner = "joaomsa";
      repo = "telescope-orgmode.nvim";
      rev = "eabff061c3852a9aa94e672a7d2fa4a1ef63f9e2";
      sha256 = "02mr0khz6in0hhqbdx4dy83hn47hjh5x43hq830fmjjvy2yviigy";
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
