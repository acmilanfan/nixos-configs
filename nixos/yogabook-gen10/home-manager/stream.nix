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

  # OBS_PASSWORD is exported by the sops-rendered ai-env.sh (common/sops.nix).
}
