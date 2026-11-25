{ lib, symlinkJoin, writeShellScriptBin, stdenv, pkgs, inputs }:
let
  # Darwin uses a source build with the reconnect-retry fix (upstream PR
  # #59543): a transient session read after an event stream reconnect would
  # otherwise drop the TUI back to the home screen. Linux keeps the pinned
  # prebuilt binary until the fix is released. The source build is pinned by
  # hand, so warn when `up` moves llm-agents past it: the Macs would otherwise
  # silently stay on the old version while Linux moves on.
  upstream = inputs.llm-agents.packages.${stdenv.hostPlatform.system}.opencode2;
  patched = pkgs.opencode2-patched;
  cli =
    if stdenv.hostPlatform.isDarwin then
      lib.warnIf (lib.versionOlder patched.version upstream.version)
        "opencode2-patched ${patched.version} is behind llm-agents' opencode2 ${upstream.version}: bump nixos/common/pkgs/opencode2-patched, or drop it once upstream PR #59543 is released"
        patched
    else upstream;
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
