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
      colors = {
        primary = {
          background = "0x1e2127";
          foreground = "0xabb2bf";
        };
        selection = {
          background = "0x3e4452";
          text = "CellForeground";
        };
        normal = {
          black = "0x2c323c";
          red = "0xe06c75";
          green = "0x98c379";
          yellow = "0xe5c07b";
          blue = "0x61afef";
          magneta = "0xc678dd";
          cyan = "0x56b6c2";
          white = "0xe6efff";
        };
        bright = {
          black = "0x3e4452";
          red = "0xe06c75";
          green = "0x98c379";
          yellow = "0xe5c07b";
          blue = "0x61afef";
          magneta = "0xc678dd";
          cyan = "0x56b6c2";
          white = "0x828791";
        };
      };
    };
  };
}
