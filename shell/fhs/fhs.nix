{ pkgs ? import <nixpkgs> {} }:

let fhs = pkgs.buildFHSUserEnv {
  name = "fhs-env";
  targetPkgs = pkgs: (with pkgs;
    [
      
    ]);
  runScript = "zsh";
};
in pkgs.stdenv.mkDerivation {
  name = "fhs-generic";
  nativeBuildInputs = [ fhs ];
  shellHook = ''
    exec fhs-env
  '';
}
