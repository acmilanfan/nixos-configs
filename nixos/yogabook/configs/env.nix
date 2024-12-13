{ lib, config, pkgs, ... }: {

  environment.variables = {
    NIX_SYSTEM = "yogabook";
    LAPTOP_MONITOR = "eDP-2";
    WINIT_X11_SCALE_FACTOR = lib.mkForce "1.9";
    EXTRA_SCREEN_BRIGHTNESS_CMD =
      lib.mkForce "light -s sysfs/backlight/intel_backlight";
  };

  services.xserver.dpi = lib.mkForce 168;

  hardware.enableRedistributableFirmware = true;

  boot.kernelParams = [
    "mem_sleep_default=deep"
    # "pci=noacpi"
    # "rtc_cmos.use_acpi_alarm=1"
    # "libdata.force=noacpi"
    # "pcie_aspm=force"
    "acpi=noirq"
    "reboot=acpi"
    "pcie_aspm.policy=powersupersave"
    "i915.force_probe=a7a1"
  ];

  boot.initrd.kernelModules = [ "ideapad_laptop" ];
  boot.extraModprobeConfig = ''
    options snd-intel-dspcfg dsp_driver=1
    options snd-sof-intel-hda-common hda_model=alc287-yoga9-bass-spk-pin
    options ideapad_laptop allow_v4_dytc=1
  '';

  # options snd_hda_intel model=auto
  # options snd slots=snd-hda-intel
  # options snd_intel_dspcfg dsp_driver=1 rtw89_pci disable_clkreq=y disable_aspm_l1=y disable_aspm_l1ss=y

  hardware.bluetooth.enable = true;
  services.pipewire.alsa.enable = true;
  hardware.sensor.iio.enable = true;

  environment.systemPackages = with pkgs; [
    alsa-firmware
    sof-firmware
    i2c-tools
    (writeShellScriptBin "sync-brightness" (lib.readFile ./sync-brightness.sh))
  ];

  services.xserver.videoDrivers = [ "modesetting" ];

  services.power-profiles-daemon.enable = true;
  powerManagement.enable = true;
  # powerManagement.cpuList = [ ]; # Disable CPU frequency scaling
  # powerManagement.batteryPercentageLow = 5; # Set low battery threshold

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

  # services.udev.extraRules = ''
  #   SUBSYSTEM=="backlight", ACTION=="change", KERNEL=="intel_backlight", RUN+="${pkgs.writeShellScriptBin "sync-brightness" (lib.readFile ./sync-brightness.sh)}"
  # '';

  # services.udev.extraRules = ''
  #   SUBSYSTEM=="backlight", ACTION=="change", KERNEL=="intel_backlight", RUN+="${
  #     pkgs.writeShellScriptBin "adjust-brightness" ''
  #       light -s sysfs/backlight/card1-eDP-2-backlight -U 5
  #     ''
  #   }"
  # '';

  # services.xserver.wacom.enable = true;
  # TODO: do proper map to screen with xrandr and rotate top screen upside down
  services.xserver.displayManager.sessionCommands = ''
    # xinput set-prop "12" --type=float "Coordinate Transformation Matrix" 1 0 0 0 0.5 0 0 0 1
    # xinput set-prop "9" --type=float "Coordinate Transformation Matrix" 1 0 0 0 0.5 0 0 0 1
    # xinput set-prop "10" --type=float "Coordinate Transformation Matrix" 1 0 0 0 0.5 0 0 0 1
    # xinput set-prop "22" --type=float "Coordinate Transformation Matrix" 1 0 0 0 0.5 0.5 0 0
    # xinput set-prop "25" --type=float "Coordinate Transformation Matrix" 1 0 0 0 0.5 0.5 0 0
  '';
}
