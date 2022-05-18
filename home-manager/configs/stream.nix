{ pkgs, ... }: 
let
  obs = pkgs.wrapOBS {
    plugins = with pkgs.obs-studio-plugins; [
      obs-websocket
    ];
  };
  secrets = import ./../../secrets/secrets.nix;
in {
  home.packages = with pkgs; [
    obs
    (callPackage ./obs-cli.nix {})
    xdotool
    #obs-wlrobs
    #obs-v4l2sink
    v4l-utils
    #nur.repos.jakobrs.obs-studio-wayland
    #nur.repos.jakobrs.obs-xdg-portal
    ffmpeg-full
    kdenlive
    blender
    gimp
    discord
    drawio
  ];

  systemd.user.sessionVariables = {
    OBS_PASSWORD = secrets.obsWebsocketPassword;
  };
}
