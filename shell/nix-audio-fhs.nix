{ pkgs ? import <nixpkgs> 
  { overlays = [ (self: super: {
      #jdk = super.jetbrains.jdk;
    }) ];
  } 
}:

let fhs = pkgs.buildFHSUserEnv {
  name = "audio-fhs-env";
  targetPkgs = pkgs: (with pkgs;
    [
       
    ]);
  runScript = "bash";
};
in pkgs.stdenv.mkDerivation {
  name = "audio-shell";
  nativeBuildInputs = [ fhs ];
  shellHook = ''
    export LANG=en_US.UTF-8 
    unset TZ
    exec audio-fhs-env
  '';
}
