{ ... }: {
  
  imports = [
    ./../common
    ./configs
    ./../configs/music.nix
    <nixos-hardware/common/cpu/amd>
    <nixos-hardware/common/pc/laptop>
    <nixos-hardware/common/pc/laptop/ssd>
  ];

  system.stateVersion = "22.11";

}
