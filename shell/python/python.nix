{
  pkgs ? import <nixpkgs> { },
}:

# direnv-friendly default shell. The FHS variant (whose shellHook exec's
# fhs-env) lives in python-fhs.nix and is available as `nix develop .#fhs`.
pkgs.mkShell {
  name = "python-shell";
  buildInputs = with pkgs; [
    python3
    python3.pkgs.requests
    xdotool
  ];
  shellHook = ''
    export PIP_PREFIX=$(pwd)/_build/pip_packages
    export PYTHONPATH="$PIP_PREFIX/${pkgs.python3.sitePackages}:$PYTHONPATH"
    export PATH="$PIP_PREFIX/bin:$PATH"
    unset SOURCE_DATE_EPOCH
  '';
}
