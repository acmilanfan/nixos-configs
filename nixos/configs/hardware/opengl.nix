{ config, pkgs, lib, ... }: {

  # extract vaapi.nix
  #nixpkgs.config.packageOverrides = pkgs: {
  #  vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  #};

  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      #vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
      #intel-media-driver
    ];
  };
  #environment.sessionVariables.LIBVA_DRIVER_NAME = "radeonsi";

  #hardware.cpu.intel.updateMicrocode =
  #  lib.mkDefault config.hardware.enableRedistributableFirmware;

}
