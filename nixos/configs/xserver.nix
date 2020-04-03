{ ... }: {

  imports =
    [ 
      ./xserver-xkb.nix
      ./xserver-libinput.nix
      ./xserver-drivers.nix
      ./xserver-display-manager.nix
    ];

  services.xserver.enable = true;

}
