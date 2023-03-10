{ pkgs ? import <nixpkgs> 
  { overlays = [ (self: super: {
      jdk = super.jetbrains.jdk;
    }) ];
  } 
}:

let fhs = pkgs.buildFHSUserEnv {
  name = "java-maven-env";
  targetPkgs = pkgs: (with pkgs;
    [
      maven zlib pam gdb xorg.libXext xorg.libX11 xorg.libXrender xorg.libXtst xorg.libXi freetype gradle libaio numactl ncurses5
    ]);
  runScript = "bash";
};
in pkgs.stdenv.mkDerivation {
  name = "maven-shell";
  nativeBuildInputs = [ fhs ];
  shellHook = ''
    export LANG=en_US.UTF-8 
    export TZ=Europe/Berlin
    exec java-maven-env
  '';
}
