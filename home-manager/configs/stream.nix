{ pkgs, ... }: {

  home.packages = with pkgs; [
    obs-studio
    #obs-wlrobs
    obs-v4l2sink
    #nur.repos.jakobrs.obs-studio-wayland
    #nur.repos.jakobrs.obs-xdg-portal
    ffmpeg-full
  ];

}
