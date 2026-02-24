# NixOS & Darwin Configurations

This repository contains Nix-based configurations for various NixOS and macOS machines, managed with Nix Flakes and Home Manager.

## Project Overview

- **Core Technologies:** Nix, NixOS, nix-darwin, Home Manager, Nix Flakes.
- **Architectures:** Supports `x86_64-linux` and `aarch64-darwin`.
- **Target Machines:**
  - **NixOS:** `z16` (ThinkPad Z16), `t480-home` (ThinkPad T480), `yogabook-gen10`.
  - **macOS:** `mac-work`, `mac-home`.
- **Key Modules:**
  - `nixos/`: NixOS-specific configurations and shared modules.
  - `darwin/`: nix-darwin configurations for macOS.
  - `dotfiles/`: Source for configuration files (symlinked/managed via Home Manager).
  - `shell/`: Custom nix-shell environments.
  - `secrets/`: Secret management (local `secrets.nix`).

## Deployment Commands

### NixOS
To apply a configuration on a NixOS machine:
```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

### macOS (nix-darwin)
To apply a configuration on a macOS machine:
```bash
darwin-rebuild switch --flake .#<hostname> --impure
```
*Note: `--impure` may be required as the flake uses environment variables to resolve home directories and secrets.*

## Key Components & Configurations

- **Keyboard Management:** Extensive use of `kanata` for advanced keyboard remapping on both platforms.
- **macOS Window Management:** `aerospace`, `jankyborders`, and custom `hammerspoon` scripts (including `NanoWM`).
- **Status Bars:** `sketchybar` on macOS, various WMs (Awesome, Hyprland, Sway) on Linux.
- **Containers:** `colima` is configured for Docker compatibility on macOS, including optimizations for Testcontainers.
- **Secret Management:** Secrets are imported from `secrets/secrets.nix`. Ensure this file exists before rebuilding.

## Development Conventions

- **Modularity:** Configuration is split into logical modules (e.g., `networking.nix`, `fonts.nix`, `services.nix`) under `nixos/common/`.
- **Shared Darwin Config:** `darwin/common.nix` contains system-level defaults and Homebrew integration for macOS.
- **Home Manager:** Used for both Linux and macOS user environments. Common macOS home settings are in `nixos/common/home-darwin.nix`.
- **Dotfile Management:** Files in `dotfiles/` are symlinked to `$HOME` using Home Manager's `home.file` attribute.
- **Homebrew:** Managed via `nix-homebrew` within `nix-darwin` configurations to ensure a unified setup.

## Key Files

- `flake.nix`: Entry point for all configurations.
- `nixos/common/default.nix`: Shared NixOS system modules.
- `darwin/common.nix`: Shared macOS system modules.
- `nixos/common/home-darwin.nix`: Shared Home Manager configuration for macOS.
- `dotfiles/`: Contains raw configuration for tools like `kitty`, `nvim`, `aerospace`, etc.
