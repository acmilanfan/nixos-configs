{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-22.11";
    unstable-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    musnix.url = "github:musnix/musnix/master";
    musnix.inputs.nixpkgs.follows = "nixpkgs";
    nur.url = "github:nix-community/NUR";
    home-manager.url = "github:nix-community/home-manager/release-22.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = inputs@{ self, nixpkgs, unstable-nixpkgs, musnix, nur, home-manager, nixos-hardware, ... }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };

      unstable = import unstable-nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };

      lib = nixpkgs.lib;
    in {
    nixosConfigurations = {
      nixos = lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./nixos/legion5/configuration.nix
          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.gentooway = import ./nixos/legion5/home.nix;
            home-manager.extraSpecialArgs = {
              inherit pkgs;
              inherit unstable;
              inherit system;
            };
          }
          musnix.nixosModules.musnix
          nixos-hardware.nixosModules.common-cpu-amd
          nixos-hardware.nixosModules.common-pc-laptop
          nixos-hardware.nixosModules.common-pc-laptop-ssd
        ];
      };
    };
  };

}