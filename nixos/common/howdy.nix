{ config, pkgs, lib, ... }:

{
  config = lib.mkMerge [
    {
      # Hosts without a camera (vm-hyprland) set this to false; everything
      # else in this module is gated on it.
      services.howdy.enable = lib.mkDefault true;
    }

    (lib.mkIf config.services.howdy.enable {
      services.howdy = {
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

      # services.howdy.enable turns on nixpkgs' own PAM integration, which
      # adds howdy as `required` to every PAM service (polkit, su, sshd, ...):
      # those then need a face match as well as a password, and fail outright
      # over SSH or with the lid closed. Disable it and add howdy only to the
      # services below, as `sufficient` (the password still works).
      security.pam.howdy.enable = false;

      security.pam.services = let
        howdyRule = {
          order = 10; # Low order to run before pam_unix
          control = "sufficient";
          modulePath = "${pkgs.howdy}/lib/security/pam_howdy.so";
        };
      in {
        hyprlock.rules.auth = {
          howdy = lib.mkForce howdyRule;
        };
        i3lock.rules.auth = {
          howdy = lib.mkForce howdyRule;
        };
        sudo.rules.auth = {
          howdy = lib.mkForce howdyRule;
        };
        login.rules.auth = {
          howdy = lib.mkForce howdyRule;
        };
      };
    })
  ];
}
