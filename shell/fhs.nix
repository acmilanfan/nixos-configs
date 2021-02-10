{ pkgs ? import <nixpkgs> {} }:

let fhs = pkgs.buildFHSUserEnv {
  name = "fhs-env";
  targetPkgs = pkgs: (with pkgs;
    [
      
    ]);
  runScript = "bash";
};
in pkgs.stdenv.mkDerivation {
  name = "fhs-template";
  nativeBuildInputs = [ fhs ];
}
