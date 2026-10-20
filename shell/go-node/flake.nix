{
  description = "go shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          # direnv/nix develop use the plain shell; `.#fhs` keeps the old
          # buildFHSEnv shell for manual use (Linux only).
          devShells = {
            default = import ./nix-go-node.nix { inherit pkgs; };
          } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
            fhs = import ./nix-go-node-fhs.nix { inherit pkgs; };
          };
        });
}
