{ ... }: {

  programs.rofi = {
    enable = true;
    theme = "purple";
    extraConfig = ''
      rofi.color-enabled: true
      rofi.sidebar-mode: true
      rofi.show-icons: true
    '';
  };

}
