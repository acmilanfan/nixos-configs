{ ... }: {

  programs.alacritty = {
    enable = true;
    settings = {
      key_bindings = [{
        key = "I";
        mods = "Control";
        chars = "\\x1b[105;5u";
      }];
      font = { size = 12; };
      selection = { save_to_clipboard = true; };
      # colors = {
      #   primary = {
      #     background = "0x1f1f28";
      #     foreground = "0xdcd7ba";
      #   };
      #   normal = {
      #     black = "0x090618";
      #     red = "0xc34043";
      #     green = "0x76946a";
      #     yellow = "0xc0a36e";
      #     blue = "0x7e9cd8";
      #     magenta = "0x957fb8";
      #     cyan = "0x6a9589";
      #     white = "0xc8c093";
      #   };
      #   bright = {
      #     black = "0x727169";
      #     red = "0xe82424";
      #     green = "0x98bb6c";
      #     yellow = "0xe6c384";
      #     blue = "0x7fb4ca";
      #     magenta = "0x938aa9";
      #     cyan = "0x7aa89f";
      #     white = "0xdcd7ba";
      #   };
      #   selection = {
      #     background = "0x2d4f67";
      #     foreground = "0xc8c093";
      #   };
      #   indexed_colors = [
      #     {
      #       index = 16;
      #       color = "0xffa066";
      #     }
      #     {
      #       index = 17;
      #       color = "0xff5d62";
      #     }
      #   ];
      # };
      colors = {
        primary = {
          background = "#192330";
          foreground = "#cdcecf";
          dim_foreground = "#aeafb0";
          bright_foreground = "#d6d6d7";
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
        selection = {
          text = "#cdcecf";
          background = "#2b3b51";
        };
        cursor = {
          text = "#cdcecf";
          cursor = "#aeafb0";
        };
        vi_mode_cursor = {
          text = "#cdcecf";
          cursor = "#63cdcf";
        };
        search = {
          matches = {
            background = "#cdcecf";
            foreground = "#81b29a";
          };
        };
        footer_bar = {
          text = "#cdcecf";
          cursor = "#29394f";
        };
        hints = {
          start = {
            background = "#cdcecf";
            foreground = "#f4a261";
          };
          end = {
            background = "#cdcecf";
            foreground = "#29394f";
          };
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
