{ ... }: {

  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        size = 15;
      };
      selection = {
        save_to_clipboard = true;
      };
    };
  }; 

}
