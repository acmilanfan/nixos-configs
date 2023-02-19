{ pkgs, ... }:

let
  doom-emacs = pkgs.callPackage (builtins.fetchTarball {
    url = https://github.com/nix-community/nix-doom-emacs/archive/master.tar.gz;
  }) {
    doomPrivateDir = ./../../../dotfiles/doom.d;
  };
in {
  home.packages = [ doom-emacs ];
  services.emacs = {
    enable = true;
    package = doom-emacs;
  };
}
