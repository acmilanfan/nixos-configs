{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
  nodejs_24,
  nix-update-script,
}:

buildNpmPackage (finalAttrs: {
  pname = "opencode-telegram-bot";
  version = "0.25.1";

  src = fetchFromGitHub {
    owner = "grinev";
    repo = "opencode-telegram-bot";
    tag = "v${finalAttrs.version}";
    hash = "sha256-+0FJ+GrodlFABxOs6WUnWFidDgiCaMuGC0mi5eZG/5g=";
  };

  nodejs = nodejs_24;

  npmDepsHash = "sha256-Ai1hgKivY3S9BLDCF5EdmtlI3JpCh7V70C/hE0VTjwM=";

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Telegram client for OpenCode: run and monitor coding tasks from chat";
    homepage = "https://github.com/grinev/opencode-telegram-bot";
    license = lib.licenses.mit;
    mainProgram = "opencode-telegram";
    platforms = lib.platforms.unix;
  };
})

