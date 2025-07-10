{ lib, buildVimPluginFrom2Nix, fetchFromGitHub, fetchgit }:

{
  telescope-orgmode = buildVimPluginFrom2Nix {
    pname = "telescope-orgmode";
    version = "main";
    src = fetchFromGitHub {
      owner = "nvim-orgmode";
      repo = "telescope-orgmode.nvim";
      rev = "a73d9b7d841364bc2a2e90e97f1d056c02b1a2f9";
      sha256 = "0wg59i6rkv7bh9icqbzwpwcxzb5bg46all2n7z92yw9apys6fxmv";
    };
  };

  org-bullets = buildVimPluginFrom2Nix {
    pname = "org-bullets";
    version = "main";
    src = fetchFromGitHub {
      owner = "nvim-orgmode";
      repo = "org-bullets.nvim";
      rev = "21437cfa99c70f2c18977bffd423f912a7b832ea";
      sha256 = "0zfic6isqvbycn4zq1jsrr6g4yksmvgxzavknzlswg2jymz0hpzy";
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
    pname = "lsplinks";
    version = "master";
    src = fetchFromGitHub {
      owner = "icholy";
      repo = "lsplinks.nvim";
      rev = "088c91e7aa0eaa24508db77ccf827440ca72760f";
      sha256 = "0inkgzbhgsd8rbca2smhm3znrqwlj0lvrh4k4kqb77v91p9zffjc";
    };
  };

  nvim-java = buildVimPluginFrom2Nix {
    pname = "nvim-java";
    version = "main";
    src = fetchFromGitHub {
      owner = "nvim-java";
      repo = "nvim-java";
      rev = "d25bc1c55b4cea53f6174b2e2171ed8519113bc5";
      sha256 = "1gcla9qqk973r3z1qif7w9yyb0l4r0r8y9gs7f9jcjzwadx7v7zc";
    };
  };

  spring-boot-nvim = buildVimPluginFrom2Nix {
    pname = "spring-boot-nvim";
    version = "main";
    src = fetchFromGitHub {
      owner = "JavaHello";
      repo = "spring-boot.nvim";
      rev = "329c715fee597d40030586297d06d69ed072cc32";
      sha256 = "18fd8c7awjafbx26fj7gaz1vs81xiaisrdlrnx4v39bknr7q043w";
    };
  };

  lua-async-await = buildVimPluginFrom2Nix {
    pname = "lua-async-await";
    version = "main";
    src = fetchFromGitHub {
      owner = "nvim-java";
      repo = "lua-async";
      rev = "652d94df34e97abe2d4a689edbc4270e7ead1a98";
      sha256 = "0jpw9008xghqmzjnikwq417p497lj7v9hkjbrach5p652yca07s8";
    };
  };

  nvim-java-refactor = buildVimPluginFrom2Nix {
    pname = "nvim-java-refactor";
    version = "main";
    src = fetchFromGitHub {
      owner = "nvim-java";
      repo = "nvim-java-refactor";
      rev = "b51a57d862338999059e1d1717df3bc80a3a15c0";
      sha256 = "14akgf8z74c4crkmggmrlckn4av0a701kr0whvn5pq6phc718dns";
    };
  };

  nvim-java-core = buildVimPluginFrom2Nix {
    pname = "nvim-java-core";
    version = "main";
    src = fetchFromGitHub {
      owner = "nvim-java";
      repo = "nvim-java-core";
      rev = "401bf7683012a25929a359deec418f36beb876e2";
      sha256 = "0s6wqz9z8r0hvvgf5dnl8drgzb49vrk798rc7gk2cbm85blzk7p8";
    };
  };

  nvim-java-test = buildVimPluginFrom2Nix {
    pname = "nvim-java-test";
    version = "main";
    src = fetchFromGitHub {
      owner = "nvim-java";
      repo = "nvim-java-test";
      rev = "7f0f40e9c5b7eab5096d8bec6ac04251c6e81468";
      sha256 = "18jvkiy568i18r0cq0pyxjsispsvbbv40niyj98dlc04dzx618ba";
    };
  };

  nvim-java-dap = buildVimPluginFrom2Nix {
    pname = "nvim-java-dap";
    version = "main";
    src = fetchFromGitHub {
      owner = "nvim-java";
      repo = "nvim-java-dap";
      rev = "55f239532f7a3789d21ea68d1e795abc77484974";
      sha256 = "01fscbw226djimzscpa7n20gfzyhw952ar4dymyw18svp5vg5g2y";
    };
  };

}
