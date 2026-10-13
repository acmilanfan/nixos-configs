{ lib, symlinkJoin, writeShellScriptBin, stdenv, inputs }:
let
  cli = inputs.llm-agents.packages.${stdenv.hostPlatform.system}.opencode2;
  launcher = writeShellScriptBin "opencode" ''
    # The shared service needs the same runtime-decrypted provider/MCP env as
    # interactive clients. Nothing secret is included in the store.
    if [ -f "$HOME/.config/sops-nix/secrets/rendered/ai-env.sh" ]; then
      . "$HOME/.config/sops-nix/secrets/rendered/ai-env.sh"
    fi
    exec ${cli}/bin/opencode2 "$@"
  '';
in
symlinkJoin {
  name = "opencode-${cli.version}";
  inherit (cli) version;
  paths = [ launcher cli ];
  meta = cli.meta // { mainProgram = "opencode"; };
}
