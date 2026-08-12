{ modulesPath, lib, ... }: {

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  services.qemuGuest.enable = true;
  hardware.graphics.enable = true;

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
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  # No camera in a VM; nixos/common/howdy.nix enables facial-recognition login
  # unconditionally with a hardcoded /dev/video2 path.
  services.howdy.enable = lib.mkForce false;

  # linux-enable-ir-emitter is enabled unconditionally alongside howdy above
  # (not gated on services.howdy.enable) and its package is Intel-only.
  services.linux-enable-ir-emitter.enable = lib.mkForce false;

  # thermald is Intel-only (x86_64/i686-linux); nixos/common/services.nix
  # enables it by default for real hardware.
  services.thermald.enable = false;

  # nixos/common/howdy.nix wires a howdy PAM rule into these services via
  # `lib.mkForce { order = ...; control = ...; modulePath = "${pkgs.howdy}/..."; }`
  # unconditionally, regardless of services.howdy.enable above. Its package
  # isn't Intel/x86-portable (fails to evaluate on aarch64-linux). A plain
  # `.enable = false` here loses to that mkForce (whole-value definitions on
  # an attrsOf-submodule key compete by priority as a unit, not per-leaf), so
  # this needs an equal-or-higher-priority whole-value override instead; once
  # `enable = false` wins, pam.nix filters rules by `.enable` before ever
  # touching `.modulePath`, so pkgs.howdy is never forced. Verified directly
  # against this repo's pinned nixpkgs source, not assumed.
  security.pam.services.hyprlock.rules.auth.howdy = lib.mkOverride 40 { enable = false; };
  security.pam.services.i3lock.rules.auth.howdy = lib.mkOverride 40 { enable = false; };
  security.pam.services.sudo.rules.auth.howdy = lib.mkOverride 40 { enable = false; };
  security.pam.services.login.rules.auth.howdy = lib.mkOverride 40 { enable = false; };

}
