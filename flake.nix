{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    unstable-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    musnix.url = "github:musnix/musnix/master";
    musnix.inputs.nixpkgs.follows = "nixpkgs";

    nur.url = "github:nix-community/NUR";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
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
  };

  outputs = inputs@{
    self, nixpkgs, unstable-nixpkgs, musnix, nur, home-manager,
    nixos-hardware, auto-cpufreq, ...
  }: 
  let
    linuxSystem = "x86_64-linux";
    macSystem = "aarch64-darwin";

    pkgsFor = system: import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    unstableFor = system: import inputs.unstable-nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    overlay-davinci-resolve = _: prev: {
      davinci-resolve = prev.davinci-resolve-studio.override (old: {
        buildFHSEnv = a:
          old.buildFHSEnv (a // {
            extraBwrapArgs = a.extraBwrapArgs
              ++ [ "--bind /run/opengl-driver/etc/OpenCL /etc/OpenCL" ];
          });
      });
    };

  in {
	homeConfigurations = {
	  "andreishumailov@work" = home-manager.lib.homeManagerConfiguration {
	    pkgs = pkgsFor macSystem;
	    extraSpecialArgs = {
	      inherit inputs;
		unstable = unstableFor macSystem;
	      hmLib = home-manager.lib;
	    };
	    modules = [
	      ./nixos/mac-work/home.nix
	    ];
	  };
	};
    nixosConfigurations = {
      z16 = inputs.nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = { inherit inputs; };
        modules = [
          ./nixos/z16/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.gentooway = import ./nixos/z16/home.nix;
            home-manager.extraSpecialArgs = {
              pkgs = pkgsFor linuxSystem;
              unstable = unstableFor linuxSystem;
              inherit inputs linuxSystem;
            };
          }
          musnix.nixosModules.musnix
          nixos-hardware.nixosModules.lenovo-thinkpad-z
          ({ config, pkgs, ... }: {
            nixpkgs.overlays = [ overlay-davinci-resolve ];
          })
        ];
      };

      t480-home = inputs.nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = { inherit inputs; };
        modules = [
          ./nixos/t480-home/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.gentooway = import ./nixos/t480-home/home.nix;
            home-manager.extraSpecialArgs = {
              pkgs = pkgsFor linuxSystem;
              unstable = unstableFor linuxSystem;
              inherit inputs linuxSystem;
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
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.gentooway = import ./nixos/yogabook-gen10/home.nix;
            home-manager.extraSpecialArgs = {
              pkgs = pkgsFor linuxSystem;
              unstable = unstableFor linuxSystem;
              inherit inputs linuxSystem;
            };
          }
          musnix.nixosModules.musnix
          nixos-hardware.nixosModules.common-pc-laptop
          nixos-hardware.nixosModules.common-pc-laptop-ssd
          nixos-hardware.nixosModules.common-hidpi
          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-gpu-intel
          auto-cpufreq.nixosModules.default
          ({ config, pkgs, ... }: {
            nixpkgs.overlays = [ overlay-davinci-resolve ];
          })
        ];
      };
    };
  };
}

