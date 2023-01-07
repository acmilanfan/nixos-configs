{ ... }: {

  programs.rofi = {
    enable = true;
    theme = "purple";
    font = "Roboto Medium 13";
    extraConfig = {
      color-enabled = true;
      sidebar-mode = true;
      show-icons = true;
    };
  };

}
