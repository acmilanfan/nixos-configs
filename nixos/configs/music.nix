{ pkgs, musnix, ... }: {

  environment.systemPackages = with pkgs; [ pavucontrol qjackctl carla libjack2 jack2 jack_capture ];

  services.tlp.enable = false;
  security.sudo.extraConfig = ''
    gentooway  ALL=(ALL) NOPASSWD: ${pkgs.systemd}/bin/systemctl
  '';

  musnix = {
    enable = true;

    #kernel.optimize = true;
    #kernel.realtime = true;
    #alsaSeq.enable = true;

    #soundcardPciId = "00:1f.3";

    #rtirq = {
    #  # highList = "snd_hrtimer";
    #  resetAll = 1;
    #  prioLow = 0;
    #  enable = true;
    #  nameList = "rtc0 snd";
    #};
  };
  #services.jack = {
  #  jackd.enable = true;
  #  jackd.extraOptions = [
  #    "-dalsa" "--device=hw:0"
  #  ];
  #};


  services.pipewire = {
    enable = true;
    wireplumber.enable = true;

    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;

    extraConfig = {
      pipewire = {
        "context.properties" = {
          "bluez5.autoswitch" = false;
        };
      };
    };
    wireplumber.extraConfig = {
      "policy.bluez" = {
        "bluez5.autoswitch-profile" = false;
      };
    };
  };

  users.users.gentooway.extraGroups = [ "jackaudio" "audio" ];
}


