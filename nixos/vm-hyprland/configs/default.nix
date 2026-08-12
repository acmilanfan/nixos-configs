{ ... }: {

  imports = [
    ./hardware
    ./host.nix
    ./users.nix
    ./env.nix
    ./ssh.nix
  ];

}
