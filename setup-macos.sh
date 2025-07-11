#!/usr/bin/env bash

# macOS Setup Script for nix-darwin and Home Manager
# This script helps set up the nix-darwin configuration

set -e

echo "🍎 Setting up macOS with nix-darwin and Home Manager"
echo "=================================================="

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script is only for macOS"
    exit 1
fi

# Check if Nix is installed
if ! command -v nix &> /dev/null; then
    echo "📦 Installing Nix..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    echo "✅ Nix installed successfully"
    echo "🔄 Please restart your terminal and run this script again"
    exit 0
fi

# Check if we're in the right directory
if [[ ! -f "flake.nix" ]]; then
    echo "❌ Please run this script from the nixos-configs directory"
    echo "   cd ~/configs/nixos-configs && ./setup-macos.sh"
    exit 1
fi

echo "🔧 Setting up nix-darwin..."

# Install nix-darwin
if ! command -v darwin-rebuild &> /dev/null; then
    echo "📦 Installing nix-darwin..."
    nix run nix-darwin -- switch --flake ./#mac-work
    echo "✅ nix-darwin installed and configured"
else
    echo "🔄 Updating nix-darwin configuration..."
    darwin-rebuild switch --flake ./#mac-work
    echo "✅ nix-darwin configuration updated"
fi

echo "🏠 Setting up Home Manager..."

# Apply Home Manager configuration
echo "📦 Applying Home Manager configuration..."
nix run home-manager/release-25.05 -- switch --flake ./#andreishumailov@work
echo "✅ Home Manager configuration applied"

echo ""
echo "🎉 Setup complete!"
echo ""
echo "📝 Next steps:"
echo "   1. Restart your terminal to load the new shell configuration"
echo "   2. Run 'sup' to update system configuration"
echo "   3. Run 'hup' to update home-manager configuration"
echo "   4. Check README-macos.md for more information"
echo ""
echo "🍺 Homebrew applications will be installed automatically on next system update"
echo "   You can also run: brew bundle --file=/opt/homebrew/Brewfile"
echo ""
echo "Happy hacking! 🚀"
