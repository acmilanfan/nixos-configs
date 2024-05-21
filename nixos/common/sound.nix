{ pkgs, ... }: {
  
  sound.enable = true;
  hardware.pulseaudio = {
    enable = false;
    extraModules = [ pkgs.pulseaudio-modules-bt ];
  };

  services.pipewire = {
    enable = true;
    package = pkgs.pipewire;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
    pulse.enable = true;
    socketActivation = true;
  };

  security.rtkit.enable = true;

  environment.systemPackages = with pkgs; [
    pamixer
    pulseaudioFull
  ];

}
