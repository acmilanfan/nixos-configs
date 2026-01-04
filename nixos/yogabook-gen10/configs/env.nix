{ lib, config, pkgs, ... }: {

  environment.variables = {
    NIX_SYSTEM = "yogabook-gen10";
    LAPTOP_MONITOR = "eDP-2";
    WINIT_X11_SCALE_FACTOR = lib.mkForce "1.9";
    QT_SCALE_FACTOR = lib.mkForce "1.9";
    EXTRA_SCREEN_BRIGHTNESS_CMD =
      lib.mkForce "light -s sysfs/backlight/intel_backlight";
  };

  services.auto-cpufreq.enable = true;
  services.auto-cpufreq.settings = {
    charger = {
      governor = "performance";
      turbo = "auto";
      energy_performance_preference = "performance";
      platform_profile = "performance";
    };
    # charger = {
    #   governor = "performance";
    #   turbo = "auto";
    #   energy_performance_preference = "balance_performance";
    #   platform_profile = "balanced";
    # };

    battery = {
      governor = "powersave";
      turbo = "auto";
      ideapad_laptop_conservation_mode = true;
      energy_performance_preference = "power";
      platform_profile = "balanced";
    };
  };
  services.xserver.dpi = lib.mkForce 168;
  services.libinput.enable = true;

  services.xserver = {
    enable = true;

    # inputClassSections = [
    #   ''
    #     Section "InputClass"
    #       Identifier "Top touchscreen"
    #       MatchProduct "INGENIC Gadget Serial and keyboard Touchscreen Top"
    #       Driver "libinput"
    #       Option "TransformationMatrix" "1 0 0 0 0.5 0 0 0 1"
    #       # Maps input to top half of the combined screen
    #     EndSection
    #   ''
    #   ''
    #     Section "InputClass"
    #       Identifier "Bottom touchscreen"
    #       MatchProduct "INGENIC Gadget Serial and keyboard Touchscreen Bottom"
    #       Driver "libinput"
    #       Option "TransformationMatrix" "1 0 0 0 0.5 0.5 0 0 1"
    #       # Maps input to bottom half of the combined screen
    #     EndSection
    #   ''
    # ''
    #   Section "InputClass"
    #     Identifier "Top touchscreen"
    #     MatchProduct "INGENIC Gadget Serial and keyboard Touchscreen Top"
    #     MatchIsTouchscreen "on"
    #     Driver "libinput"
    #     Option "CalibrationMatrix" "1 0 0 0 1 0 0 0 1"
    #   EndSection
    # ''
    # ''
    #   Section "InputClass"
    #     Identifier "Top stylus"
    #     MatchProduct "INGENIC Gadget Serial and keyboard Stylus Top"
    #     MatchIsTablet "on"
    #     Driver "libinput"
    #   EndSection
    # ''
    # ''
    #   Section "InputClass"
    #     Identifier "Bottom touchscreen"
    #     MatchProduct "INGENIC Gadget Serial and keyboard Touchscreen Bottom"
    #     MatchIsTouchscreen "on"
    #     Driver "libinput"
    #     Option "CalibrationMatrix" "1 0 0 0 1 0 0 0 1"
    #   EndSection
    # ''
    #     ''
    #       Section "InputClass"
    #         Identifier "Bottom stylus"
    #         MatchProduct "INGENIC Gadget Serial and keyboard Stylus Bottom"
    #         MatchIsTablet "on"
    #         Driver "libinput"
    #       EndSection
    #     ''
    #     ''
    #       Section "InputClass"
    #         Identifier "Ignore keyboard"
    #         MatchProduct "INGENIC Gadget Serial and keyboard Keyboard"
    #         Option "Ignore" "on"
    #       EndSection
    #     ''
    #     ''
    #       Section "InputClass"
    #         Identifier "Ignore touchpad"
    #         MatchProduct "INGENIC Gadget Serial and keyboard Emulated Touchpad"
    #         Option "Ignore" "on"
    #       EndSection
    #     ''
    #   ];
  };

  boot.kernelPatches = [{
    name = "yoga-book-9i-fix";
    patch = ./yogabook9i-hid.patch;
  }
  # {
  #   name = "yoga-book-9i-touch-fix";
  #   patch = ./yb9i-gen10-touch-fix2.patch;
  # }
    ];

  hardware.enableRedistributableFirmware = true;
  hardware.enableAllFirmware = true;

  services.hardware.bolt.enable = true;
  # TODO: requires manual refind install: nix-shell -p refind, sudo refind-install
  # TODO: this should go to /boot/EFI/refind/refind.conf
  # environment.etc."EFI/refind/refind.conf".text = ''
  #   enable_touch true
  #   timeout 10
  #   shutdown_after_timeout
  # '';

  services.pulseaudio.support32Bit = true;

  nixpkgs.config.allowUnfree = true;
  # hardware.enableAllFirmware = true;
  hardware.firmware = with pkgs; [ linux-firmware sof-firmware ];

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
    "apm=power_off"
    "xe.enable_dpcd_backlight=2"
    "xe.force_probe=7d51"
    "i915.force_probe=!7d51"
    "video=eDP-1:panel_orientation=upside_down"
  ];

  # TODO: add psr support
  # "pci=biosirq"
  # "acpi=noirq"
  # "i915.force_probe=7d51"
  # "i915.enable_dpcd_backlight=2"
  boot.blacklistedKernelModules = [ "simpledrm" ];
  # boot.blacklistedKernelModules = [ "hid-multitouch simpledrm" ];
  # boot.blacklistedKernelModules = [ "hid-multitouch simpledrm efifb" ];
  boot.initrd.kernelModules = [ "xe ideapad_laptop i2c-dev" ];
  boot.extraModprobeConfig = ''
    options ideapad_laptop allow_v4_dytc=1
  '';

  fileSystems."/sys/kernel/debug" = {
    device = "debugfs";
    fsType = "debugfs";
  };

  # environment.etc."wireplumber/alsa-monitor.conf.d/51-dualmaster.conf".text = ''
  #   rules = [
  #     {
  #       matches = [
  #         { "node.name" = "~alsa_output.*" }
  #       ]
  #       apply-properties = {
  #         "api.alsa.use-acp" = true
  #         "api.alsa.mixer-name" = "DualMaster"
  #       }
  #     }
  #   ]
  # '';

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

  hardware.i2c.enable = true;
  environment.systemPackages = with pkgs; [
    alsa-ucm-conf
    i2c-tools
    evsieve
    acpica-tools
    alsa-utils
    intel-gpu-tools
    linux-firmware
    libinput
    (writeShellScriptBin "sync-brightness" (lib.readFile ./sync-brightness.sh))
    (writeShellScriptBin "set-sync-brightness"
      (lib.readFile ./set-sync-brightness.sh))
    (writeShellScriptBin "restore-sync-brightness"
      (lib.readFile ./restore-sync-brightness.sh))
    (writeShellScriptBin "adjust-sync-brightness"
      (lib.readFile ./adjust-sync-brightness.sh))
  ];

  services.xserver.videoDrivers = [ "modesetting" ];

  services.power-profiles-daemon.enable = false;
  powerManagement.enable = true;

  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };

    # Trims down the kernel by disabling drivers for hardware we don't have.
    # This should result in faster kernel builds.
    linux_latest = pkgs.linux_latest.overrideAttrs (old: {
      extraConfig = (old.extraConfig or "") + ''
        CONFIG_DRM_AMDGPU=n
        CONFIG_DRM_RADEON=n
        CONFIG_DRM_NOUVEAU=n
      '';
    });
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      # vaapiIntel
      libva-vdpau-driver
      libvdpau-va-gl
      intel-media-driver
    ];
  };

  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  # SUBSYSTEM=="input", ATTRS{bInterfaceNumber}=="03", ENV{ID_INPUT_TOUCHSCREEN}="1"
  # ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="INGENIC Gadget Serial and keyboard", ATTRS{phys}=="usb-0000:00:14.0-6/input3", ENV{ID_INPUT_TOUCHSCREEN}="1"
  services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="platform", KERNEL=="VPC2004:00", RUN+="/bin/sh -c 'echo 1 > /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode'"
        ACTION=="add", SUBSYSTEM=="hid", ATTR{idVendor}=="17ef", ATTR{idProduct}=="6161", RUN+="/bin/sh -c 'echo %k > /sys/bus/hid/drivers/hid-generic/unbind; echo %k > /sys/bus/hid/drivers/hid-multitouch/bind'"
        ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Touchscreen Top", ENV{LIBINPUT_DEVICE_GROUP}="group_top", ENV{CUSTOM_ID}="touch_top", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1 0 0 1"
        ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Stylus Top", ENV{LIBINPUT_DEVICE_GROUP}="group_top", ENV{CUSTOM_ID}="tablet_top", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1 0 0 1"
        ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Touchscreen Bottom", ENV{LIBINPUT_DEVICE_GROUP}="group_bottom", ENV{CUSTOM_ID}="touch_bottom"
        ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Stylus Bottom", ENV{LIBINPUT_DEVICE_GROUP}="group_bottom", ENV{CUSTOM_ID}="tablet_bottom"
        ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Keyboard", ENV{LIBINPUT_IGNORE_DEVICE}="1"
        ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Emulated Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="17ef", ATTR{idProduct}=="6161", ATTR{power/control}="on"
  '';

  # services.udev.extraRules = ''
  #   ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Touchscreen Top", ENV{LIBINPUT_DEVICE_GROUP}="group_top"
  #   ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Stylus Top", ENV{LIBINPUT_DEVICE_GROUP}="group_top"
  #   ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Touchscreen Bottom", ENV{LIBINPUT_DEVICE_GROUP}="group_bottom"
  #   ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Stylus Bottom", ENV{LIBINPUT_DEVICE_GROUP}="group_bottom"
  #   ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Keyboard", ENV{LIBINPUT_IGNORE_DEVICE}="1"
  #   ACTION=="add", SUBSYSTEM=="input", ATTRS{name}=="INGENIC Gadget Serial and keyboard Emulated Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
  # '';

}
