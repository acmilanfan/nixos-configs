{ pkgs, ... }:

{
  imports = [ ./common.nix ];

  system.primaryUser = "gentooway";

  networking.hostName = "mac-home";

  # Lets `nix build` produce aarch64-linux derivations (e.g. the vm-hyprland
  # image) locally via a small aarch64-linux builder VM. Defaults are 1
  # core/3GB/20GB-disk, which is far too small for a full desktop image
  # (crawls on anything with a real test suite e.g. arrow-cpp; a ~2000
  # store-path/20GB+ closure fills the default disk and triggers mid-build
  # GC). This Mac has 14 cores/48GB, so it can afford more of both than
  # mac-work.nix's 11-core/~18GB sizing (which had to cap cores at 4 to avoid
  # OOM-killing heavy Qt/C++ compiles under only 12GB — see that file for the
  # full explanation of why cores/memory need to scale together). Here 8
  # cores x 32GB averages 4GB/job, comfortably above the ~1.5-3GB heavy -O3
  # translation units (e.g. vicinae) can need, while leaving 6 cores/16GB
  # for the host.
  #
  # diskSize/memorySize go through the module's own virtualisation.darwin-builder.*
  # options rather than the generic virtualisation.diskSize/memorySize directly:
  # nixpkgs' nix-builder-vm.nix profile plainly assigns the generic options FROM
  # these, so setting the generic ones directly conflicts with that at equal
  # priority (needs lib.mkForce); setting the upstream darwin-builder.* options
  # is the single source of truth and avoids that fight entirely.
  nix.linux-builder.enable = true;
  nix.linux-builder.config.virtualisation = {
    cores = 8;
    darwin-builder = {
      memorySize = 32768; # MB
      diskSize = 102400; # MB (100GB; qcow2 is sparse, won't eagerly consume this)
    };
  };
}
