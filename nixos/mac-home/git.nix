{ secrets, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.email = secrets.homeEmail;
      core = {
        sshCommand = "ssh -i ~/.ssh/id_ed25519 -o 'IdentitiesOnly yes'";
      };
    };
  };

}
