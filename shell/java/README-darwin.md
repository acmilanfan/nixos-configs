# Java Maven Darwin Development Shell

This directory contains a Darwin/macOS-compatible development shell for Java Maven projects, based on the original `nix-java-docker.nix` but adapted for macOS.

## Files

- `nix-java-darwin.nix` - Main shell configuration for Darwin/macOS
- `flake-darwin.nix` - Flake configuration for the Darwin shell
- `README-darwin.md` - This documentation file

## Key Differences from Linux Version

The Darwin version differs from the original Linux version in several important ways:

### Removed Linux-specific Features
- **buildFHSUserEnv**: Replaced with standard `mkShell` (FHS environments don't exist on macOS)
- **systemd commands**: Removed Docker systemd service management
- **Linux-specific packages**: Removed glibc, systemd, pam, xorg libraries, etc.

### Darwin-specific Additions
- **Apple SDK frameworks**: Added Security, CoreFoundation, and SystemConfiguration frameworks
- **macOS Docker integration**: Updated Docker setup for Docker Desktop
- **Homebrew path support**: Added `/opt/homebrew/bin` to PATH

### Docker Configuration
- Expects Docker Desktop to be installed and running
- Checks Docker status and provides helpful messages
- No longer attempts to start Docker service via systemd

## Usage

### Using nix-shell directly:
```bash
cd shell/java
NIXPKGS_ALLOW_BROKEN=1 nix-shell nix-java-darwin.nix
```

### Using the flake:
```bash
cd shell/java
nix develop -f flake-darwin.nix
```

## Included Tools

- **Java**: OpenJDK 21 (configurable)
- **Build tools**: Maven, Gradle
- **Node.js**: Version 22 with TypeScript support
- **Development tools**: OpenSSL, GNU Make
- **Database clients**: MySQL client, MariaDB
- **Docker**: Docker CLI (requires Docker Desktop)
- **macOS utilities**: zlib, freetype, ncurses

## Environment Variables

The shell sets up the following environment variables:
- `JAVA_HOME`: Points to the selected JDK
- `LANG`: Set to en_US.UTF-8
- `TZ`: Set to Europe/Berlin
- `PATH`: Includes Java, Homebrew, and system paths

## Prerequisites

1. **Nix package manager** installed on macOS
2. **Docker Desktop** for Docker functionality (optional)
3. **Xcode Command Line Tools** (usually installed automatically)

## Notes

- The shell includes deprecation warnings for Darwin SDK stubs - these are harmless and will be addressed in future Nixpkgs versions
- Some packages may require `NIXPKGS_ALLOW_BROKEN=1` environment variable
- The shell is optimized for Apple Silicon (aarch64-darwin) but should work on Intel Macs as well

## Troubleshooting

### Docker Issues
If you see "Docker Desktop is not running", make sure Docker Desktop is installed and running before entering the shell.

### Build Issues
If you encounter build issues, try:
```bash
export NIXPKGS_ALLOW_BROKEN=1
nix-shell nix-java-darwin.nix
```

### Java Version
To use a different Java version, modify the `selectedJDK` variable in `nix-java-darwin.nix`:
```nix
# selectedJDK = pkgs.openjdk11;
selectedJDK = pkgs.openjdk21;  # Current default
# selectedJDK = pkgs.openjdk23;
```
