{ ... }: 

let 
  secrets = import ./../../secrets/secrets.nix;
in {
  programs.git = {
    enable = true;
    userEmail = secrets.workEmail;
  };

}
