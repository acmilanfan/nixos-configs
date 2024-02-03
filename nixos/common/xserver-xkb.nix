{ ... }: {

  services.xserver.xkb = {
    layout = "us,de,ru";
    options = "grp:alt_space_toggle,caps:escape";
  };

}
