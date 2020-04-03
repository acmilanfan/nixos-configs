{ ... }: {

  imports =
    [
      ./default.nix
      ./xserver-wacom.nix
      ./hardware/default.nix
      ./hardware/home.nix
    ];

  networking.hostName = "nixos";

  users.users.andrei = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

}
