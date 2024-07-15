{ pkgs, lib, ... }: {

  boot.kernelModules = [ "amdgpu" ];

  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;
  hardware.opengl.extraPackages = with pkgs; [
    rocm-opencl-icd
    rocm-opencl-runtime
    amdvlk
    rocmPackages.clr.icd
  ];

  hardware.opengl.extraPackages32 = with pkgs; [ driversi686Linux.amdvlk ];

  environment.variables.AMD_VULKAN_ICD = lib.mkDefault "RADV";

}
