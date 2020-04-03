{ config, pkgs, ... }: {

  imports =
    [ 
      ./default.nix
      ./hardware/default.nix
      ./hardware/work.nix
    ];

  networking.hostName = "ashumailov-nixos";

  users.users.ashumailov = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

}
