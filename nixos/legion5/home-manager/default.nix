{ ... }: {

  imports = [
    ./autorandr.nix
    ./git.nix
    ./music.nix
    ./stream.nix
    ./../../home-manager/configs/common-ssh.nix
  ];

}
