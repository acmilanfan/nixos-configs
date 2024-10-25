{ ... }: {

  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  virtualisation.libvirtd.enable = true;

  users.users.gentooway.extraGroups = [ "docker" "libvirtd" ];

}
