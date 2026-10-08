# Machine-local options for the agent configs in ./ai-agents.nix.
#
# Lives in its own file because declaring `options` at the top level of a
# home-manager module forces every config attribute there into an explicit
# `config = { ... }` block (new module syntax) — which would re-indent all of
# ai-agents.nix for a single option. Keep this file options-only.
{ lib, ... }:

{
  options.ai-agents.extraTrustedWorkspaces = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "/Users/gentooway/Projects/some-project" ];
    description = ''
      Extra directories appended to Antigravity's trustedWorkspaces beyond
      the shared nixos-configs repo entry. Set per host (e.g.
      nixos/mac-home/home.nix) so machine-local project paths never land in
      the shared common module.
    '';
  };

  options.ai-agents.antigravity.remoteControl = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Auto-start `agy remote-control` (on activation, from the agy/antigravity
      wrappers and the PreInvocation hook), registered under this host's
      short hostname. Opt-in per host so the work laptop isn't remotely
      drivable by default.
    '';
  };
}
