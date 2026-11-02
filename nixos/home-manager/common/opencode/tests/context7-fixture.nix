# Evaluate the real modules against fabricated secrets; never decrypt anything.
{ secretsFile }:
let
  root = ../../../../..;
  inputs = (builtins.getFlake (toString root)).inputs;
  lib = inputs.nixpkgs.lib // {
    hm.dag = import (inputs.home-manager + "/modules/lib/dag.nix") { inherit lib; };
  };
  pkgs = import inputs.nixpkgs {
    system = builtins.currentSystem;
    overlays = [
      (import (root + "/nixos/common/overlays.nix") { inherit inputs; })
      inputs.mcp-nixos.overlays.default
    ];
  };
  config = {
    home = { username = "gentooway"; homeDirectory = "/fixture"; };
    customSops = { enable = true; secretsFile = /. + secretsFile; };
    ai-agents = { extraTrustedWorkspaces = [ ]; antigravity.remoteControl = false; };
    sops = {
      placeholder = lib.mapAttrs (name: _: "fixture-" + builtins.replaceStrings [ "/" ] [ "-" ] name)
        sopsModule.config.content.sops.secrets;
      secrets = {
        "github/token".path = "@GITHUB_TOKEN_FILE@";
        "github/personal_token".path = "@GITHUB_PERSONAL_TOKEN_FILE@";
        "context7/apiKey".path = "@CONTEXT7_KEY_FILE@";
      };
      templates."mcp-credentials-generation" = {
        path = "@MCP_GENERATION_FILE@";
        content = generation.content or "fixture-current-generation";
      };
    };
  };
  args = { inherit config inputs lib pkgs; secrets = { }; unstable = pkgs; };
  sopsModule = import (root + "/nixos/home-manager/common/sops.nix") {
    inherit config inputs lib pkgs;
    secrets = { };
  };
  generation = sopsModule.config.content.sops.templates."mcp-credentials-generation" or { };
  opencode = import (root + "/nixos/home-manager/common/opencode.nix") args;
  agents = import (root + "/nixos/home-manager/common/ai-agents.nix") (builtins.removeAttrs args [ "unstable" ]);
in {
  hasSecret = builtins.hasAttr "context7/apiKey" sopsModule.config.content.sops.secrets;
  envTemplate = sopsModule.config.content.sops.templates."ai-env.sh";
  generationTemplate = generation;
  opencodeActivation = opencode.home.activation.opencodeSettings.data;
  antigravityActivation = agents.home.activation.installGeminiExtensions.data;
}
