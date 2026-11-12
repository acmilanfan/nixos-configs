{ lib, buildGoModule }:
let
  sourceRoot = ../../../apps/youtube-org;
in
buildGoModule {
  pname = "youtube-org";
  version = "0.1.0";

  # Only tracked program/module files enter the store, never runtime credentials.
  src = lib.fileset.toSource {
    root = sourceRoot;
    fileset = lib.fileset.unions [
      (sourceRoot + "/go.mod")
      (sourceRoot + "/go.sum")
      (lib.fileset.fileFilter (file: file.type == "regular" && file.hasExt "go") (sourceRoot + "/cmd"))
      (lib.fileset.fileFilter (file: file.type == "regular" && file.hasExt "go") (sourceRoot + "/internal"))
    ];
  };

  vendorHash = "sha256-JmN7Oh199H5RzIwXtptLpOEvtFp3GpaUDdSe1296I9w=";
  subPackages = [ "cmd/youtube-org" ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    go test -timeout 90s ./...
    runHook postCheck
  '';

  meta = {
    description = "Save selected YouTube videos directly to monthly Org files";
    mainProgram = "youtube-org";
    platforms = lib.platforms.darwin;
  };
}
