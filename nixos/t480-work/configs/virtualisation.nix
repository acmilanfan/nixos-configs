{ ... }: {

  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  virtualisation.libvirtd.enable = true;

  users.users.ashumailov.extraGroups = [ "docker" "libvirtd" ];

}
