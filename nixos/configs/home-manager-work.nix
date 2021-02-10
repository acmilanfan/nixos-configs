{ ... }: {

  imports = [
    <home-manager/nixos>
  ];

  home-manager.users.ashumailov = import ./../../home-manager/home.nix;

}
