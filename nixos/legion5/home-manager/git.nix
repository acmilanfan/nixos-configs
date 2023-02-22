{ ... }: 

let 
  secrets = import /home/gentooway/configs/nixos-configs/secrets/secrets.nix;
in {
  programs.git = {
    enable = true;
    userEmail = secrets.homeEmail;
  };

}
