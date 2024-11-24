{ ... }: {

  imports = [
    ./autorandr.nix
    ./git.nix
    ./custom.nix
    ./../../home-manager/configs/common-ssh.nix
  ];

}
