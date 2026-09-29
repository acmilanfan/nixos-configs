# Build one Raycast Store extension from its pinned upstream commit as a
# network-enabled fixed-output derivation.
#
# Used for extensions that cannot be built with the vicinae flake's
# mkRayCastExtension:
#   - broken/stale lockfiles (importNpmLock fails or npm wants uncached deps)
#   - package.json `overrides` conflicting with nix-injected tarball URLs
#   - old `ray` CLI shims that download the build binary over the network
#
# npm install + `ray build` run inside the derivation (fixed-output
# derivations are allowed to use the network), and the result is pinned by
# `outHash`. There is no local copy of the built extension anywhere.
#
# `node` exists because some extensions bundle an old @raycast/api such that
# the derived `ray` CLI misbehaves on newer Node; `patchBuild` rewrites the
# package.json build script (e.g. to add `-e dist`).
#
# Updating: bump `rev` to the commit the store currently builds (see
# scripts/update-vicinae-raycast-extensions.sh), set both hashes to
# lib.fakeHash, and let two builds report the real values (first the source
# hash, then the output hash).
{
  pkgs,
  name,
  dir,
  rev,
  sourceHash,
  outHash,
  author ? null, # metadata for scripts/update-vicinae-raycast-extensions.sh
  node ? pkgs.nodejs,
  patchBuild ? false,
  extraPostPatch ? "",
}:
pkgs.stdenv.mkDerivation {
  pname = "raycast-ext-${name}";
  version = "0";
  src = pkgs.fetchFromGitHub {
    owner = "raycast";
    repo = "extensions";
    inherit rev;
    hash = sourceHash;
    sparseCheckout = [ "/extensions/${dir}" ];
  } + "/extensions/${dir}";
  nativeBuildInputs = [
    node
    pkgs.curl
    pkgs.cacert
    pkgs.jq
  ];
  postPatch =
    (if patchBuild then
      ''
        ${pkgs.jq}/bin/jq '.scripts.build = "ray build -e dist"' package.json > package.json.tmp
        mv package.json.tmp package.json
      ''
    else
      "")
    + extraPostPatch;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = outHash;
  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    export npm_config_cache="$TMPDIR/npm-cache"
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export NIX_SSL_CERT_FILE=$SSL_CERT_FILE
    npm install --no-audit --no-fund
    npm run build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    # ray build writes to $HOME/.config/raycast/extensions/<package name>,
    # which may differ from the source directory name (e.g. google-translate
    # builds a "translate" package). There is exactly one extension per build.
    cp -r "$HOME/.config/raycast/extensions/"*/. "$out/"
    runHook postInstall
  '';
}
