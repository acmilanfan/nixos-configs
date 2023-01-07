{ pkgs, ... }: {

  home.pointerCursor = {
    x11.enable = true;
    package = pkgs.libsForQt5.breeze-gtk;
    name = "breeze_cursors";
    size = 16;
  };

  xsession.enable = true;
}
