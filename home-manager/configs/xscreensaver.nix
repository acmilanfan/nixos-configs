{ ... }: {

  services.xscreensaver = {
    enable = true;
    settings = {
      mode = "blank";
      lock = true; 
      fadeSeconds = 10;
      lockTimeout = 10;
    };
  };

}
