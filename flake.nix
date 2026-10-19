{
  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  inputs = {
    # Copy the private secrets submodule into the flake source, so
    # ./secrets/secrets.nix and secrets.yaml resolve without --impure.
    self.submodules = true;

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    unstable-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    musnix.url = "github:musnix/musnix/master";
    musnix.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";

    auto-cpufreq = {
      url = "github:AdnanHodzic/auto-cpufreq";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
      inputs.brew-src.follows = "homebrew-brew";
    };

    # Keep the Homebrew engine in step with tap DSL changes rather than
    # relying on nix-homebrew's older release-tagged brew-src input.
    homebrew-brew = { url = "github:Homebrew/brew"; flake = false; };

    # Homebrew definitions are pinned alongside Nix packages. Update these
    # inputs explicitly, then rebuild; `brew update` does not manage them.
    homebrew-core = { url = "github:homebrew/homebrew-core"; flake = false; };
    homebrew-cask = { url = "github:homebrew/homebrew-cask"; flake = false; };
    homebrew-formulae = { url = "github:FelixKratz/homebrew-formulae"; flake = false; };
    homebrew-autoraise = { url = "github:Dimentium/homebrew-autoraise"; flake = false; };
    homebrew-k06a = { url = "github:k06a/homebrew-tap"; flake = false; };
    homebrew-omlx = { url = "github:jundot/omlx"; flake = false; };

    vicinae-extensions = {
      url = "github:vicinaehq/extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # `gf` CLI used by the Vicinae fuzzy-files extension. The published
    # v0.1.0 macOS release binary is broken (prints no results), so build it
    # from source via its flake.
    goldfish = {
      url = "github:sameoldlab/goldfish";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vicinae = {
      url = "github:vicinaehq/vicinae";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Runtime-decrypted secrets (age/GPG-encrypted secrets.yaml in the
    # secrets submodule). Values never enter /nix/store.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "unstable-nixpkgs";
    };

    nixpkgs-howdy = {
      url = "github:fufexan/nixpkgs/howdy";
    };

    mcp-nixos = {
      url = "github:utensils/mcp-nixos";
      inputs.nixpkgs.follows = "unstable-nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "unstable-nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "unstable-nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "unstable-nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };

    # Plain sources (flake = false) for plugins/packages built in this repo.
    # flake.lock pins them; `pins outdated` / `pins update [name...]` bumps
    # only these, leaving nixpkgs and the other flakes alone.
    tmux-agent-indicator = { url = "github:accessd/tmux-agent-indicator"; flake = false; };
    tmux-resurrect = { url = "github:tmux-plugins/tmux-resurrect"; flake = false; };
    telescope-orgmode = { url = "github:nvim-orgmode/telescope-orgmode.nvim"; flake = false; };
    org-bullets = { url = "github:nvim-orgmode/org-bullets.nvim"; flake = false; };
    nvim-macroni = { url = "github:jesseleite/nvim-macroni"; flake = false; };
    lsplinks-nvim = { url = "github:icholy/lsplinks.nvim"; flake = false; };
    nvim-java = { url = "github:nvim-java/nvim-java"; flake = false; };
    nvim-java-core = { url = "github:nvim-java/nvim-java-core"; flake = false; };
    nvim-java-dap = { url = "github:nvim-java/nvim-java-dap"; flake = false; };
    nvim-java-refactor = { url = "github:nvim-java/nvim-java-refactor"; flake = false; };
    nvim-java-test = { url = "github:nvim-java/nvim-java-test"; flake = false; };
    lua-async = { url = "github:nvim-java/lua-async"; flake = false; };
    spring-boot-nvim = { url = "github:JavaHello/spring-boot.nvim"; flake = false; };
    blueutil-tui = { url = "github:zaloog/blueutil-tui"; flake = false; };
    vimmode-spoon = { url = "github:dbalatero/VimMode.spoon"; flake = false; };
    # Only its common.js (getRegExpSites), to compile block patterns for the
    # managed-storage file (nixos/home-manager/common/firefox-managed-storage.nix).
    leechblockng = { url = "github:proginosko/LeechBlockNG/v1.8"; flake = false; };
    # Skills + the opencode plugin the server imports
    # (nixos/home-manager/common/opencode.nix). Bump with `pins update superpowers`.
    superpowers = { url = "github:obra/superpowers"; flake = false; };
    # Antigravity extensions installed from these pinned sources
    # (nixos/home-manager/common/ai-agents.nix), not from GitHub heads.
    cc-skills-golang = { url = "github:samber/cc-skills-golang"; flake = false; };
    gemini-cli-security = { url = "github:gemini-cli-extensions/security"; flake = false; };
    gemini-cli-code-review = { url = "github:gemini-cli-extensions/code-review"; flake = false; };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      unstable-nixpkgs,
      musnix,
      home-manager,
      nixos-hardware,
      auto-cpufreq,
      nix-darwin,
      nix-homebrew,
      mcp-nixos,
      ...
    }:
    let
      linuxSystem = "x86_64-linux";
      macSystem = "aarch64-darwin";
      vmSystem = "aarch64-linux";
      # The one user on every NixOS host; modules take it as `username`.
      linuxUser = "gentooway";

      # Eval-time values only (emails, marketplace names). Credentials live in
      # secrets/secrets.yaml and are decrypted at activation by sops-nix.
      secrets = import ./secrets/secrets.nix;

      overlay-howdy = _: prev: {
        howdy = inputs.nixpkgs-howdy.legacyPackages.${prev.stdenv.hostPlatform.system}.howdy;
        linux-enable-ir-emitter = inputs.nixpkgs-howdy.legacyPackages.${prev.stdenv.hostPlatform.system}.linux-enable-ir-emitter;
      };

      overlay-custom = import ./nixos/common/overlays.nix { inherit inputs; };

      overlay-fastmcp-slim-fix = import ./nixos/common/overlays/fastmcp-slim-fix.nix;

      overlay-mcp-nixos = nixpkgs.lib.composeExtensions
        mcp-nixos.overlays.default
        overlay-fastmcp-slim-fix;

      # One nixpkgs config and overlay list for everything: each host's system
      # package set (nixpkgs.*) and, through useGlobalPkgs, its Home Manager
      # user. Previously HM got its own `pkgs` via extraSpecialArgs with more
      # overlays than the system, so system-level overlays (DaVinci) never
      # reached HM packages and HM-level nixpkgs.config was silently ignored.
      nixpkgsConfig = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "pnpm-9.15.9"
        ];
      };
      sharedOverlays = [
        overlay-howdy
        overlay-custom
        overlay-mcp-nixos
      ];

      sharedPkgsModule = {
        nixpkgs.config = nixpkgsConfig;
        nixpkgs.overlays = sharedOverlays;
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "backup";
      };

      # Same set outside a host (flake `packages`).
      pkgsFor =
        system:
        import inputs.nixpkgs {
          inherit system;
          config = nixpkgsConfig;
          overlays = sharedOverlays;
        };

      unstableFor =
        system:
        import inputs.unstable-nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            overlay-howdy
            overlay-custom
            overlay-mcp-nixos
          ];
        };

      overlay-davinci-resolve = _: prev: {
        davinci-resolve-studio = prev.davinci-resolve-studio.override (old: {
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
        t480-home = inputs.nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; username = linuxUser; };
          modules = [
            ./nixos/t480-home/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.users.${linuxUser} = import ./nixos/t480-home/home.nix;
              home-manager.extraSpecialArgs = {
                unstable = unstableFor linuxSystem;
                inherit inputs linuxSystem secrets;
              };
            }
            nixos-hardware.nixosModules.lenovo-thinkpad-t480
            sharedPkgsModule
          ];
        };

        yogabook-gen10 = inputs.nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; username = linuxUser; };
          modules = [
            ./nixos/yogabook-gen10/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.users.${linuxUser} = import ./nixos/yogabook-gen10/home.nix;
              home-manager.extraSpecialArgs = {
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
            sharedPkgsModule
            { nixpkgs.overlays = [ overlay-davinci-resolve ]; }
          ];
        };

        vm-hyprland = inputs.nixpkgs.lib.nixosSystem {
          system = vmSystem;
          specialArgs = { inherit inputs; username = linuxUser; };
          modules = [
            ./nixos/vm-hyprland/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.users.${linuxUser} = import ./nixos/vm-hyprland/home.nix;
              home-manager.extraSpecialArgs = {
                unstable = unstableFor vmSystem;
                inherit inputs secrets;
                linuxSystem = vmSystem;
              };
            }
            sharedPkgsModule
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
            ./darwin/mac-work.nix
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
            sharedPkgsModule
            {
              home-manager.users.andreishumailov = import ./nixos/mac-work/home.nix;
              home-manager.extraSpecialArgs = {
                unstable = unstableFor macSystem;
                inherit inputs secrets;
              };
            }
          ];
        };

        "mac-home" = nix-darwin.lib.darwinSystem {
          system = macSystem;
          specialArgs = {
            inherit inputs secrets;
            unstable = unstableFor macSystem;
          };
          modules = [
            ./darwin/mac-home.nix
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                enableRosetta = true;
                user = "gentooway";
                autoMigrate = true;
              };
            }
            home-manager.darwinModules.home-manager
            sharedPkgsModule
            {
              home-manager.users.gentooway = import ./nixos/mac-home/home.nix;
              home-manager.extraSpecialArgs = {
                unstable = unstableFor macSystem;
                inherit inputs secrets;
              };
            }
          ];
        };
      };

      packages = nixpkgs.lib.genAttrs [ linuxSystem macSystem vmSystem ] (system:
        {
          inherit (pkgsFor system) opencode opencode-telegram-bot;
        } // nixpkgs.lib.optionalAttrs (system == macSystem) {
          vm-hyprland-image = self.nixosConfigurations.vm-hyprland.config.system.build.images.qemu-efi;
        });
    };
}
