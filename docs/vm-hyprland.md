# vm-hyprland on a Mac (UTM)

How to bring the `vm-hyprland` UTM VM up on another Mac, and which steps are
still manual. Everything VM-side is in `nixos/vm-hyprland/`; the Mac-side
helpers are in `nixos/common/home-darwin.nix` and `darwin/mac-*.nix`.

## 1. Mac side (once per Mac)

1. **Apply the Mac config:** `sup`. This installs `create-utm-vm-hyprland`,
   `utm-vm-hyprland-share` and `sup-vm-hyprland`, and the linux-builder's GC
   thresholds (`min-free` 20 GiB / `max-free` 40 GiB). Changing the builder's
   config makes the running builder build its replacement, so it needs some
   free disk; see below if it doesn't have it.
2. **Check the linux-builder** (it builds every aarch64-linux path):

   ```bash
   sudo nix store info --store ssh-ng://linux-builder   # must say Trusted: 1
   sudo ssh linux-builder 'df -h /'
   ```

   - **Disk full** (builds fail with `No space left on device`):
     `sudo ssh linux-builder nix-store --gc`.
   - **`Trusted: 0`** (uploads fail with `lacks a signature by a trusted
     key`): the builder's store has a corrupt (e.g. empty) `nix.conf`,
     typically left behind by a full disk. Check with
     `sudo ssh linux-builder 'wc -c /etc/nix/nix.conf'` (0 bytes = broken).
     Recreate the builder's disk; its keys in `/var/lib/linux-builder/keys`
     are kept:

     ```bash
     sudo launchctl bootout system/org.nixos.linux-builder
     sudo rm /var/lib/linux-builder/nixos.qcow2
     sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.linux-builder.plist
     ```

     It comes back with an empty store, so the next build re-uploads or
     re-downloads its inputs.
3. **SSH key:** the VM is key-only. This Mac's `~/.ssh/id_ed25519.pub` must
   be in `nixos/vm-hyprland/configs/authorized_keys` before building a new
   image or deploying.

## 2a. New VM

```bash
create-utm-vm-hyprland            # VM name defaults to vm-hyprland
```

It builds `.#vm-hyprland-image`, creates the UTM VM (virtio-gpu-gl display
with dynamic + native resolution, bridged network, VirtFS sharing), points the
share at `~/configs/nixos-configs` and enlarges the imported disk to 100G.
Overrides: `VM_MEMORY_MB`, `VM_CPU_CORES`, `VM_DISK_SIZE`, `VM_SHARE_DIR`.
The first run triggers a macOS Automation prompt for UTM; allow it.

Then:

1. Boot it in UTM and log in at the console as `gentooway` / `changeme`;
   run `passwd`.
2. Find its IP (`ip -4 a` in the VM). The name `vm-hyprland` doesn't resolve
   from the Mac, so deploys use the IP.
3. Continue with **3. Deploy**.

## 2b. Existing VM created from an older image

A VM created before these fixes needs the following, in this order:

1. **IP:** `ip -4 a` in the VM, or match the MAC address in
   `~/Library/Containers/com.utmapp.UTM/Data/Documents/vm-hyprland.utm/config.plist`
   against `arp -a`.
2. **SSH key** (an old generation may still have password login and no
   authorized keys). From a normal terminal:
   `ssh-copy-id -i ~/.ssh/id_ed25519.pub gentooway@<ip>`.
3. **Disk.** The image's root disk is sized to the closure with ~512MB
   free, so the first deploy runs out of space. Shut the VM down, then in
   UTM: VM Settings -> the VirtIO drive -> **Resize…** (e.g. 100 GB). Boot
   and check `df -h /`. If the root partition did not grow (its grow step
   needs a little free space itself):

   ```bash
   nix-store --gc
   sudo systemctl restart growpart.service && sudo systemctl restart systemd-growfs-root.service
   ```

4. **Shared folder** (VM stopped): `utm-vm-hyprland-share`. Or by hand:
   VM Settings -> Sharing -> Directory Share Mode VirtFS -> pick
   `~/configs/nixos-configs`.
5. **Boot partition.** The ESP is a fixed 256M and an aarch64 kernel +
   initrd is ~90MB. Deployed configs keep only one boot entry, but a VM that
   still has several old kernels fails the bootloader step with
   `No space left on device ... /boot/EFI/nixos/...`. Then delete the old
   generations and their kernel files, keeping the running one:

   ```bash
   ls -la /nix/var/nix/profiles/ ; readlink /run/current-system
   sudo nix-env -p /nix/var/nix/profiles/system --delete-generations <old ones>
   ls /boot/EFI/nixos/          # remove kernels/initrds no kept generation uses
   sudo rm -f /boot/EFI/nixos/*linux-<old version>* /boot/EFI/nixos/*.tmp
   ```

## 3. Deploy

```bash
VM_HYPRLAND_HOST=<ip> sup-vm-hyprland
ssh -t gentooway@<ip> sudo reboot
```

`sup-vm-hyprland` builds on the Mac (via the linux-builder) and asks for the
VM's sudo password. Reboot after the first deploy so Hyprland and the session
agent start with the new config.

Check:

- Resizing the UTM window changes the guest resolution, with scale 2:
  `journalctl --user -u spice-vdagent | grep Virtual-1` logs each change.
- The cursor lines up without capturing input.
- `ls ~/configs/nixos-configs` shows the Mac's checkout (mounted on first
  access).

## What is fixed in the config (for reference)

- **Resolution:** UTM sends the window size to the SPICE agent, not to
  virtio-gpu. The session agent wrapper (`home-manager/custom.nix`) applies it
  to `Virtual-1` at scale 2 and ignores the stale 1280x800 that UTM sends at
  login.
- **Hyprland patch** (`configs/hardware/hyprland-modeset-buffer-size.patch`):
  Hyprland reused the previous frame's buffer for a mode change, which
  virtio-gpu rejects. When Hyprland is updated and the patch no longer
  applies, the VM build fails at `patching file src/helpers/Monitor.cpp`:
  rebase it, or drop it if upstream fixed `CMonitorState::ensureBufferPresent`.
- **Cursor:** `xwayland.force_zero_scaling` so the SPICE agent's tablet range
  matches UTM's pixel coordinates. X11-only apps render unscaled (small).
- **No secrets:** sops-nix is disabled on the VM (the secrets are encrypted
  only to the admin GPG key), so `ai-env.sh` etc. don't exist there.
- **Boot menu:** one entry (`configurationLimit = 1`); older generations
  stay in the profile for `nixos-rebuild switch --rollback`.
