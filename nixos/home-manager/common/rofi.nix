{ pkgs, ... }: {

  home.packages = with pkgs; [
    rofi-power-menu
    rofi-pulse-select
    rofi-systemd
    rofi-bluetooth
  ];

  programs.rofi = {
    enable = true;
    theme = "purple";
    font = "Roboto Medium 13";
    terminal = "\${pkgs.alacritty}/bin/alacritty";
    plugins = with pkgs; [
      rofi-calc
      rofi-emoji
      rofi-top
    ];
    extraConfig = {
      color-enabled = true;
      sidebar-mode = true;
      show-icons = true;
      kb-row-up = "Up,Control+k,Shift+Tab";
      kb-row-down = "Down,Control+j";
      kb-mode-next = "Shift+Right,Control+Tab,Control+l";
      kb-mode-previous = "Shift+Left,Control+Shift+Tab,Control+h";
      kb-remove-to-eol = "Control+Shift+e";
      kb-accept-entry = "Control+m,Return,KP_Enter";
      kb-remove-char-back = "BackSpace,Shift+BackSpace";
      kb-mode-complete = "";
    };
  };

}
