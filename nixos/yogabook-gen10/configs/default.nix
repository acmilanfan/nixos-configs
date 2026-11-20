{ ... }: {

  imports = [
    ./hardware
    ./env.nix
    ./host.nix
    ./users.nix
    ./ci.nix
  ];

}
