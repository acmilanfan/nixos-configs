{ pkgs, ... }: {
  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        # decorations = "none";
      };
      font = {
        size = 16;
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

      # Key bindings to handle Control/Command swap for terminal applications (Darwin/macOS only)
      # keyboard = pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
      #   bindings = [
      #     # Map Command+[A-Z] to send Control+[A-Z] for terminal applications
      #     { key = "A"; mods = "Command"; chars = "\\u0001"; } # Ctrl+A
      #     { key = "B"; mods = "Command"; chars = "\\u0002"; } # Ctrl+B
      #     # { key = "C"; mods = "Command"; chars = "\\u0003"; } # Ctrl+C
      #     { key = "D"; mods = "Command"; chars = "\\u0004"; } # Ctrl+D
      #     { key = "E"; mods = "Command"; chars = "\\u0005"; } # Ctrl+E
      #     { key = "F"; mods = "Command"; chars = "\\u0006"; } # Ctrl+F
      #     { key = "G"; mods = "Command"; chars = "\\u0007"; } # Ctrl+G
      #     { key = "H"; mods = "Command"; chars = "\\u0008"; } # Ctrl+H
      #     { key = "I"; mods = "Command"; chars = "\\u0009"; } # Ctrl+I
      #     { key = "J"; mods = "Command"; chars = "\\u000A"; } # Ctrl+J
      #     { key = "K"; mods = "Command"; chars = "\\u000B"; } # Ctrl+K
      #     { key = "L"; mods = "Command"; chars = "\\u000C"; } # Ctrl+L
      #     { key = "M"; mods = "Command"; chars = "\\u000D"; } # Ctrl+M
      #     { key = "N"; mods = "Command"; chars = "\\u000E"; } # Ctrl+N
      #     { key = "O"; mods = "Command"; chars = "\\u000F"; } # Ctrl+O
      #     { key = "P"; mods = "Command"; chars = "\\u0010"; } # Ctrl+P
      #     # { key = "Q"; mods = "Command"; chars = "\\u0011"; } # Ctrl+Q
      #     { key = "R"; mods = "Command"; chars = "\\u0012"; } # Ctrl+R
      #     { key = "S"; mods = "Command"; chars = "\\u0013"; } # Ctrl+S
      #     { key = "T"; mods = "Command"; chars = "\\u0014"; } # Ctrl+T
      #     { key = "U"; mods = "Command"; chars = "\\u0015"; } # Ctrl+U
      #     # { key = "V"; mods = "Command"; chars = "\\u0016"; } # Ctrl+V
      #     { key = "W"; mods = "Command"; chars = "\\u0017"; } # Ctrl+W
      #     { key = "X"; mods = "Command"; chars = "\\u0018"; } # Ctrl+X
      #     { key = "Y"; mods = "Command"; chars = "\\u0019"; } # Ctrl+Y
      #     { key = "Z"; mods = "Command"; chars = "\\u001A"; } # Ctrl+Z
      #   ];
      # };
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
