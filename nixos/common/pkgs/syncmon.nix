{ lib, buildGoModule }:

buildGoModule {
  pname = "syncmon";
  version = "0.1.0";

  src = ../../../apps/syncmon;

  vendorHash = "sha256-ZxjKNUQeUzTqL+xHIZh58o7YXxFy6vaFq9Sp3Bg/FCY=";

  meta = with lib; {
    description = "Sync and system status dashboard";
    homepage = "https://github.com/acmilanfan/nixos-configs";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.darwin;
  };
}
