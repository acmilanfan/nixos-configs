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
      rev = "d5a91e06d0a6bb0dd865cb3d0d69555e63a32de3";
      sha256 = "077fiyc0db45h7lin2maigzyv5ixzdxfa61r9v5pxvhsqap0b3lh";
    };
  };

  headlines-nvim = buildVimPluginFrom2Nix {
    pname = "headlines";
    version = "v3.3.0";
    src = fetchFromGitHub {
      owner = "lukas-reineke";
      repo = "headlines.nvim";
      rev = "6496b6229ce708253a906daed07067c1d32a427b";
      sha256 = "0565b3h1i7zfdzkzymsqrxvqizgpyigrngx30wj0w48zzrzd6n8k";
    };
  };

}
