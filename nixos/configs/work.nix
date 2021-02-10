{ config, pkgs, ... }: {

  imports =
    [ 
      ./default.nix
      ./bootloader-work.nix
      ./hardware/default.nix
      ./hardware/work.nix
      ./home-manager-work.nix
    ];

  networking.hostName = "ashumailov-nixos";

  users.users.ashumailov = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

}
