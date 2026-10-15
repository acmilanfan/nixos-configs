import assert from "node:assert/strict";
import test from "node:test";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, mkdtemp, readFile, readdir, stat, utimes, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";

const execute = promisify(execFile);
// Use the actual Nix-evaluated activation, not a duplicate of its shell logic.
const activation = process.env.OPENCODE_TEST_CLI_ACTIVATION;
const options = { skip: !activation && "Set OPENCODE_TEST_CLI_ACTIVATION to the evaluated activation script" };
const artifacts = join(homedir(), "ai/artifacts/nixos-configs/opencode-cli-tests");

async function fixture() {
  await mkdir(artifacts, { recursive: true });
  const home = await mkdtemp(join(artifacts, "settings-"));
  const directory = join(home, ".config/opencode");
  await mkdir(directory, { recursive: true });
  const config = join(directory, "cli.json");
  const run = (dryRun = "") => execute("bash", ["-eu", activation], {
    env: { ...process.env, HOME: home, DRY_RUN_CMD: dryRun },
  });
  const backups = async () => (await readdir(directory)).filter((name) => /^cli\.json\.drift\..*\.json$/.test(name));
  return { config, directory, run, backups };
}

test("fresh CLI settings do not report drift or create a backup", options, async () => {
  const { config, run, backups } = await fixture();
  const result = await run();
  assert.doesNotMatch(result.stdout, /has drifted/);
  assert.equal(JSON.parse(await readFile(config, "utf8")).tabs.mode, "off");
  assert.deepEqual(await backups(), []);
});

test("CLI activation disables noisy builtin notifications", options, async () => {
  const { config, run } = await fixture();
  await run();
  const live = JSON.parse(await readFile(config, "utf8"));
  assert.deepEqual(live.plugins, ["-opencode.notifications"]);
  assert.equal(live.attention.sound, true);
});

test("notification override preserves unrelated CLI plugin order and options", options, async () => {
  const { config, run, backups } = await fixture();
  await run();
  const live = JSON.parse(await readFile(config, "utf8"));
  const external = { package: "example-plugin", options: { compact: true } };
  live.plugins = ["-opencode.notifications", "*", external, "-team.*", "-opencode.notifications"];
  live.session.permissions = "autoaccept";
  await writeFile(config, JSON.stringify(live));
  await run();
  const merged = JSON.parse(await readFile(config, "utf8"));
  assert.deepEqual(merged.plugins, ["*", external, "-team.*", "-opencode.notifications"]);
  assert.equal(merged.session.permissions, "autoaccept");
  const saved = await backups();
  assert.equal(saved.length, 1);
  const second = await run();
  assert.doesNotMatch(second.stdout, /has drifted/);
  assert.deepEqual(await backups(), saved);
});

test("managed CLI drift warns and backs up the exact live file before merging", options, async () => {
  const { config, directory, run, backups } = await fixture();
  await run();
  const live = JSON.parse(await readFile(config, "utf8"));
  live.tabs.mode = "on";
  live.tabs.scope = "global";
  live.attention.volume = 0.2;
  const original = `${JSON.stringify(live, null, 4)}\n`;
  await writeFile(config, original);
  const result = await run();
  assert.match(result.stdout, /cli\.json has drifted/);
  assert.match(result.stdout, /"mode": "on"/);
  assert.match(result.stdout, /"mode": "off"/);
  const saved = await backups();
  assert.equal(saved.length, 1);
  assert.equal(await readFile(join(directory, saved[0]), "utf8"), original);
  const merged = JSON.parse(await readFile(config, "utf8"));
  assert.equal(merged.tabs.mode, "off");
  assert.equal(merged.tabs.scope, "global");
  assert.equal(merged.attention.volume, 0.2);
  const second = await run();
  assert.doesNotMatch(second.stdout, /has drifted/);
  assert.deepEqual(await backups(), saved);
});

test("formatting and unrelated CLI changes do not report drift or create backups", options, async () => {
  const { config, run, backups } = await fixture();
  await run();
  const live = JSON.parse(await readFile(config, "utf8"));
  live.session.permissions = "autoaccept";
  const original = JSON.stringify(live);
  await writeFile(config, original);
  const result = await run();
  assert.doesNotMatch(result.stdout, /has drifted/);
  assert.deepEqual(await backups(), []);
  assert.equal(JSON.parse(await readFile(config, "utf8")).session.permissions, "autoaccept");
});

test("CLI drift keeps the five newest backups without touching other files", options, async () => {
  const { config, directory, run, backups } = await fixture();
  await run();
  for (let i = 1; i <= 6; i++) {
    const path = join(directory, `cli.json.drift.${i}.json`);
    await writeFile(path, String(i));
    await utimes(path, i, i);
  }
  const other = join(directory, "opencode.json.drift.1.json");
  await writeFile(other, "leave untouched");
  const live = JSON.parse(await readFile(config, "utf8"));
  live.tabs.mode = "on";
  await writeFile(config, JSON.stringify(live));
  await run();
  const saved = await backups();
  assert.equal(saved.length, 5);
  assert(!saved.includes("cli.json.drift.1.json"));
  assert(!saved.includes("cli.json.drift.2.json"));
  assert.equal(await readFile(other, "utf8"), "leave untouched");
});

test("CLI drift dry runs do not write, back up, or prune", options, async () => {
  const { config, directory, run, backups } = await fixture();
  await run();
  for (let i = 1; i <= 6; i++) await writeFile(join(directory, `cli.json.drift.${i}.json`), String(i));
  const live = JSON.parse(await readFile(config, "utf8"));
  live.tabs.mode = "on";
  const original = JSON.stringify(live);
  await writeFile(config, original);
  const before = await backups();
  await run("echo");
  assert.equal(await readFile(config, "utf8"), original);
  assert.deepEqual(await backups(), before);
});

test("invalid CLI JSON is left untouched without a backup", options, async () => {
  const { config, run, backups } = await fixture();
  for (const invalid of ["invalid JSON", "", "   \n", "{}\n{}", "[]", "null"]) {
    await writeFile(config, invalid);
    await assert.rejects(run());
    assert.equal(await readFile(config, "utf8"), invalid);
    assert.deepEqual(await backups(), []);
  }
  assert((await stat(config)).isFile());
});
