import assert from "node:assert/strict";
import test from "node:test";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, mkdtemp, readFile, readlink, stat, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const execute = promisify(execFile);
const initializer = fileURLToPath(new URL("../memory-init.sh", import.meta.url));
const artifacts = join(homedir(), "ai/artifacts/nixos-configs/opencode-memory-tests");

async function fixture() {
  await mkdir(artifacts, { recursive: true });
  const root = await mkdtemp(join(artifacts, "seed-"));
  const seeds = join(root, "seeds");
  const memory = join(root, "memory");
  await mkdir(seeds);
  await writeFile(join(seeds, "human.md"), "Original user preferences\n");
  await writeFile(join(seeds, "persona.md"), "Original memory guidance\n");
  return { root, seeds, memory };
}

test("first activation seeds private writable memory files", async () => {
  const { seeds, memory } = await fixture();
  await execute("bash", [initializer, seeds, memory]);
  assert.equal(await readFile(join(memory, "human.md"), "utf8"), "Original user preferences\n");
  assert.equal(await readFile(join(memory, "persona.md"), "utf8"), "Original memory guidance\n");
  assert.equal((await stat(memory)).mode & 0o777, 0o700);
  assert.equal((await stat(join(memory, "human.md"))).mode & 0o777, 0o600);
});

test("later activations preserve learned notes and seed only missing blocks", async () => {
  const { seeds, memory } = await fixture();
  await mkdir(memory);
  await writeFile(join(memory, "human.md"), "Learned user preferences\n");
  await execute("bash", [initializer, seeds, memory]);
  await writeFile(join(seeds, "human.md"), "Updated default preferences\n");
  await execute("bash", [initializer, seeds, memory]);
  assert.equal(await readFile(join(memory, "human.md"), "utf8"), "Learned user preferences\n");
  assert.equal(await readFile(join(memory, "persona.md"), "utf8"), "Original memory guidance\n");
});

test("activation does not replace user-managed symlinks, including dangling ones", async () => {
  const { root, seeds, memory } = await fixture();
  await mkdir(memory);
  const personal = join(root, "personal.md");
  const missing = join(root, "missing.md");
  await writeFile(personal, "User-managed memory\n");
  await symlink(personal, join(memory, "human.md"));
  await symlink(missing, join(memory, "persona.md"));
  await execute("bash", [initializer, seeds, memory]);
  assert.equal(await readlink(join(memory, "human.md")), personal);
  assert.equal(await readlink(join(memory, "persona.md")), missing);
  assert.equal(await readFile(personal, "utf8"), "User-managed memory\n");
});
