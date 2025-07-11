# macOS Setup with nix-darwin and Home Manager

This configuration provides a complete macOS setup using nix-darwin and Home Manager with Homebrew integration for applications that don't work well with Nix.

## Initial Setup

### 1. Install Nix

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### 2. Clone this repository

```bash
git clone https://github.com/your-username/nixos-configs.git ~/configs/nixos-configs
cd ~/configs/nixos-configs
```

### 3. Install nix-darwin

```bash
nix run nix-darwin -- switch --flake ~/configs/nixos-configs/#mac-work
```

### 4. Apply Home Manager configuration

```bash
nix run home-manager/release-25.05 -- switch --flake ~/configs/nixos-configs/#andreishumailov@work
```

## Daily Usage

### System Updates

```bash
# Update system configuration
sup  # alias for: darwin-rebuild switch --flake $HOME/configs/nixos-configs/#mac-work

# Update home-manager configuration  
hup  # alias for: home-manager switch --flake $HOME/configs/nixos-configs/#andreishumailov@work

# Update flake inputs
up   # alias for: cd $HOME/configs/nixos-configs && nix flake update
```

### Homebrew Management

Homebrew is automatically managed through nix-darwin. The configuration includes:

#### GUI Applications (Casks)
- **Browsers**: Google Chrome, Firefox
- **Development**: Visual Studio Code, Docker, Postman
- **Communication**: Slack, Discord, Zoom
- **Productivity**: Notion, Obsidian
- **Media**: VLC, Spotify
- **Utilities**: Alfred, Rectangle, Raycast
- **Terminals**: Kitty, Alacritty

#### CLI Tools (Brews)
- `mas` - Mac App Store CLI
- `scrcpy` - Android screen mirroring

#### Mac App Store Apps
- Xcode
- TestFlight

### macOS System Preferences

The configuration automatically sets up:

- **Dock**: Auto-hide enabled, no recent apps, optimized size
- **Finder**: Show all files and extensions, list view, path bar
- **Keyboard**: Fast key repeat, caps lock → escape
- **Trackpad**: Tap to click, three-finger drag
- **Security**: Touch ID for sudo
- **Appearance**: Dark mode

### Development Environment

#### Available Development Shells
```bash
docker-shell   # Java development environment
java-shell     # Pure Java shell
go-shell       # Go and Node.js environment
python-shell   # Python development
fhs-shell      # FHS-compliant shell for compatibility
```

#### macOS-specific Tools
- **Colima**: Container runtime (Docker alternative)
- **mas**: Mac App Store CLI
- **m-cli**: Swiss Army Knife for macOS
- **duti**: Default application handler

### Useful Aliases

```bash
# System management
flush-dns      # Flush DNS cache
show-hidden    # Show hidden files in Finder
hide-hidden    # Hide hidden files in Finder

# Docker/Colima
docker-start   # Start Colima
docker-stop    # Stop Colima

# Git and organization
gs             # git status
gp             # git pull
os             # Pull org files
op             # Push org files
```

## Configuration Structure

```
├── flake.nix                    # Main flake configuration
├── darwin/
│   └── configuration.nix        # nix-darwin system configuration
├── nixos/
│   ├── mac-work/
│   │   └── home.nix            # macOS-specific home-manager config
│   └── home-manager/
│       └── common/             # Shared home-manager modules
│           ├── default.nix     # Main imports
│           ├── packages.nix    # Package definitions with platform guards
│           └── shell.nix       # Shell configuration
└── README-macos.md             # This file
```

## Customization

### Adding Homebrew Applications

Edit `darwin/configuration.nix` and add to the appropriate section:

```nix
homebrew = {
  casks = [
    "your-new-app"
  ];
  brews = [
    "your-cli-tool"
  ];
  masApps = {
    "App Name" = 123456789;  # App Store ID
  };
};
```

### Adding Nix Packages

For system-wide packages, edit `darwin/configuration.nix`:
```nix
environment.systemPackages = with pkgs; [
  your-package
];
```

For user packages, edit `nixos/mac-work/home.nix`:
```nix
home.packages = with pkgs; [
  your-package
];
```

### Platform-Specific Packages

The configuration uses platform guards to ensure compatibility:

```nix
home.packages = with pkgs; [
  # Common packages
  git
  vim
] ++ lib.optionals stdenv.isLinux [
  # Linux-only packages
  linux-specific-tool
] ++ lib.optionals stdenv.isDarwin [
  # macOS-only packages
  macos-specific-tool
];
```

## Troubleshooting

### Homebrew Issues
```bash
# Manually run homebrew operations
brew update
brew upgrade
brew cleanup
```

### Nix Issues
```bash
# Rebuild nix database
nix-store --verify --check-contents --repair

# Clean up old generations
nix-collect-garbage -d
```

### Home Manager Issues
```bash
# Reset home-manager
home-manager expire-generations "-30 days"
```

## Migration from Linux

If migrating from a Linux NixOS setup:

1. Review `nixos/home-manager/common/packages.nix` for Linux-specific packages
2. Check shell aliases in `nixos/home-manager/common/shell.nix`
3. Adapt any custom scripts or configurations
4. Consider which GUI applications should use Homebrew vs Nix

The configuration is designed to share as much as possible between Linux and macOS while respecting platform differences.
