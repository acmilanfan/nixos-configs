{ config, pkgs, lib, ... }: {

  services.xserver.videoDrivers = [ "intel" ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      (intel-vaapi-driver.override { enableHybridCodec = true; })
      libva-vdpau-driver
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
