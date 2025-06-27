{ lib, config, pkgs, ... }: {

  environment.variables = {
    NIX_SYSTEM = "yogabook-gen10";
    LAPTOP_MONITOR = "eDP-2";
    WINIT_X11_SCALE_FACTOR = lib.mkForce "1.9";
    QT_SCALE_FACTOR = lib.mkForce "1.9";
    EXTRA_SCREEN_BRIGHTNESS_CMD =
      lib.mkForce "light -s sysfs/backlight/intel_backlight";
  };

  programs.auto-cpufreq.enable = true;
  programs.auto-cpufreq.settings = {
    charger = {
      governor = "performance";
      turbo = "auto";
      energy_performance_preference = "balance_performance";
      platform_profile = "balanced";
    };

    battery = {
      governor = "powersave";
      turbo = "auto";
      ideapad_laptop_conservation_mode = true;
      energy_performance_preference = "power";
      platform_profile = "balanced";
    };
  };
  services.xserver.dpi = lib.mkForce 168;

  # boot.kernelPatches = [{
  #   name = "yoga-book-9i-14IAH10-backlight";
  #   patch = ./NB140B9M-dpcd-backlight-fix.patch;
  # }];

  # boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.linux_6_14.override {
  #   argsOverride = rec {
  #     # disable unwanted drivers
  #     configfile = pkgs.writeText "kernel-config" ''
  #       ${builtins.readFile "${pkgs.linux_6_14}/lib/modules/*/build/.config"}
  #       # disable AMD/Nouveau GPU support
  #       CONFIG_DRM_AMDGPU=n
  #       CONFIG_DRM_RADEON=n
  #       CONFIG_DRM_NOUVEAU=n
  #     '';
  #   };
  # });

  services.hardware.bolt.enable = true;

  hardware.enableRedistributableFirmware = true;

  environment.etc."gdm/Init/Default".text = ''
    #!/bin/bash
    xrandr --output eDP-1 --rotate inverted
  '';
  environment.etc."gdm/Init/Default".mode = "0755";

  # TODO: requires manual refind install: nix-shell -p refind, sudo refind-install
  # TODO: this should go to /boot/EFI/refind/refind.conf
  # environment.etc."EFI/refind/refind.conf".text = ''
  #   enable_touch true
  #   timeout 10
  #   shutdown_after_timeout
  # '';

  services.pulseaudio.support32Bit = true;
  # hardware.enableAllFirmware = true;
  hardware.firmware = with pkgs; [ sof-firmware ];

  environment.etc."systemd/sleep.conf".text = ''
    [Sleep]
    HibernateMode=platform
    HibernateState=disk
    AllowSuspend=false
  '';

  systemd.targets.suspend.wants = [ "hibernate.target" ];

  boot.kernel.sysctl."kernel.debug" = 1;
  boot.kernelParams = [
    "mem_sleep_default=deep"
    "reboot=pci"
    "acpi=noirq"
    "apm=power_off"
    "i915.force_probe=7d51"
  ];
  # "acpi_backlight=video"
  # "acpi_backlight=vendor"
  # "i915.enable_dpcd_backlight=1"
  # "i915.enable_psr=0"
  # "i915.disable_panel_lc_pwm=1"
  # "i915.enable_dpcd_backlight_deferred=1"
  # "drm.debug=0x1e"

  boot.blacklistedKernelModules = [ "hid-multitouch" ];
  # boot.loader.systemd-boot.memtest86.enable = true;

  boot.initrd.kernelModules = [ "ideapad_laptop" ];
  boot.extraModprobeConfig = ''
    options ideapad_laptop allow_v4_dytc=1
  '';

  fileSystems."/sys/kernel/debug" = {
    device = "debugfs";
    fsType = "debugfs";
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  hardware.bluetooth.settings = { General = { Experimental = true; }; };

  # TODO: increase bootloader size and try again for BT on luks password screen
  # boot.initrd.preDeviceCommands = ''
  #   mkdir -p /lib/firmware/intel
  #   cp -v ${pkgs.linux-firmware}/lib/firmware/intel/ibt-0040-0041.sfi /lib/firmware/intel/
  #   cp -v ${pkgs.linux-firmware}/lib/firmware/intel/ibt-0040-0041.ddc /lib/firmware/intel/
  # '';

  hardware.sensor.iio.enable = true;

  services.colord.enable = true;

  environment.systemPackages = with pkgs; [
    i2c-tools
    evsieve
    acpica-tools
    alsa-utils
    intel-gpu-tools
    (writeShellScriptBin "sync-brightness" (lib.readFile ./sync-brightness.sh))
  ];

  services.xserver.videoDrivers = [ "modesetting" ];

  services.power-profiles-daemon.enable = false;
  powerManagement.enable = true;

  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      # vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
      intel-media-driver
    ];
  };

  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="platform", KERNEL=="VPC2004:00", RUN+="/bin/sh -c 'echo 1 > /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode'"
  '';
}
