{
  description = "go shell";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          # direnv/nix develop use the plain shell; `.#fhs` keeps the old
          # buildFHSEnv shell for manual use.
          devShells.default = import ./nix-go-node.nix { inherit pkgs; };
          devShells.fhs = import ./nix-go-node-fhs.nix { inherit pkgs; };
        });
}
