{ pkgs ? import <nixpkgs> {} }:

let fhs = pkgs.buildFHSUserEnv {
  name = "fhs-env";
  targetPkgs = pkgs: (with pkgs;
    [
      python3
      python3.pkgs.requests
    ]);
  runScript = "bash";
};

in pkgs.stdenv.mkDerivation {
  name = "fhs-python";
  nativeBuildInputs = [ fhs pkgs.python3 pkgs.python3.pkgs.requests ];
  shellHook = ''
    export PIP_PREFIX=$(pwd)/_build/pip_packages
    export PYTHONPATH="$PIP_PREFIX/${pkgs.python3.sitePackages}:$PYTHONPATH"
    export PATH="$PIP_PREFIX/bin:$PATH"
    unset SOURCE_DATE_EPOCH
  '';
}
