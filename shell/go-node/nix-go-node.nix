{ pkgs ? import <nixpkgs> {} }:

let fhs = pkgs.buildFHSUserEnv {
  name = "dev-env";
  targetPkgs = pkgs: (with pkgs;
    [
      go nodejs yarn
    ]);
  runScript = "bash";
};
in pkgs.stdenv.mkDerivation {
  name = "maven-shell";
  nativeBuildInputs = [ fhs ];
  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin
    # npm set prefix ~/.npm-global
    exec dev-env
  '';
}
