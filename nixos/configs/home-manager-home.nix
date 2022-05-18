{ ... }: {

  imports = [
    <home-manager/nixos>
  ];

  home-manager.users.gentooway = import ./../../home-manager/home.nix;

}
