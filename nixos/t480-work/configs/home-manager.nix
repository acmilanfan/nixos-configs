{ ... }: {

  imports = [
    <home-manager/nixos>
  ];

  home-manager.users.ashumailov = import ./../home.nix;

}
