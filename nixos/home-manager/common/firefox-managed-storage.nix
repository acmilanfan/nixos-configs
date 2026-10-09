# Firefox extension settings from the exports in dotfiles/, applied on every
# Firefox start through managed-storage files:
#   macOS: ~/Library/Application Support/Mozilla/ManagedStorage/<id>.json
#   Linux: ~/.mozilla/managed-storage/<id>.json
# Unlike enterprise policies this works with the Homebrew Firefox and shows no
# "managed by your organization". Only extensions that read storage.managed:
#   - uBlock Origin: adminSettings (a full backup) is re-applied every launch.
#   - LeechBlock NG (>= 1.7.3): every key given overwrites its local storage.
# So changes made in either extension's UI are reverted on the next start;
# re-export and overwrite dotfiles/ublock/ublock-backup.txt or
# dotfiles/firefox/extensions/LeechBlockOptions.json instead. Vimium C and Dark Reader
# don't read managed storage; they rely on Firefox Sync.
{ pkgs, inputs, ... }:

let
  storageDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/Mozilla/ManagedStorage"
    else
      ".mozilla/managed-storage";

  ublock = builtins.toJSON {
    name = "uBlock0@raymondhill.net";
    description = "uBlock Origin settings managed by nixos-configs";
    type = "storage";
    data.adminSettings = builtins.readFile ../../../dotfiles/ublock/ublock-backup.txt;
  };

  # Adds the compiled block patterns LeechBlock only builds on Save, and drops
  # per-set passwords (see ./firefox/leechblock-managed.js).
  leechblock =
    pkgs.runCommand "leechblockng-managed-storage.json" { nativeBuildInputs = [ pkgs.nodejs ]; }
      ''
        node ${./firefox/leechblock-managed.js} ${inputs.leechblockng}/common.js \
          ${../../../dotfiles/firefox/extensions/LeechBlockOptions.json} > $out
      '';
in
{
  home.file."${storageDir}/uBlock0@raymondhill.net.json".text = ublock;
  home.file."${storageDir}/leechblockng@proginosko.com.json".source = leechblock;
}
