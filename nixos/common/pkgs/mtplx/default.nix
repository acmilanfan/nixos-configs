{ inputs, lib, python312, callPackage }:
let
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
  pythonBase = callPackage inputs.pyproject-nix.build.packages { python = python312; };
  pythonSet = pythonBase.overrideScope (
    lib.composeManyExtensions [
      inputs.pyproject-build-systems.overlays.wheel
      overlay
    ]
  );
in
pythonSet.mkVirtualEnv "mtplx-env" workspace.deps.default
