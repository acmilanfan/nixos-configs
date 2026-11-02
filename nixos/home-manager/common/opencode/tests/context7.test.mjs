import assert from "node:assert/strict";
import { before, test } from "node:test";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, stat, symlink, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const execute = promisify(execFile);
const artifacts = join(homedir(), "ai/artifacts/nixos-configs/context7-tests");
const ciphertext = "context7:\n  apiKey: ENC[fixture]\n";
const generation = createHash("sha256").update(ciphertext).digest("hex");
const runHelper = 'run() { if [[ -v DRY_RUN ]]; then echo "$@"; else "$@"; fi; };\n';
let data;

before(async () => {
  await mkdir(artifacts, { recursive: true });
  const root = await mkdtemp(join(artifacts, "evaluation-"));
  const secrets = join(root, "secrets.yaml");
  await writeFile(secrets, ciphertext);
  const result = await execute("nix", ["eval", "--impure", "--json", "--file",
    fileURLToPath(new URL("./context7-fixture.nix", import.meta.url)), "--apply", `f: f { secretsFile = ${JSON.stringify(secrets)}; }`],
    { timeout: 120000 });
  data = JSON.parse(result.stdout);
});

async function fixture() {
  const home = await mkdtemp(join(artifacts, "activation-"));
  for (const [directory, marker, key] of [
    ["previous", "previous-generation", "previous-context7-secret"],
    ["next", generation, "current-context7-secret"],
  ]) {
    for (const child of ["rendered", "github", "context7"]) await mkdir(join(home, directory, child), { recursive: true });
    await writeFile(join(home, directory, "rendered/mcp-credentials-generation"), marker);
    await writeFile(join(home, directory, "github/token"), "fixture-github-token\n");
    await writeFile(join(home, directory, "github/personal_token"), "fixture-github-personal-token\n");
    await writeFile(join(home, directory, "context7/apiKey"), `${key}\n`);
  }
  await symlink(join(home, "previous"), join(home, "secrets"));
  const settings = join(home, ".gemini/antigravity-cli/settings.json");
  // Exercise the real settings activation without installing unrelated plugins.
  const activation = data.antigravityActivation.split("# 2. Antigravity Global Hooks Setup")[0]
    .replaceAll("@GITHUB_TOKEN_FILE@", join(home, "secrets/github/token"))
    .replaceAll("@GITHUB_PERSONAL_TOKEN_FILE@", join(home, "secrets/github/personal_token"))
    .replaceAll("@CONTEXT7_KEY_FILE@", join(home, "secrets/context7/apiKey"))
    .replaceAll("@MCP_GENERATION_FILE@", join(home, "secrets/rendered/mcp-credentials-generation"));
  const activate = (prelude = "", environment = {}) => execute("bash", ["-euc", runHelper + prelude + activation], {
    env: { ...process.env, HOME: home, ...environment }, timeout: 10000,
  });
  return { home, settings, activate };
}

test("Context7 uses a runtime secret and a marker tied to the encrypted source", async () => {
  assert.equal(data.hasSecret, true);
  assert.equal(data.envTemplate.mode, "0600");
  assert.equal(data.generationTemplate.content, generation);
  const env = await execute("bash", ["-euc", data.envTemplate.content + '\nprintf "%s" "$CONTEXT7_API_KEY"']);
  assert.equal(env.stdout, "fixture-context7-apiKey");
  const { home } = await fixture();
  const context7Key = join(home, "secrets/context7/apiKey");
  const opencodeActivation = data.opencodeActivation
    .replaceAll("@GITHUB_TOKEN_FILE@", join(home, "secrets/github/token"))
    .replaceAll("@GITHUB_PERSONAL_TOKEN_FILE@", join(home, "secrets/github/personal_token"))
    .replaceAll("@CONTEXT7_KEY_FILE@", context7Key);
  await execute("bash", ["-euc", runHelper + opencodeActivation], { env: { ...process.env, HOME: home } });
  const oc = JSON.parse(await readFile(join(home, ".config/opencode/opencode.json"), "utf8"));
  const context7 = (oc.mcp.servers ?? oc.mcp).context7;
  assert.deepEqual(context7.headers, { Authorization: `Bearer {file:${context7Key}}` });
  assert.equal(context7.oauth, false);
});

test("Antigravity does not copy the previous key while SOPS has not published its generation", async () => {
  const { home, settings, activate } = await fixture();
  assert.equal(await readFile(join(home, "secrets/context7/apiKey"), "utf8"), "previous-context7-secret\n");
  // Deterministic delayed producer: publish only once activation has to wait.
  // Both secret files already exist, exactly as on a macOS key rotation.
  const publish = `sleep() { ln -sfn ${JSON.stringify(join(home, "next"))} ${JSON.stringify(join(home, "secrets"))}; };\n`;
  const result = await activate(publish);
  const live = JSON.parse(await readFile(settings, "utf8"));
  assert.equal(live.mcpServers.context7.headers.Authorization, "Bearer current-context7-secret");
  assert.equal((await stat(settings)).mode & 0o777, 0o600);
  assert.doesNotMatch(result.stdout + result.stderr, /previous-context7-secret|current-context7-secret/);
});

for (const missing of [false, true]) {
  test(`Antigravity preserves existing settings when the current SOPS marker is ${missing ? "missing" : "stale"}`, async () => {
    const { home, settings, activate } = await fixture();
    if (missing) {
      // Use a fresh generation with no marker, without deleting any fixture data.
      await mkdir(join(home, "unready"));
      await execute("ln", ["-sfn", join(home, "unready"), join(home, "secrets")]);
    }
    await mkdir(join(home, ".gemini/antigravity-cli"), { recursive: true });
    const original = '{"notifications":false}\n';
    await writeFile(settings, original, { mode: 0o600 });
    await assert.rejects(activate("sleep() { :; };\n"), (error) => {
      assert.match(error.stderr, /SOPS.*current.*generation/i);
      assert.doesNotMatch(error.stdout + error.stderr, /previous-context7-secret|current-context7-secret/);
      return true;
    });
    assert.equal(await readFile(settings, "utf8"), original);
  });
}

test("Antigravity dry runs do not wait for SOPS or change settings", async () => {
  const { settings, activate } = await fixture();
  const result = await activate("sleep() { return 88; };\n", { DRY_RUN: "1" });
  await assert.rejects(readFile(settings), { code: "ENOENT" });
  assert.doesNotMatch(result.stdout + result.stderr, /previous-context7-secret|current-context7-secret/);
});
