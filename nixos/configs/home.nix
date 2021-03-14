{ ... }: {

  imports =
    [
      ./default.nix
      ./bootloader-home.nix
      ./xserver-wacom.nix
      ./hardware/default.nix
      ./hardware/home.nix
      ./home-manager-home.nix
      ./music.nix
      #./hardware/games.nix
    ];

  networking.hostName = "nixos";

  users.users.andrei = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

}
