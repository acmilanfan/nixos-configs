{ ... }: {

  programs.alacritty = {
    enable = true;
    settings = {
      font = { size = 12; };
      selection = { save_to_clipboard = true; };
      colors = {
        primary = {
          background = "#1a1b26";
          foreground = "#c0caf5";
        };
        selection = {
          background = "#3e4452";
          text = "CellForeground";
        };
        normal = {
          black = "#15161e";
          red = "#f7768e";
          green = "#9ece6a";
          yellow = "#e0af68";
          blue = "#7aa2f7";
          magenta = "#bb9af7";
          cyan = "#7dcfff";
          white = "#a9b1d6";
        };
        bright = {
          black = "#414868";
          red = "#9ece6a";
          green = "#98c379";
          yellow = "#e0af68";
          blue = "#7aa2f7";
          magenta = "#bb9af7";
          cyan = "#7dcfff";
          white = "#c0caf5";
        };
        indexed_colors = [
          {
            index = 16;
            color = "#ff9e64";
          }
          {
            index = 17;
            color = "#db4b4b";
          }
        ];
      };
    };
  };
}
