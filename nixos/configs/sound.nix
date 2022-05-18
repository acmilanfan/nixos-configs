{ pkgs, ... }: {
  
  sound.enable = true;
  hardware.pulseaudio = {
    enable = false;
    extraModules = [ pkgs. pulseaudio-modules-bt ];
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
    pulse.enable = true;
    socketActivation = true;
  };

    environment.systemPackages = with pkgs; [ pamixer ];

}
