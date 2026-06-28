{ pkgs ? import <nixpkgs> { } }:

let
  fhs = pkgs.buildFHSEnv {
    name = "fhs-env";
    targetPkgs = pkgs:
      (with pkgs; [
        python3
        python3.pkgs.requests
        # python3.pkgs.pyqt5  # removed from nixpkgs
        # python3.pkgs.xlib   # removed from nixpkgs
        # qt5.full            # removed from nixpkgs
        xdotool
      ]);
    runScript = "zsh";
  };

in pkgs.stdenv.mkDerivation {
  name = "fhs-python";
  nativeBuildInputs = [
    fhs
    pkgs.python3.pkgs.requests
    # pkgs.python3.pkgs.pyqt5  # removed from nixpkgs
    # pkgs.python3.pkgs.xlib   # removed from nixpkgs
    # pkgs.python3.pkgs.evdev  # removed from nixpkgs
  ];
  shellHook = ''
    export PIP_PREFIX=$(pwd)/_build/pip_packages
    export PYTHONPATH="$PIP_PREFIX/${pkgs.python3.sitePackages}:$PYTHONPATH"
    export PATH="$PIP_PREFIX/bin:$PATH"
    unset SOURCE_DATE_EPOCH
    exec fhs-env
  '';
}
