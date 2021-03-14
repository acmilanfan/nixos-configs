{ pkgs ? import <nixpkgs> { config = { allowUnfree = true; }; } }:

let fhs = pkgs.buildFHSUserEnv {
  name = "music-production-env";
  targetPkgs = pkgs: (with pkgs;
    [ 
      bitwig-studio3
    ]);
  runScript = "bash";
};
in pkgs.stdenv.mkDerivation {
  name = "music-production";
  nativeBuildInputs = [ fhs ];
  buildInputs = with pkgs; [ libjack2 xorg.libX11 ];
  #LD_LIBRARY_PATH = "${stdenv.lib.makeLibraryPath buildInputs}:${LD_LIBRARY_PATH}";
  shellHook = ''
    export LANG=en_US.UTF-8 
    export LD_LIBRARY_PATH=~/.nix-profile/lib:$LD_LIBRARY_PATH
    unset TZ
    exec music-production-env
  '';
}
