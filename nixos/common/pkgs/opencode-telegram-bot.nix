{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
  nodejs_24,
  nix-update-script,
}:

buildNpmPackage (finalAttrs: {
  pname = "opencode-telegram-bot";
  version = "0.26.3";

  src = fetchFromGitHub {
    owner = "grinev";
    repo = "opencode-telegram-bot";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kgD1TXOqDPalocW7HNiZz31bbUMiyJ6xu0cPYBVzjhs=";
  };

  nodejs = nodejs_24;

  npmDepsHash = "sha256-1PeS2g4rU/E2+ITWYO3troB1v3FlnHFWrIWlZWImjHg=";

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Telegram client for OpenCode: run and monitor coding tasks from chat";
    homepage = "https://github.com/grinev/opencode-telegram-bot";
    license = lib.licenses.mit;
    mainProgram = "opencode-telegram";
    platforms = lib.platforms.unix;
  };
})
