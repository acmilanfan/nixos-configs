{ ... }:

let
  secrets = import /home/gentooway/configs/nixos-configs/secrets/secrets.nix;
in {
  programs.git = {
    enable = true;
    userEmail = secrets.homeEmail;
    extraConfig = {
      core = {
        sshCommand = "ssh -i ~/.ssh/id_ed25519 -o 'IdentitiesOnly yes'";
      };
    };
    includes = [
      {
        condition = "gitdir:~/Work/";
        contents = {
          user = {
            email = secrets.workEmail;
            name = "Andrei Shumailov";
          };
          core = {
            sshCommand = "ssh -i ~/.ssh/id_rsa -o 'IdentitiesOnly yes'";
          };
        };
      }
    ];
  };

}
