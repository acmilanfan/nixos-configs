{ pkgs, lib, ... }: {

  boot = {
    initrd.kernelModules = [ "amdgpu" ];
    kernelModules = [ "amdgpu" ];
  };

  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = with pkgs; [
    # rocmPackages.clr.icd
    # rocmPackages.rocm-runtime
    rocmPackages_5.rocm-runtime
    rocmPackages_5.rocminfo
    amdvlk
    rocmPackages_5.clr.icd
  ];

  hardware.graphics.extraPackages32 = with pkgs; [ driversi686Linux.amdvlk ];

  environment.variables.AMD_VULKAN_ICD = lib.mkDefault "RADV";

  systemd.tmpfiles.rules =
    [ "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages_5.clr}" ];
}
