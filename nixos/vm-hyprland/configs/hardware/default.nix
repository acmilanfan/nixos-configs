{ modulesPath, lib, ... }: {

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  services.qemuGuest.enable = true;
  hardware.graphics.enable = true;

  # UTM's "Auto Resolution" (dynamic display resize to follow the VM window)
  # sends the window size to the SPICE guest agent, not to virtio-gpu, whose
  # mode stays at QEMU's 1280x800. The agent can't apply it on Wayland itself;
  # the session agent wrapper in home-manager/custom.nix does. (See UTM docs:
  # guest-support/dynamic-resolution.)
  services.spice-vdagentd.enable = true;

  # Hyprland (0.55.4, still in upstream main as of 2026-10) keeps the previous
  # frame's buffer when testing/committing a new mode if only its format
  # matches. virtio-gpu requires the primary plane to cover the whole CRTC, so
  # every mode change was rejected (atomic: EINVAL; legacy: ENOSPC) and the
  # display never left 1280x800. The patch also requires the size to match.
  nixpkgs.overlays = [
    (_: prev: {
      hyprland = prev.hyprland.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./hyprland-modeset-buffer-size.patch ];
      });
    })
  ];

  # Matches what nixpkgs' virtualisation/disk-image.nix module (used only
  # when building the initial .qcow2 via system.build.images.qemu-efi) sets
  # for its root/ESP partitions. Declared here too so the plain
  # system.build.toplevel used by `nixos-rebuild switch` (e.g. for
  # sup-vm-hyprland's remote deploys) has a root filesystem defined at all -
  # without this it fails NixOS's "fileSystems does not specify your root
  # file system" assertion, since that module isn't part of the base host
  # config. Identical values from both sources merge without conflict
  # (verified directly, not assumed).
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    # The image's diskSize = "auto" leaves only ~512MB free, so the disk is
    # meant to be enlarged in UTM (VM settings -> drive -> Resize). The image
    # module enables growing into that space, but only for the image build;
    # keep it for deployed generations too.
    autoResize = true;
  };
  boot.growPartition = true;

  # The image's ESP is make-disk-image's fixed 256M, and an aarch64 kernel
  # (uncompressed Image) plus initrd is ~90MB, so it holds two kernels. The
  # systemd-boot installer copies the new generation's files before removing
  # old ones: with a limit of 2, two kernel changes in a row need room for
  # three and fail with ENOSPC. Older generations stay in the system profile.
  boot.loader.systemd-boot.configurationLimit = 1;
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  # No camera in a VM. nixos/common/howdy.nix gates its settings, PAM rules
  # and linux-enable-ir-emitter (Intel-only package) on this.
  services.howdy.enable = false;

  # thermald is Intel-only (x86_64/i686-linux); nixos/common/services.nix
  # enables it by default for real hardware.
  services.thermald.enable = false;

}
