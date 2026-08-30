{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "tg2kobo";
  version = "0.1.0";

  src = ../../../apps/tg2kobo;

  vendorHash = "sha256-hzZcL4dZUOfCx8amgWFL9zKZvqegPyoKFE3dqjoyG30=";

  meta = {
    description = "Export selected Telegram messages to EPUB and copy them to a Kobo reader";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
