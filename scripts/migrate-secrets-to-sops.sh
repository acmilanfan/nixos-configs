#!/usr/bin/env bash
set -euo pipefail

# migrate-secrets-to-sops.sh
# Safely extracts secrets from secrets/secrets.nix and creates an encrypted
# secrets/secrets.yaml using SOPS and your GPG key.
# No secret values are printed to terminal output.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_NIX="$REPO_ROOT/secrets/secrets.nix"
SECRETS_YAML="$REPO_ROOT/secrets/secrets.yaml"
GPG_FINGERPRINT="F45F0EE88195A11F983842515B3566CDE26D887A"

if [ ! -f "$SECRETS_NIX" ]; then
  echo "Error: $SECRETS_NIX not found." >&2
  exit 1
fi

if [ -f "$SECRETS_YAML" ]; then
  echo "Warning: $SECRETS_YAML already exists."
  read -r -p "Overwrite and re-encrypt? [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "==> Converting secrets from $SECRETS_NIX to encrypted $SECRETS_YAML..."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TMP_YAML="$TMP_DIR/unencrypted.yaml"

# Evaluate Nix secrets to JSON and format as YAML for SOPS
nix eval --json --impure --expr "import $SECRETS_NIX" | python3 -c '
import sys, json

try:
    import yaml
except ImportError:
    yaml = None

data = json.load(sys.stdin)

# Schema mapping
secrets = {
    "telegram": {
        "bot_token": (data.get("telegram") or {}).get("bot_token", "REPLACE_WITH_TELEGRAM_BOT_TOKEN"),
        "allowed_user_id": str((data.get("telegram") or {}).get("allowed_user_id", "REPLACE_WITH_ALLOWED_USER_ID")),
    },
    "aiProxy": {
        "claude": data.get("aiProxy", {}).get("claude", ""),
        "openai": data.get("aiProxy", {}).get("openai", ""),
        "mistralCompletion": data.get("aiProxy", {}).get("mistralCompletion", ""),
        "apiKey": data.get("aiProxy", {}).get("apiKey", ""),
        "claudeKey": data.get("aiProxy", {}).get("claudeKey", ""),
        "selfHosted": data.get("aiProxy", {}).get("selfHosted", ""),
        "selfHostedKey": data.get("aiProxy", {}).get("selfHostedKey", ""),
    },
    "github": {
        "token": (data.get("github") or {}).get("token", ""),
    },
    "sonar": {
        "apiKey": (data.get("sonar") or {}).get("apiKey", ""),
        "url": (data.get("sonar") or {}).get("url", ""),
    },
    "mcp": {
        "ragUrl": (data.get("mcp") or {}).get("ragUrl", ""),
        "scorecardUrl": (data.get("mcp") or {}).get("scorecardUrl", ""),
    },
    "syncthing_api_key": str(data.get("syncthing_api_key", "")),
    "obsWebsocketPassword": str(data.get("obsWebsocketPassword", "")),
}

if yaml:
    with open("'"$TMP_YAML"'", "w") as f:
        yaml.dump(secrets, f, default_flow_style=False, sort_keys=False)
else:
    # Pure Python basic YAML dumper if pyyaml is missing
    with open("'"$TMP_YAML"'", "w") as f:
        for k, v in secrets.items():
            if isinstance(v, dict):
                f.write(f"{k}:\n")
                for sub_k, sub_v in v.items():
                    sub_v_str = str(sub_v).replace("\"", "\\\"")
                    f.write(f"  {sub_k}: \"{sub_v_str}\"\n")
            else:
                v_str = str(v).replace("\"", "\\\"")
                f.write(f"{k}: \"{v_str}\"\n")
'

# Encrypt directly with SOPS using the user's GPG key
nix run nixpkgs#sops -- --encrypt --pgp "$GPG_FINGERPRINT" "$TMP_YAML" > "$SECRETS_YAML"
chmod 600 "$SECRETS_YAML"

echo "==> Successfully created and encrypted: $SECRETS_YAML"
echo "==> To inspect or edit decrypted contents at any time:"
echo "    sops $SECRETS_YAML"
