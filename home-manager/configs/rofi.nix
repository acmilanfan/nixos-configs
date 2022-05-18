{ ... }: {

  programs.rofi = {
    enable = true;
    theme = "purple";
    extraConfig = {
      color-enabled = true;
      sidebar-mode = true;
      show-icons = true;
    };
  };

}
