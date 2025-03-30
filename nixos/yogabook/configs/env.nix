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

  services.hardware.bolt.enable = true;

  hardware.enableRedistributableFirmware = true;
  # hardware.enableAllFirmware = true;
  # nixpkgs.config.allowUnfree = true;

  environment.etc."gdm/Init/Default".text = ''
    #!/bin/bash
    xrandr --output eDP-1 --rotate inverted
  '';
  environment.etc."gdm/Init/Default".mode = "0755";
  # environment.etc."EFI/refind/refind_x64.efi".text = ''
  #   ln -s ${pkgs.refind}/lib/efi/boot/refind_x64.efi
  # '';

  # environment.etc."EFI/refind/refind.conf".text = ''
  #   DEFAULT=systemd-bootx64.efi
  #   enable_touch true
  #   timeout 20
  #   shutdown_after_timeout
  # '';

  environment.etc."systemd/sleep.conf".text = ''
    [Sleep]
    HibernateMode=platform
    HibernateState=disk
    AllowSuspend=false
  '';

  systemd.targets."shutdown.target".unitConfig = {
    ExecStop = [ "/run/current-system/sw/bin/systemctl reboot" ];
  };

  boot.kernelParams = [
    "mem_sleep_default=deep"
    # "pci=noacpi"
    # "rtc_cmos.use_acpi_alarm=1"
    # "libdata.force=noacpi"
    # "pcie_aspm=force"
    "acpi=noirq"
    "reboot=pci"
    "shutdown=pci"
    "pcie_aspm.policy=powersupersave"
    "i915.force_probe=a7a1"
  ];

  boot.blacklistedKernelModules = [ "hid-multitouch" ];

  # boot.initrd.availableKernelModules = [ "btusb" "bluetooth" "hidp" ];
  # boot.initrd.kernelModules = [ "ideapad_laptop" "btusb" ];
  boot.initrd.kernelModules = [ "ideapad_laptop" ];
  boot.extraModprobeConfig = ''
    options snd-intel-dspcfg dsp_driver=1
    options snd-hda-intel model=alc287-yoga9-bass-spk-pin
    options ideapad_laptop allow_v4_dytc=1
  '';

  # options snd-sof-intel-hda-common hda_model=alc287-yoga9-bass-spk-pin
  # boot.initrd.extraUtilsCommands = ''
  #   copy_bin_and_libs ${pkgs.bluez}/bin/bluetoothctl
  #   copy_bin_and_libs ${pkgs.bluez}/bin/hcitool
  #   copy_bin_and_libs ${pkgs.bluez}/bin/hcidump
  # '';
  # boot.initrd.postMountCommands = ''
  #   ${pkgs.bluez}/bin/bluetoothctl connect 00:1B:66:F9:6B:1E
  # '';

  #   echo "Starting Bluetooth..."
  #   mkdir -p /var/run/dbus
  #   ${pkgs.dbus}/bin/dbus-daemon --system
  #   ${pkgs.bluez}/bin/bluetoothd --nodetach &
  #   sleep 2
  #
  # options snd_hda_intel model=auto
  # options snd slots=snd-hda-intel
  # options snd_intel_dspcfg dsp_driver=1 rtw89_pci disable_clkreq=y disable_aspm_l1=y disable_aspm_l1ss=y

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  hardware.bluetooth.settings = { General = { Experimental = true; }; };

  # TODO: increase bootloader size and try again
  # boot.initrd.preDeviceCommands = ''
  #   mkdir -p /lib/firmware/intel
  #   cp -v ${pkgs.linux-firmware}/lib/firmware/intel/ibt-0040-0041.sfi /lib/firmware/intel/
  #   cp -v ${pkgs.linux-firmware}/lib/firmware/intel/ibt-0040-0041.ddc /lib/firmware/intel/
  # '';

  # hardware.firmware = with pkgs; [ linux-firmware sof-firmware alsa-firmware ];

  # hardware.firmware = [ pkgs.linux-firmware ];

  # boot.initrd.preLVMCommands = ''
  #   echo "Waiting for firmware..."
  #   sleep 2
  #   modprobe btusb
  #   sleep 2
  #   ${pkgs.bluez}/bin/bluetoothd --nodetach &
  #   sleep 2
  #   ${pkgs.bluez}/bin/bluetoothctl connect 00:1B:66:F9:6B:1E
  # '';

  hardware.sensor.iio.enable = true;

  environment.systemPackages = with pkgs; [
    i2c-tools
    evsieve
    acpica-tools
    (writeShellScriptBin "sync-brightness" (lib.readFile ./sync-brightness.sh))
  ];

  services.xserver.videoDrivers = [ "modesetting" ];

  services.power-profiles-daemon.enable = false;
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

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="platform", KERNEL=="VPC2004:00", RUN+="/bin/sh -c 'echo 1 > /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode'"
  '';

  # ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="INGENIC Gadget Serial and keyboard Touchscreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 0.5 0 0 0 1"
  #
  # KERNEL=="event*", ATTRS{name}=="INGENIC Gadget Serial and keyboard Touchscreen", SYMLINK+="input/touchscreen_top"
  # KERNEL=="event*", ATTRS{name}=="INGENIC Gadget Serial and keyboard Touchscreen", SYMLINK+="input/touchscreen_bottom"

  # SUBSYSTEM=="backlight", ACTION=="change", KERNEL=="intel_backlight", RUN+="${
  #   pkgs.writeShellScriptBin "sync-brightness"
  #   (lib.readFile ./sync-brightness.sh)
  # }"

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
