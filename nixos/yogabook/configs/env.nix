{ lib, config, pkgs, ... }: {

  environment.variables = {
    NIX_SYSTEM = "yogabook";
    LAPTOP_MONITOR = "eDP-2";
    WINIT_X11_SCALE_FACTOR = lib.mkForce "1.9";
    EXTRA_SCREEN_BRIGHTNESS_CMD =
      lib.mkForce "light -s sysfs/backlight/intel_backlight";
  };

  programs.auto-cpufreq.enable = true;
  programs.auto-cpufreq.settings = {
    charger = {
      governor = "performance";
      turbo = "auto";
    };

    battery = {
      governor = "powersave";
      turbo = "auto";
    };
  };
  # services.xserver.dpi = lib.mkForce 168;

  # boot.kernelPatches = [{
  #   name = "yoga-book-9i-sound-fix";
  #   patch = ./yoga-book-9i-audio-fix.patch;
  # }];

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

  hardware.pulseaudio.support32Bit = true;
  # hardware.enableAllFirmware = true;
  hardware.firmware = with pkgs; [ sof-firmware ];

  environment.etc."systemd/sleep.conf".text = ''
    [Sleep]
    HibernateMode=reboot
    HibernateState=disk
    AllowSuspend=false
  '';

  systemd.targets.shutdown.wants = [ "reboot.target" ];
  systemd.targets.suspend.wants = [ "hibernate.target" ];

  boot.kernelParams = [
    "mem_sleep_default=deep"
    "acpi=noirq"
    "apm=power_off"
    "reboot=pci"
    "i915.force_probe=a7a1"
  ];

  boot.blacklistedKernelModules = [ "hid-multitouch" ];

  boot.initrd.kernelModules = [ "ideapad_laptop" ];
  boot.extraModprobeConfig = ''
    options ideapad_laptop allow_v4_dytc=1
  '';

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

  environment.systemPackages = with pkgs; [
    i2c-tools
    evsieve
    acpica-tools
    alsa-utils
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
