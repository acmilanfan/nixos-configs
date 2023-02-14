{ config, pkgs, lib, ... }: {

  services.xserver.videoDrivers = [ "intel" ];

    # extract vaapi.nix
  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  };

  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
      intel-media-driver
    ];
  };

  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.kernelParams = [
    "nouveau.modeset=0"
    "i915.enable_fbc=1"
    "i915.enable_psr=0"
  ];
}
