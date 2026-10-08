{ secrets, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.email = secrets.homeEmail;
    };
  };

}
