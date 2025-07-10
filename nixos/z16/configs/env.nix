{ ... }:

let secrets = import /home/gentooway/configs/nixos-configs/secrets/secrets.nix;
in {
  environment.variables = {
    NIX_SYSTEM = "z16";
    LAPTOP_MONITOR = "eDP";
    AI_PROXY_CLAUDE = secrets.aiProxy.claude;
    AI_PROXY_OPENAI = secrets.aiProxy.openai;
    AI_PROXY_MISTRAL = secrets.aiProxy.mistralCompletion;
    AI_API_KEY = secrets.aiProxy.apiKey;
  };

}
