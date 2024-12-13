{ pkgs, lib, config, ... }: {

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia.powerManagement.enable = false;

  environment.systemPackages = with pkgs; [
    cudatoolkit
  ];

  hardware.graphics.extraPackages = with pkgs; [
    rocm-opencl-icd
    rocm-opencl-runtime
    amdvlk
  ];

  hardware.graphics.extraPackages32 = with pkgs; [
    driversi686Linux.amdvlk
  ];

  environment.variables.AMD_VULKAN_ICD = lib.mkDefault "RADV";

}
