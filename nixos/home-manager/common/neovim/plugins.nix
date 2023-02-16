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
      rev = "f71ac901fca4b52c9aebe6f0f5899d9f38162d46";
      sha256 = "0d2mgy8jpykp7krbqq4mbwa44nx3p4c2pn7aqflnlzp00q1k1rdx";
    };
  };

  headlines-nvim = buildVimPluginFrom2Nix {
    pname = "headlines";
    version = "v3.3.0";
    src = fetchFromGitHub {
      owner = "lukas-reineke";
      repo = "headlines.nvim";
      rev = "1cd93a641c03419bb255f8b3fe734451517763b1";
      sha256 = "1035jmy21in2vc56pcyvprwa0c1wg277vdad3cgx55aqsj3labqb";
    };
  };

}
