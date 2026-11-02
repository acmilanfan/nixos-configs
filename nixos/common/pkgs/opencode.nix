{ lib, symlinkJoin, writeShellScriptBin, stdenv, pkgs, inputs }:
let
  # Darwin uses a source build with the reconnect-retry fix (upstream PR
  # #59543): a transient session read after an event stream reconnect would
  # otherwise drop the TUI back to the home screen. Linux keeps the pinned
  # prebuilt binary until the fix is released.
  cli =
    if stdenv.hostPlatform.isDarwin then pkgs.opencode2-patched
    else inputs.llm-agents.packages.${stdenv.hostPlatform.system}.opencode2;
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
