{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    unstable-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    musnix.url = "github:musnix/musnix/master";
    musnix.inputs.nixpkgs.follows = "nixpkgs";
    nur.url = "github:nix-community/NUR";
    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nix-doom-emacs.url = "github:nix-community/nix-doom-emacs";
    nix-doom-emacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, unstable-nixpkgs, musnix, nur, home-manager
    , nixos-hardware, nix-doom-emacs, ... }:
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

      overlay-davinci-resolve = old: prev: {
        davinci-resolve = prev.davinci-resolve-studio.override (old: {
          buildFHSEnv = a:
            (old.buildFHSEnv (a // {
              extraBwrapArgs = a.extraBwrapArgs
                ++ [ "--bind /run/opengl-driver/etc/OpenCL /etc/OpenCL" ];
            }));
        });
      };
    in {
      nixosConfigurations = {
        z16 = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./nixos/z16/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.gentooway = import ./nixos/z16/home.nix;
              home-manager.extraSpecialArgs = {
                inherit pkgs;
                inherit unstable;
                inherit system;
                inherit inputs;
              };
            }
            musnix.nixosModules.musnix
            nixos-hardware.nixosModules.lenovo-thinkpad-z
            ({ config, pkgs, ... }: {
              nixpkgs.overlays = [ overlay-davinci-resolve ];
            })
          ];
        };
        t480-work = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./nixos/t480-work/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashumailov = import ./nixos/t480-work/home.nix;
              home-manager.extraSpecialArgs = {
                inherit pkgs;
                inherit unstable;
                inherit system;
                inherit inputs;
              };
            }
            nixos-hardware.nixosModules.common-pc-laptop
            nixos-hardware.nixosModules.common-pc-laptop-ssd
          ];
        };
        t480-home = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./nixos/t480-home/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.gentooway = import ./nixos/t480-home/home.nix;
              home-manager.extraSpecialArgs = {
                inherit pkgs;
                inherit unstable;
                inherit system;
                inherit inputs;
              };
            }
            nixos-hardware.nixosModules.lenovo-thinkpad-t480
          ];
        };
        yogabook = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./nixos/yogabook/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.gentooway = import ./nixos/yogabook/home.nix;
              home-manager.extraSpecialArgs = {
                inherit pkgs;
                inherit unstable;
                inherit system;
                inherit inputs;
              };
            }
            nixos-hardware.nixosModules.common-pc-laptop
            nixos-hardware.nixosModules.common-pc-laptop-ssd
            ({ config, pkgs, ... }: {
              nixpkgs.overlays = [ overlay-davinci-resolve ];
            })
          ];
        };
      };
    };

}
