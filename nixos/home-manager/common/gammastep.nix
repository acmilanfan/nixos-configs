{ config, ... }:
{
  # Disabled: replaced by hyprsunset (see brightness-ctl.sh).
  # Night mode not yet ported — hyprsunset lacks automatic scheduling.
  services.gammastep.enable = false;
}
