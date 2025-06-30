{ ... }: {

  imports = [
    ./hardware
    ./env.nix
    ./host.nix
    ./users.nix
    ./virtualisation.nix
  ];

}
