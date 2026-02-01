{ pkgs, ... }: {
  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        decorations = "Buttonless";
      };
      font = {
        size = if pkgs.stdenv.isDarwin then 16 else 13;
        normal = {
          family = "RobotoMono Nerd Font";
          style = "Medium";
        };
        bold = {
          family = "RobotoMono Nerd Font";
          style = "Bold";
        };
        italic = {
          family = "RobotoMono Nerd Font";
          style = "Medium Italic";
        };
      };
      selection = { save_to_clipboard = true; };

      colors = {
        primary = {
          background = "#1a1b26";
          foreground = "#cdcecf";
          dim_foreground = "#aeafb0";
          bright_foreground = "#d6d6d7";
        };
        # cursor = {
        #   text = "#cdcecf";
        #   cursor = "#aeafb0";
        # };
        vi_mode_cursor = {
          text = "#cdcecf";
          cursor = "#63cdcf";
        };
        search = {
          matches = {
            foreground = "#cdcecf";
            background = "#3c5372";
          };
          focused_match = {
            foreground = "#cdcecf";
            background = "#81b29a";
          };
        };
        footer_bar = {
          foreground = "#cdcecf";
          background = "#29394f";
        };
        hints = {
          start = {
            foreground = "#cdcecf";
            background = "#f4a261";
          };
          end = {
            foreground = "#cdcecf";
            background = "#29394f";
          };
        };
        selection = {
          text = "#cdcecf";
          background = "#2b3b51";
        };
        normal = {
          black = "#393b44";
          red = "#c94f6d";
          green = "#81b29a";
          yellow = "#dbc074";
          blue = "#719cd6";
          magenta = "#9d79d6";
          cyan = "#63cdcf";
          white = "#dfdfe0";
        };
        bright = {
          black = "#575860";
          red = "#d16983";
          green = "#8ebaa4";
          yellow = "#e0c989";
          blue = "#86abdc";
          magenta = "#baa1e2";
          cyan = "#7ad5d6";
          white = "#e4e4e5";
        };
        dim = {
          black = "#30323a";
          red = "#ab435d";
          green = "#6e9783";
          yellow = "#baa363";
          blue = "#6085b6";
          magenta = "#8567b6";
          cyan = "#54aeb0";
          white = "#bebebe";
        };
        indexed_colors = [
          {
            index = 16;
            color = "#f4a261";
          }
          {
            index = 17;
            color = "#d67ad2";
          }
        ];
      };
    };
  };
}
