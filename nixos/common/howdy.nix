{ config, pkgs, lib, ... }:

{
  services.howdy = {
    enable = true;
    package = pkgs.howdy;
    settings = {
      core = {
        no_face_timeout = 10;
        detection_notice = false;
      };
      video = {
        device_path = "/dev/video2"; # Common path for IR cameras, adjust if needed (e.g., /dev/video0)
        dark_threshold = 50;
        # resolution = "640x480"; # Some IR cameras need specific resolution
      };
    };
  };

  # Help enable the IR emitter if the camera has one and it's not active by default
  services.linux-enable-ir-emitter.enable = true;

  # Manually configure PAM rules since we aren't using fufexan's PAM module
  security.pam.services = let
    howdyRule = {
      order = 10; # Low order to run before pam_unix
      control = "sufficient";
      modulePath = "${pkgs.howdy}/lib/security/pam_howdy.so";
    };
  in {
    hyprlock.rules.auth = {
      howdy = howdyRule;
    };
    i3lock.rules.auth = {
      howdy = howdyRule;
    };
    sudo.rules.auth = {
      howdy = howdyRule;
    };
    login.rules.auth = {
      howdy = howdyRule;
    };
  };
}
