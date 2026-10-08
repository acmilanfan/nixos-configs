{ pkgs, lib, src, python3Packages }:

python3Packages.buildPythonApplication rec {
  pname = "blueutil-tui";
  version = "latest";
  pyproject = true;

  # flake input `blueutil-tui` (pinned in flake.lock, bump with `pins update`)
  inherit src;

  nativeBuildInputs = with python3Packages; [
    setuptools
    hatchling
  ];

  propagatedBuildInputs = with python3Packages; [
    textual
  ];

  doCheck = false;

  meta = with lib; {
    description = "A Textual TUI for blueutil on macOS";
    homepage = "https://github.com/zaloog/blueutil-tui";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
