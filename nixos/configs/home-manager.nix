{ ... }: {

  imports = [
    <home-manager/nixos>
  ];

  home-manager.users.andrei = import ./../../home-manager/home.nix;

}
