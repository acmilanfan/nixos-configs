{ config, ... }: {

  #home.file.".password-store".source = /home/ashumailov/configs/nixos-configs/secrets;
  #home.file.".password-store".recursive = true;

  # todo make it work
  #programs.password-store = {
  #  enable = true;
  #  settings = { 
  #    PASSWORD_STORE_DIR = "/home/andrei/configs/secrets"; 
  #  };
  #};

}
