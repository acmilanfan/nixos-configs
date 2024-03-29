{ buildGoModule, fetchFromGitHub, lib, pkgs }:

buildGoModule rec {
  pname = "obs-cli";
  version = "v0.5.0";

  src = fetchFromGitHub {
    owner = "muesli";
    repo = "obs-cli";
    rev = version;
    sha256 = "19wv493m9hckgrq51imavgg3x5s3jm71h26frvsg8gxjypwd5n72";
  };

  vendorSha256 = "03r2asykqllds1kwrddwcfbvb8q494l7x0w6pxcskkbvgyln8sj4";

  meta = with lib; {
    description =
      "OBS-cli is a command-line remote control for OBS";
    homepage = "https://github.com/muesli/obs-cli";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = with maintainers; [ acmilanfan ];
  };
}
