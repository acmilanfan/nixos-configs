{ pkgs, ... }:

{
  imports = [ ./common.nix ];

  system.primaryUser = "andreishumailov";

  networking.hostName = "mac-work";

  # Lets `nix build` produce aarch64-linux derivations (e.g. the vm-hyprland
  # image) locally via a small aarch64-linux builder VM. Defaults to 1
  # core/3GB/20GB-disk, which is far too small for building a full desktop
  # image (crawls on anything with a real test suite e.g. arrow-cpp; a ~2000
  # store-path/20GB+ closure fills the default disk and triggers mid-build
  # GC). This Mac has 11 cores/~18GB/244GB free, so give the builder more
  # room while leaving headroom for the host.
  #
  # cores is intentionally 4, not 8: ninja (used by heavy Qt/C++ packages
  # like vicinae) spawns one compile job per core by default, and Qt-heavy
  # -O3 translation units can each need 1.5-3GB — 8-way parallelism OOM-killed
  # cc1plus under only 12GB. 4 cores x up to 3GB fits comfortably; trades some
  # wall-clock speed for not crashing the build.
  #
  # diskSize/memorySize go through the module's own virtualisation.darwin-builder.*
  # options rather than the generic virtualisation.diskSize/memorySize directly:
  # nixpkgs' nix-builder-vm.nix profile plainly assigns the generic options FROM
  # these, so setting the generic ones directly conflicts with that at equal
  # priority (needs lib.mkForce); setting the upstream darwin-builder.* options
  # is the single source of truth and avoids that fight entirely.
  nix.linux-builder.enable = true;
  nix.linux-builder.config.virtualisation = {
    cores = 4;
    darwin-builder = {
      memorySize = 12288; # MB
      diskSize = 102400; # MB (100GB; qcow2 is sparse, won't eagerly consume this)
    };
  };
}
