{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  makeWrapper,
  ripgrep,
  unzip,
}:

# OpenCode 2 built from source with the TUI reconnect-retry fix from upstream
# PR #59543 (issue #59542: a single transient session read after an event
# stream reconnect sends the session view back to the home screen).
#
# The llm-agents package installs the prebuilt npm binary, which cannot be
# patched. This derivation compiles the CLI instead. It is intentionally
# restricted to aarch64-darwin: Linux keeps the pinned npm binary until the
# fix reaches a release, and the PR applies unmodified to 2.2.x (the 2.1.4 port needed
# an inlined abort() because that helper did not exist there).
let
  version = "2.2.5";
  bunVersion = "1.4.4";

  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    tag = "v${version}";
    hash = "sha256-/a1czcXi12KWPXcESqplNdOZcjEs8gWCMO7w4nQYLkw=";
  };

  # The build script refuses to run on older Bun; nixpkgs has 1.4.2.
  bun = stdenv.mkDerivation {
    pname = "bun";
    version = bunVersion;
    src = fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${bunVersion}/bun-darwin-aarch64.zip";
      hash = "sha256-wkDX8My5DCY6hJ/NsJt+5iYw2SE0jtaq/ahrnVd7xRA=";
    };
    nativeBuildInputs = [ unzip ];
    sourceRoot = "bun-darwin-aarch64";
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 bun $out/bin/bun
      runHook postInstall
    '';
  };

  # Workspace install is a fixed-output derivation because Nix builds are
  # sandboxed. The lockfile is frozen, so the result only depends on `src`.
  deps = stdenv.mkDerivation {
    pname = "opencode-${version}-node-modules";
    inherit version src;
    nativeBuildInputs = [ bun ];
    dontConfigure = true;
    dontFixup = true;
    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      export BUN_INSTALL_CACHE_DIR=$TMPDIR/bun-cache
      bun install --frozen-lockfile
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      # Root node_modules holds the real packages under .bun; per-workspace
      # node_modules are symlink farms pointing into it with relative paths,
      # so they must be preserved at the same depth (e.g. @opentui/solid lives
      # in packages/cli/node_modules, not at the root).
      while IFS= read -r d; do
        mkdir -p "$out/$(dirname "$d")"
        cp -a "$d" "$out/$d"
      done < <(find . -type d -name node_modules -prune -print)
      runHook postInstall
    '';
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-3iHVHeH0Rp6waPh/gJeC17Hfbtp6iwP2K6ioAk67cHc=";
  };
in
stdenv.mkDerivation {
  pname = "opencode2";
  inherit version src;

  patches = [ ./59543.patch ];

  nativeBuildInputs = [ bun makeWrapper ];

  postPatch = ''
    # Restore every vendored node_modules tree (root and per-workspace). Copy
    # instead of symlinking: Bun resolves symlinks by real path, so the
    # workspace links inside the root tree must resolve within this checkout.
    while IFS= read -r d; do
      rm -rf "$d"
      mkdir -p "$(dirname "$d")"
      cp -a "${deps}/$d" "$d"
    done < <(cd ${deps} && find . -type d -name node_modules -prune -print)
  '';

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    export BUN_INSTALL_CACHE_DIR=$TMPDIR/bun-cache
    # The build reads its release metadata from git, which store sources lack.
    export OPENCODE_CHANNEL=latest
    export OPENCODE_VERSION=${version}
    (
      cd packages/cli
      bun run build --single --skip-web-ui --skip-install
    )
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 "$(find packages/cli/dist -type f -name opencode | head -1)" $out/bin/opencode2
    wrapProgram $out/bin/opencode2 --prefix PATH : ${lib.makeBinPath [ ripgrep ]}
    runHook postInstall
  '';

  # Bun-compiled executable; stripping corrupts the embedded payload.
  dontStrip = true;

  meta = {
    description = "OpenCode 2 CLI built from source with the session-read retry fix";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    mainProgram = "opencode2";
    platforms = [ "aarch64-darwin" ];
  };
}
