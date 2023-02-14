{ ... }: {

  imports = [
    <home-manager/nixos>
  ];

  home-manager.users.gentooway = import ./../home.nix;

}
