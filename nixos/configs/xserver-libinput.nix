{ ... }: {

  services.xserver.libinput = {
    enable = true;
    naturalScrolling = true;
    disableWhileTyping = true;
    horizontalScrolling = true;
  };

  services.xserver.displayManager.sessionCommands = ''
    xinput --set-prop '2.4G Mouse' 'libinput Natural Scrolling Enabled' 0
    xinput --set-prop '2.4G Mouse Mouse' 'libinput Natural Scrolling Enabled' 0
  ''; 
}
