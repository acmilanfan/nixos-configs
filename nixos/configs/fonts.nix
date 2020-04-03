{ pkgs, lib, ... }: {

  fonts.fonts = with pkgs; [
    corefonts
    fira-code
    font-awesome
    hack-font
    source-code-pro
    roboto
    roboto-mono
  ];

  fonts.fontconfig.defaultFonts.monospace = [ "Roboto Mono" ];

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "corefonts"
  ];

}
