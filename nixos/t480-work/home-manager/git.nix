{ ... }: 

let 
  secrets = import /home/ashumailov/configs/nixos-configs/secrets/secrets.nix;
in {
  programs.git = {
    enable = true;
    userEmail = secrets.workEmail;
  };

}
