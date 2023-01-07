{ pkgs, ... }: {

  qt5 = {
    enable = true;
    platformTheme = "qt5ct";
  };

  environment.systemPackages = with pkgs; [
    libsForQt5.breeze-qt5
    libsForQt5.breeze-icons
  ];

}
