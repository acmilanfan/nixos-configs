{ inputs, lib, python312, callPackage }:
let
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  # mlx / mlx-metal are namespace packages: mlx-metal installs
  # libmlx.dylib + libjaccl.dylib + mlx.metallib into mlx/lib/.
  # core.cpython-312-darwin.so (in mlx) uses @rpath=@loader_path/lib,
  # which resolves inside mlx's own store path.  Under Nix each
  # Python package lives in its own store path, so the .so can't
  # find the dylibs.  Symlink them in.
  mlxFixOverlay = self: super: {
    mlx = super.mlx.overrideAttrs (old: {
      postFixup = (old.postFixup or "") + ''
        mkdir -p $out/${python312.sitePackages}/mlx/lib
        ln -sf ${self.mlx-metal}/${python312.sitePackages}/mlx/lib/libmlx.dylib $out/${python312.sitePackages}/mlx/lib/
        ln -sf ${self.mlx-metal}/${python312.sitePackages}/mlx/lib/libjaccl.dylib $out/${python312.sitePackages}/mlx/lib/
        ln -sf ${self.mlx-metal}/${python312.sitePackages}/mlx/lib/mlx.metallib $out/${python312.sitePackages}/mlx/lib/
      '';
    });
  };

  pythonBase = callPackage inputs.pyproject-nix.build.packages { python = python312; };
  pythonSet = pythonBase.overrideScope (
    lib.composeManyExtensions [
      inputs.pyproject-build-systems.overlays.wheel
      overlay
      mlxFixOverlay
    ]
  );
in
pythonSet.mkVirtualEnv "mtplx-env" workspace.deps.default
