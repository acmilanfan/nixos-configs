{ pkgs, ... }:
let
  obs = pkgs.wrapOBS {
    plugins = with pkgs.obs-studio-plugins; [
      obs-pipewire-audio-capture
      obs-vkcapture
      obs-move-transition
      obs-multi-rtmp
    ];
  };
  secrets = import /home/gentooway/configs/nixos-configs/secrets/secrets.nix;
in {
  home.packages = with pkgs; [
    obs
    # (callPackage ./obs-cli.nix {})
    xdotool
    v4l-utils
    ffmpeg-full
    gimp
    discord
    drawio
    davinci-resolve-studio
  ];

  systemd.user.sessionVariables = {
    OBS_PASSWORD = secrets.obsWebsocketPassword;
  };
}
