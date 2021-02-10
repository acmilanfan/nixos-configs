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
      maven zlib pam gdb 
    ]);
  runScript = "bash";
};
in pkgs.stdenv.mkDerivation {
  name = "maven-shell";
  nativeBuildInputs = [ fhs ];
  shellHook = ''
    export LANG=en_US.UTF-8 
    unset TZ
    exec java-maven-env
  '';
}
