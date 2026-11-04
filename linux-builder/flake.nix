{
  description = "Pinned nixpkgs for the nix-darwin Linux builder VM";

  # Pin a commit, not a branch: Nix merges inputs with the same original URL
  # into one lock node, which lets a root nix flake update move the pin.
  # Named builder-nixpkgs so the root lock keeps `nixpkgs` for the main input.
  inputs.builder-nixpkgs.url = "github:NixOS/nixpkgs/7dcdd87373d72e7a2173e4db02e20d3d7f495cfd";

  outputs =
    { self, builder-nixpkgs }:
    {
      legacyPackages.aarch64-darwin = import builder-nixpkgs { system = "aarch64-darwin"; };
    };
}
