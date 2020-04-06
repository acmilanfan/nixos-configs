{ ... }: {

  programs.bash = {
    enable = true;
    historyIgnore = [ "ls", "cd", "exit" "tree" ];
    historySize = 50000;
    shellAliases = {
      repass = "PASSWORD_STORE_DIR=$HOME/.config/nixpkgs/secrets pass";
    };
    #initExtra = "";
  };

}
