{ pkgs, ... }: {
  
  sound.enable = true;
  hardware.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
    extraModules = [ pkgs. pulseaudio-modules-bt ];
  };

  nixpkgs.config.pulseaudio = true;

}
