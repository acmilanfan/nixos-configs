{ config, ... }:
{
  # Disabled: replaced by the hyprsunset service, which only handles the
  # night tint. Brightness is controlled by the DPCD hardware backlight.
  services.gammastep.enable = false;
}
