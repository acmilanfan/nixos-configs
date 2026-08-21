{ ... }: {

  # Mounts the host Mac's ~/configs/nixos-configs directly, via UTM's VirtFS
  # (9p) directory sharing, so the VM uses the exact same git working tree
  # as the host instead of a separate clone. "share" is UTM's fixed VirtFS
  # mount tag for this feature (not something we choose) - see UTM.sdef's
  # "qemu directory share mode" documentation. The actual host folder to
  # share isn't scriptable (GUI-only: VM Settings -> Sharing -> pick
  # ~/configs/nixos-configs, with Directory Share Mode set to VirtFS).
  #
  # nofail: don't hang/fail boot if the share isn't attached (e.g. sharing
  # not yet configured in UTM, or booting for image-build purposes where no
  # VirtFS device exists at all).
  fileSystems."/home/gentooway/configs/nixos-configs" = {
    device = "share";
    fsType = "9p";
    options = [ "trans=virtio" "version=9p2000.L" "msize=104857600" "rw" "nofail" ];
  };

}
