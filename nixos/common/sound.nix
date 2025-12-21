{ pkgs, ... }: {

  services.pulseaudio = {
    enable = false;
    extraModules = [ pkgs.pulseaudio-modules-bt ];
  };

  services.pipewire = {
    enable = true;
    package = pkgs.pipewire;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
    pulse.enable = true;
    socketActivation = true;

    extraConfig = {
      pipewire = { "context.properties" = { "bluez5.autoswitch" = false; }; };
    };
    wireplumber.extraConfig = {
      "51-alsa-volume-fix.conf" = {
        "monitor.alsa.rules" = [{
          matches = [{
            "node.name" =
              "alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink";
          }];
          actions = {
            "apply-properties" = {
              # Our original, correct strategy:
              # Use "Speaker" as the main control...
              "api.alsa.volume.element" = "Speaker";

              # ...and link "Bass Speaker" to it.
              "api.alsa.slave-volumes.elements" = [ "Bass Speaker" ];
            };
          };
        }];
      };
      "policy.bluez" = { "bluez5.autoswitch-profile" = false; };
    };
  };

  security.rtkit.enable = true;

  environment.systemPackages = with pkgs; [ pamixer pulseaudioFull ];

}
