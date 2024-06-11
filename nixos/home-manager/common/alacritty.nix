{ ... }: {

  programs.alacritty = {
    enable = true;
    settings = {
      font = { size = 12; };
      selection = { save_to_clipboard = true; };
      colors = {
        primary = {
          background = "#1e2127";
          foreground = "#abb2bf";
        };
        selection = {
          background = "#3e4452";
          text = "CellForeground";
        };
        normal = {
          black = "#2c323c";
          red = "#e06c75";
          green = "#98c379";
          yellow = "#e5c07b";
          blue = "#61afef";
          magenta = "#c678dd";
          cyan = "#56b6c2";
          white = "#e6efff";
        };
        bright = {
          black = "#3e4452";
          red = "#e06c75";
          green = "#98c379";
          yellow = "#e5c07b";
          blue = "#61afef";
          magenta = "#c678dd";
          cyan = "#56b6c2";
          white = "#828791";
        };
      };
    };
  };
}
