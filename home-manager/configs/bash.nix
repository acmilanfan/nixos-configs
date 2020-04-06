{ ... }: {

  programs.bash = {
    enable = true;
    historyIgnore = [ "ls", "cd", "exit" "tree" ];
    historySize = 50000;
  };

}
