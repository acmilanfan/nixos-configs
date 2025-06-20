{ pkgs, lib, ... }: {

  boot = {
    initrd.kernelModules = [ "amdgpu" ];
    kernelModules = [ "amdgpu" "tp_smapi" ];
  };

  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = with pkgs; [
    # rocmPackages.clr.icd
    # rocmPackages.rocm-runtime
    rocmPackages.rocm-runtime
    rocmPackages.rocminfo
    amdvlk
    rocmPackages.clr.icd
    vaapiVdpau
    libvdpau-va-gl
    mesa
  ];

  hardware.graphics.extraPackages32 = with pkgs; [ driversi686Linux.amdvlk ];

  environment.variables.AMD_VULKAN_ICD = lib.mkDefault "RADV";

  systemd.tmpfiles.rules =
    [ "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}" ];
}
