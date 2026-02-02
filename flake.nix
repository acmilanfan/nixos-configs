{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    unstable-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    musnix.url = "github:musnix/musnix/master";
    musnix.inputs.nixpkgs.follows = "nixpkgs";

    nur.url = "github:nix-community/NUR";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    minimal-tmux = {
      url = "github:niksingh710/minimal-tmux-status";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    auto-cpufreq = {
      url = "github:AdnanHodzic/auto-cpufreq";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
    };
    mac-app-util.url = "github:hraban/mac-app-util";

    vicinae-extensions = {
      url = "github:vicinaehq/extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      unstable-nixpkgs,
      musnix,
      nur,
      home-manager,
      nixos-hardware,
      auto-cpufreq,
      nix-darwin,
      nix-homebrew,
      mac-app-util,
      ...
    }:
    let
      linuxSystem = "x86_64-linux";
      macSystem = "aarch64-darwin";

      sudoUser = builtins.getEnv "SUDO_USER";
      homeDir = if sudoUser != ""
        then "/Users/${sudoUser}"  # macOS path when running with sudo
        else builtins.getEnv "HOME";
      actualHomeDir = if homeDir == "" || homeDir == "/var/root"
        then "/home/${sudoUser}"
        else homeDir;
      secretsPath = "${actualHomeDir}/configs/nixos-configs/secrets/secrets.nix";
      secrets = import secretsPath;

      pkgsFor =
        system:
        import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

      unstableFor =
        system:
        import inputs.unstable-nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

      overlay-davinci-resolve = _: prev: {
        davinci-resolve = prev.davinci-resolve-studio.override (old: {
          buildFHSEnv =
            a:
            old.buildFHSEnv (
              a
              // {
                extraBwrapArgs = a.extraBwrapArgs ++ [ "--bind /run/opengl-driver/etc/OpenCL /etc/OpenCL" ];
              }
            );
        });
      };

    in
    {
      nixosConfigurations = {
        z16 = inputs.nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; };
          modules = [
            ./nixos/z16/configuration.nix
            home-manager.nixosModules.home-manager
            {
              # home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.gentooway = import ./nixos/z16/home.nix;
              home-manager.extraSpecialArgs = {
                pkgs = pkgsFor linuxSystem;
                unstable = unstableFor linuxSystem;
                inherit inputs linuxSystem secrets;
              };
            }
            musnix.nixosModules.musnix
            nixos-hardware.nixosModules.lenovo-thinkpad-z
            (
              { config, pkgs, ... }:
              {
                nixpkgs.overlays = [ overlay-davinci-resolve ];
              }
            )
          ];
        };

        t480-home = inputs.nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; };
          modules = [
            ./nixos/t480-home/configuration.nix
            home-manager.nixosModules.home-manager
            {
              # home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.gentooway = import ./nixos/t480-home/home.nix;
              home-manager.extraSpecialArgs = {
                pkgs = pkgsFor linuxSystem;
                unstable = unstableFor linuxSystem;
                inherit inputs linuxSystem secrets;
              };
            }
            nixos-hardware.nixosModules.lenovo-thinkpad-t480
          ];
        };

        yogabook-gen10 = inputs.nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; };
          modules = [
            ./nixos/yogabook-gen10/configuration.nix
            home-manager.nixosModules.home-manager
            {
              # home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.gentooway = import ./nixos/yogabook-gen10/home.nix;
              home-manager.extraSpecialArgs = {
                pkgs = pkgsFor linuxSystem;
                unstable = unstableFor linuxSystem;
                inherit inputs linuxSystem secrets;
              };
            }
            musnix.nixosModules.musnix
            nixos-hardware.nixosModules.common-pc-laptop
            nixos-hardware.nixosModules.common-pc-laptop-ssd
            nixos-hardware.nixosModules.common-hidpi
            nixos-hardware.nixosModules.common-cpu-intel
            nixos-hardware.nixosModules.common-gpu-intel
            auto-cpufreq.nixosModules.default
            (
              { config, pkgs, ... }:
              {
                nixpkgs.overlays = [ overlay-davinci-resolve ];
              }
            )
          ];
        };
      };

      darwinConfigurations = {
        "mac-work" = nix-darwin.lib.darwinSystem {
          system = macSystem;
          specialArgs = {
            inherit inputs secrets;
            unstable = unstableFor macSystem;
          };
          modules = [
            ./darwin/configuration.nix
            # mac-app-util.darwinModules.default
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                enableRosetta = true;
                user = "andreishumailov";
                autoMigrate = true;
              };
            }
            home-manager.darwinModules.home-manager
            {
              # home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              # home-manager.sharedModules =
              #   [ mac-app-util.homeManagerModules.default ];
              home-manager.users.andreishumailov = import ./nixos/mac-work/home.nix;
              home-manager.extraSpecialArgs = {
                pkgs = pkgsFor macSystem;
                unstable = unstableFor macSystem;
                inherit inputs secrets;
              };
            }
          ];
        };
      };
    };
}
