{ ... }: 

let 
  secrets = import /home/gentooway/configs/nixos-configs/secrets/secrets.nix;
in {
  programs.git = {
    enable = true;
    userEmail = secrets.homeEmail;
    userName = "Andrei Shumailov";
    includes = [
      {
        condition = "gitdir:~/Work/**";
        contents = {
          user = {
            email = secrets.workEmail;
            name = "Andrei Shumailov";
          };
        };
      }
    ];
  };

}
