// Requires nix-instantiate (run with the flake's locked nixpkgs environment).
// Validate generated routing descriptions against the documented low/max/max
// defaults. Inline lead prompt cues and live model behavior are not covered here.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

const modulePath = fileURLToPath(new URL("../../opencode.nix", import.meta.url));

for (const username of ["gentooway", "andreishumailov"]) {
  test(`${username}: hybrid routing descriptions and models retain documented defaults`, () => {
    const activation = JSON.parse(execFileSync("nix-instantiate", ["--eval", "--strict", "--json", "--expr", `
      let m = import ${modulePath} {
        config.home.username = "${username}";
        config.home.homeDirectory = "/Users/${username}";
        secrets = {}; unstable = {}; inputs = {};
        pkgs = {
          mcp-nixos = "/fixture/mcp-nixos"; jq = "/fixture/jq";
          opencode-agent-memory = "/fixture/memory";
          stdenv.isDarwin = true;
          runCommand = name: env: script: "/fixture/" + name;
        };
        lib.hm.dag.entryAfter = _: value: value;
      }; in m.home.activation.opencodeSettings
    `], { encoding: "utf8", timeout: 30000 }));
    const { agents } = JSON.parse(activation.split("cat <<'EOF'\n")[1].split("\nEOF")[0]);
    for (const [id, expectedEffort] of [
      ["hybrid-explore", "low"], ["hybrid-review", "max"], ["hybrid-worker", "max"],
    ]) {
      const profile = agents[id];
      assert.ok(profile, `${id} is registered`);
      assert.equal(profile.model, `opencode-go/deepseek-v4.1-flash#${expectedEffort}`,
        `${id} retains its documented model and effort`);
      const advertisedEffort = profile.description.match(/^Flash (low|high|max):/)?.[1];
      assert.equal(advertisedEffort, expectedEffort, `${id} advertises its documented effort`);
    }
  });
}
