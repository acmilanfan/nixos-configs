# opencode-agent-memory as a Nix-built directory plugin, instead of letting
# opencode install `opencode-agent-memory@<version>` from npm at runtime with
# floating dependencies. The published tarball ships a prebuilt dist/; this
# directory's package.json + package-lock.json pin every dependency by
# integrity hash. Regenerate the lock after a version bump:
#   NPM_CONFIG_USERCONFIG=/dev/null npm install --package-lock-only \
#     --ignore-scripts --registry=https://registry.npmjs.org/
# then update npmDepsHash (nix run nixpkgs#prefetch-npm-deps -- package-lock.json).
#
# @huggingface/transformers is left out: it is only a lazy import for the
# journal's semantic search (embeddings), and the journal is disabled
# (~/.config/opencode/agent-memory.json). Enabling the journal needs it back.
{
  lib,
  buildNpmPackage,
  fetchurl,
}:

buildNpmPackage (finalAttrs: {
  pname = "opencode-agent-memory";
  version = "0.3.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/opencode-agent-memory/-/opencode-agent-memory-${finalAttrs.version}.tgz";
    hash = "sha512-M+U1sYu47RaPKNIlRy85uI6mw3MFwEtf74Gzlm5D6no70RRzszQcrjvuetx7Uq/s+FSoZt3z/CHKBx8OBDvurw==";
  };

  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-OfQNBfrsYKcTi00E91k4V2s8emfx9CJBoYJS4QUBUHA=";

  # dist/ is prebuilt in the published tarball.
  dontNpmBuild = true;

  # opencode loads directory plugins from <dir>/index.js (like the other
  # directory plugins in opencode.nix); re-export the package entrypoint there.
  postInstall = ''
    echo 'export { default } from "./dist/index.js";' \
      > "$out/lib/node_modules/opencode-agent-memory/index.js"
  '';

  meta = {
    description = "Letta-style persistent memory blocks for opencode";
    homepage = "https://github.com/joshuadavidthomas/opencode-agent-memory";
    license = lib.licenses.mit;
  };
})
