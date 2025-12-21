{ pkgs, ... }: {

  home.pointerCursor = {
    x11.enable = true;
    package = pkgs.kdePackages.breeze-gtk;
    name = "breeze_cursors";
    size = 16;
  };

  xsession.enable = true;
}
