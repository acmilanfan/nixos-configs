# Work MCP servers (Agent1, Jenkins, Kibana), shared by Claude Code
# (ai-agents.nix), opencode (opencode.nix) and their credentials (sops.nix).
# Not a module: import it with `import ./work-mcp.nix { ... }`.
#
# This repo is public, so endpoints and usernames come from the private
# `secrets.work.mcp` block (each service is generated only when its block
# exists; Kibana whenever the work marketplace is set) and credentials from sops, exported by ai-env.sh. Configs reference
# the credentials as env vars (${VAR} in Claude Code, {env:VAR} in opencode),
# so no credential lands in /nix/store or a generated config file.
{ lib, pkgs, secrets }:
let
  cfg = secrets.work.mcp or { };
  jenkins = cfg.jenkins or { };
  marketplace = secrets.claude.workMarketplaceName or "";

  # legacy-qa-jenkins -> JENKINS_LEGACY_QA_JENKINS_TOKEN
  jenkinsTokenEnv = name: "JENKINS_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name)}_TOKEN";

  # Client-neutral specs; `ref` renders an env-var reference for one client.
  # Remote: { url; bearer; }. Local: { command; env ? { }; }.
  specs = ref:
    lib.optionalAttrs (cfg ? agent1) {
      agent1-mcp = { url = cfg.agent1.prod; bearer = ref "AGENT1_API_KEY"; };
      agent1-mcp-qa = { url = cfg.agent1.qa; bearer = ref "AGENT1_QA_API_KEY"; };
    }
    # Server names are kept as they were: coding-java/cfe skills call
    # mcp__legacy-qa-jenkins__* etc. by name. A server is a URL, or
    # { url; readOnly ? false; username ? jenkins.username; }.
    // lib.mapAttrs (name: server:
      let s = if builtins.isString server then { url = server; } else server; in {
        command = [
          "${pkgs.uv}/bin/uvx"
          "mcp-jenkins@3.4.0"
          "--jenkins-url=${s.url}"
          "--jenkins-username=${s.username or jenkins.username}"
          "--jenkins-password=${ref (jenkinsTokenEnv name)}"
        ] ++ lib.optional (s.readOnly or false) "--read-only";
      }) (jenkins.servers or { });

  # Claude Code gets Kibana from the marketplace's kibana plugin. opencode uses
  # its own clone of the same plugin (opencodeWorkAssets in opencode.nix) for
  # the bridge, skills and fan-out workers, as the plugin's install-opencode.sh
  # would. Each server runs with the env the plugin's .mcp.json gives it, so
  # Kibana URLs and spaces stay the plugin's business. ELASTIC_API_KEY (a
  # Claude Code ${VAR} there) is left out: the bridge then reads the variable
  # ELASTIC_KEY_NAME names, or ~/.config/auto1-kibana/keys.json.
  kibanaEnabled = marketplace != "";
  kibanaPluginDir = "$HOME/.cache/opencode-kibana-plugin";
  kibanaMcp = pkgs.writeShellScript "kibana-mcp" ''
    dir="${kibanaPluginDir}"
    envs=$(${pkgs.jq}/bin/jq -r --arg s "$1" '
      .mcpServers[$s].env // error("no server \($s) in .mcp.json")
      | to_entries[] | select(.key != "ELASTIC_API_KEY") | @sh "export \(.key)=\(.value)"
    ' "$dir/.mcp.json") || { echo "kibana-mcp: cannot read $1 from $dir/.mcp.json" >&2; exit 1; }
    eval "$envs"
    exec ${pkgs.nodejs_22}/bin/node "$dir/mcp-server/dist/server.js"
  '';
  kibanaSpecs = lib.optionalAttrs kibanaEnabled {
    kibana-qa.command = [ "${kibanaMcp}" "kibana-qa" ];
    kibana-prod.command = [ "${kibanaMcp}" "kibana-prod" ];
  };
in
{
  inherit kibanaEnabled kibanaPluginDir;
  # Fan-out workers whose tools live on kibana-qa/kibana-prod; the metrics and
  # security workers need servers (and keys) that aren't configured.
  kibanaWorkers = [ "app-health" "edge-health" "perf-health" "platform-health" ];

  # Credentials to decrypt and export from ai-env.sh: sops key -> env var.
  credentials =
    lib.optionalAttrs (cfg ? agent1) {
      "agent1/prodApiKey" = "AGENT1_API_KEY";
      "agent1/qaApiKey" = "AGENT1_QA_API_KEY";
    }
    // lib.optionalAttrs kibanaEnabled {
      "elastic/qaApiKey" = "ELASTIC_API_KEY_QA";
      "elastic/prodApiKey" = "ELASTIC_API_KEY_PROD";
    }
    // lib.mapAttrs' (name: _: lib.nameValuePair "jenkins/${name}" (jenkinsTokenEnv name)) (jenkins.servers or { });

  # Shape `claude mcp add-json` stores in ~/.claude.json, so an unchanged
  # entry compares equal and isn't rewritten on every switch.
  claude = lib.mapAttrs (_: s:
    if s ? url then {
      type = "http";
      inherit (s) url;
      headers.Authorization = "Bearer ${s.bearer}";
    } else {
      type = "stdio";
      command = lib.head s.command;
      args = lib.tail s.command;
      env = s.env or { };
    }) (specs (name: "\${${name}}"));

  opencode = lib.mapAttrs (_: s:
    if s ? url then {
      type = "remote";
      inherit (s) url;
      # API-key endpoint: skip opencode's OAuth discovery.
      oauth = false;
      headers.Authorization = "Bearer ${s.bearer}";
    } else {
      type = "local";
      inherit (s) command;
      environment = s.env or { };
    }) (specs (name: "{env:${name}}") // kibanaSpecs);
}
