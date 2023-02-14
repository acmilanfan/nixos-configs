{ ... }: {

  imports = [
    ./hardware
    ./env.nix
    ./home-manager.nix
    ./host.nix
    ./users.nix
  ];

}
