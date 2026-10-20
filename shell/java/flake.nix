{
  description = "java shell";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          # direnv/nix develop use the plain shell; `.#fhs` keeps the old
          # buildFHSEnv shell for manual use.
          devShells.default = import ./nix-java-docker.nix { inherit pkgs; };
          devShells.fhs = import ./nix-java-docker-fhs.nix { inherit pkgs; };
        });
}
