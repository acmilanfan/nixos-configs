{ ... }: {

  services.acpid = {
    enable = true;
    lidEventCommands = ''
      export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH
      export DISPLAY=":1"
      export XAUTHORITY="/run/user/1001/gdm/Xauthority"
      if grep -q open /proc/acpi/button/lid/LID/state; then
        xrandr --output eDP1 --auto
        autorandr --change
      else
        xrandr --output eDP1 --off
      fi
    '';
  };

}
