{ config, ... }: {

  programs.browserpass = {     
    enable = config.programs.firefox.enable;     
    browsers = [ "firefox" ];   
  };

  home.file.".password-store".source = ../secrets;
  home.file.".password-store".recursive = true;

    # todo migrate once in stable branch
#  programs.password-store = {
#    enable = true;
#    settings = { 
#      PASSWORD_STORE_DIR = "\${HOME}/.config/nixpkgs/secrets"; 
#    };
#  };

}
