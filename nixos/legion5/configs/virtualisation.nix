{ ... }: {

  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;

  users.users.gentooway.extraGroups = [ "docker" "libvirtd" ];

}