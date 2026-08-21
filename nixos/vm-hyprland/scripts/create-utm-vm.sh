#!/usr/bin/env bash
# UTM VM creation via AppleScript (utmctl has no `create` subcommand as of
# writing). Property names/types below are taken directly from this
# machine's installed /Applications/UTM.app/Contents/Resources/UTM.sdef
# (`make new virtual machine`, `qemu configuration`, `qemu drive/network/
# display configuration` record types) - not guessed from secondhand
# examples. If UTM updates its sdef in a way that breaks this, re-check that
# file (or Script Editor -> File -> Open Dictionary -> UTM) rather than
# guessing property names again.
#
# After creation, open UTM and confirm the disk boots the built image
# rather than an empty UEFI shell.
set -euo pipefail

VM_NAME="${1:-vm-hyprland}"
MEMORY_MB="${VM_MEMORY_MB:-4096}"
CPU_CORES="${VM_CPU_CORES:-4}"

echo "Building .#vm-hyprland-image (first run can take a while)..."
IMAGE_DIR=$(nix build "$HOME/configs/nixos-configs#vm-hyprland-image" --no-link --print-out-paths --impure)
DISK_PATH=$(find "$IMAGE_DIR" -name '*.qcow2' | head -1)

if [ -z "$DISK_PATH" ]; then
  echo "Could not find a .qcow2 file under $IMAGE_DIR" >&2
  exit 1
fi

echo "Disk image: $DISK_PATH"
echo "Creating UTM VM '$VM_NAME' via AppleScript..."

osascript <<APPLESCRIPT
on run
	tell application "UTM"
		set newVM to make new virtual machine with properties {backend:qemu, configuration:{name:"$VM_NAME", architecture:"aarch64", memory:$MEMORY_MB, cpu cores:$CPU_CORES, hypervisor:true, uefi:true, directory share mode:VirtFS, drives:{{removable:false, source:(POSIX file "$DISK_PATH"), interface:VirtIO}}, network interfaces:{{mode:bridged}}, displays:{{hardware:"virtio-gpu-gl-pci", native resolution:true}}}}
	end tell
end run
APPLESCRIPT

cat <<MSG

Created VM '$VM_NAME'. Open UTM to confirm it boots the built image
correctly (rather than an empty UEFI shell) before relying on it.

Directory Share Mode is set to VirtFS, but the actual host folder to share
isn't scriptable - in VM Settings -> Sharing, manually pick
~/configs/nixos-configs as the shared directory.
MSG
