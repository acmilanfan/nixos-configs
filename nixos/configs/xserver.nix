{ ... }: {

  imports =
    [ 
      ./xserver-xkb.nix
      ./xserver-libinput.nix
      ./xserver-drivers.nix
      ./xserver-display-manager.nix
    ];
  
  services.xserver.displayManager.sessionCommands = ''
    xinput --set-prop '2.4G Mouse' 'libinput Natural Scrolling Enabled' 0
    xinput --set-prop '2.4G Mouse Mouse' 'libinput Natural Scrolling Enabled' 0  

    setwacom --set "Wacom HID 50F8 Finger touch" MapToOutput eDP1
    setwacom --set "Wacom HID 50F8 Pen stylus" MapToOutput eDP1
    setwacom --set "Wacom HID 50F8 Pen eraser" MapToOutput eDP1
  '';

  services.xserver.enable = true;

}
