{ ... }: {

  services.libinput.enable = true;

  services.libinput.touchpad = {
    naturalScrolling = true;
    disableWhileTyping = true;
    horizontalScrolling = true;
  };

}
