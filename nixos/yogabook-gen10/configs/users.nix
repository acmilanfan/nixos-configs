{ ... }: {

  users.users.gentooway = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" "uinput" ];
  };

}
