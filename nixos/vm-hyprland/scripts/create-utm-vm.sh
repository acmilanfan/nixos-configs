#!/usr/bin/env bash
# UTM VM creation via AppleScript (utmctl has no `create` subcommand as of
# writing). Property names/types below are taken directly from this
# machine's installed /Applications/UTM.app/Contents/Resources/UTM.sdef
# (`make new virtual machine`, `qemu configuration`, `qemu drive/network/
# display configuration` record types, `update registry`) - not guessed from
# secondhand examples. If UTM updates its sdef in a way that breaks this,
# re-check that file (or Script Editor -> File -> Open Dictionary -> UTM)
# rather than guessing property names again.
#
# After creation, open UTM and confirm the disk boots the built image
# rather than an empty UEFI shell. Steps that still need doing by hand are in
# docs/vm-hyprland.md.
set -euo pipefail

VM_NAME="${1:-vm-hyprland}"
MEMORY_MB="${VM_MEMORY_MB:-4096}"
CPU_CORES="${VM_CPU_CORES:-4}"
# The image is built with diskSize = "auto" (closure + ~512MB free); the
# guest grows its root partition into whatever the disk is enlarged to.
DISK_SIZE="${VM_DISK_SIZE:-100G}"
SHARE_DIR="${VM_SHARE_DIR:-$HOME/configs/nixos-configs}"
BUNDLE="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/$VM_NAME.utm"

if [ -e "$BUNDLE" ]; then
  echo "$BUNDLE already exists; delete the VM in UTM first or pass another name." >&2
  exit 1
fi

echo "Building .#vm-hyprland-image (first run can take a while)..."
# The linux-builder is stopped by default; `run` starts it for this build only.
IMAGE_DIR=$(linux-builder run nix build "$HOME/configs/nixos-configs#vm-hyprland-image" --no-link --print-out-paths)
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
		set newVM to make new virtual machine with properties {backend:qemu, configuration:{name:"$VM_NAME", architecture:"aarch64", memory:$MEMORY_MB, cpu cores:$CPU_CORES, hypervisor:true, uefi:true, directory share mode:VirtFS, drives:{{removable:false, source:(POSIX file "$DISK_PATH"), interface:VirtIO}}, network interfaces:{{mode:bridged}}, displays:{{hardware:"virtio-gpu-gl-pci", dynamic resolution:true, native resolution:true}}}}
		-- QEMU VMs keep the shared directory in UTM's registry (a security-
		-- scoped bookmark), not in config.plist; this is the only scripted
		-- way to set it.
		update registry of newVM with {POSIX file "$SHARE_DIR"}
	end tell
end run
APPLESCRIPT

# UTM imports (copies) the source image into the bundle; enlarge that copy.
VM_DISK=$(find "$BUNDLE/Data" -name '*.qcow2' | head -1)
if [ -n "$VM_DISK" ]; then
  echo "Resizing $VM_DISK to $DISK_SIZE..."
  chmod u+w "$VM_DISK"
  qemu-img resize "$VM_DISK" "$DISK_SIZE"
else
  echo "Couldn't find the imported disk under $BUNDLE/Data; resize it in UTM (Settings -> drive -> Resize)." >&2
fi

cat <<MSG

Created VM '$VM_NAME' sharing $SHARE_DIR, disk $DISK_SIZE. Open UTM to
confirm it boots the built image correctly (rather than an empty UEFI
shell) before relying on it. Remaining manual steps: docs/vm-hyprland.md.
MSG
