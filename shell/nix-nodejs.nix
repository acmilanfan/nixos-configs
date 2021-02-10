let pkgs = import <nixpkgs> {};

    buildNodejs = pkgs.callPackage <nixpkgs/pkgs/development/web/nodejs/nodejs.nix> {};
    
    nodejs = buildNodejs {
      enableNpm = true;
      version = "10.15.2";
      sha256 = "0ncc27azpfrhc55n4j35wqcxbf7n42j0j07pq9dqjvh1rfkjvfxq";
    };

in pkgs.mkShell rec {
  name = "webdev";
  
  buildInputs = with pkgs; [
    nodejs
  ];
}
