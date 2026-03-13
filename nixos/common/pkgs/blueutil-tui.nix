{ pkgs, lib, fetchFromGitHub, python3Packages }:

python3Packages.buildPythonApplication rec {
  pname = "blueutil-tui";
  version = "latest";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "zaloog";
    repo = "blueutil-tui";
    rev = "main";
    hash = "sha256-CPa3TU3CV9WA5umnLzrFUa6nySnainmv1ymxAGAZazY=";
  };

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
