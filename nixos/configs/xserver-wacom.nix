{ ... }: {

  services.xserver.wacom.enable = true;

  services.xserver.displayManager.sessionCommands = ''
    setwacom --set "Wacom HID 50F8 Finger touch" MapToOutput eDP1
    setwacom --set "Wacom HID 50F8 Pen stylus" MapToOutput eDP1
    setwacom --set "Wacom HID 50F8 Pen eraser" MapToOutput eDP1
  '';
}
