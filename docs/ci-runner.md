# Nix-managed CI runner account and daemon

mac-home now creates a hidden, headless `weekenduo-ci` service account and can
run GitLab Runner as a system LaunchDaemon. No GUI login or account password is
needed.

## Account

The module owns:

```nix
users.knownUsers = [ "weekenduo-ci" ];
users.users.weekenduo-ci = {
  uid = 599;
  gid = 20;
  home = "/Users/weekenduo-ci";
  createHome = true;
  isHidden = true;
  description = "Weekenduo local CI runner";
  shell = "/bin/bash";
  packages = [ nodejs_22 go git curl docker colima gitlab-runner ];
};
```

nix-darwin creates it with `sysadminctl -addUser` during activation. It cannot
set a macOS password/SecureToken, so this account is intentionally **hidden and
headless**; it cannot be used for GUI login. If the account is removed from
`users.knownUsers`, nix-darwin can delete the account and home directory.

`users.users.weekenduo-ci.packages` creates the rooted per-user profile at
`/etc/profiles/per-user/weekenduo-ci`, used by runner jobs. Node 22 includes
Corepack; a separate corepack package would conflict.

The account is managed even while `services.ciRunner.enable = false`; only the
runner daemon/config is gated. Change `uid` if `599` conflicts with an existing
account.

## Prerequisites

1. Create one project runner in each GitLab project (`weekenduo/backend` and
   `weekenduo/duomobile`), tagged `weekenduo-laptop-ci`, locked, no untagged
   jobs. Copy the two `glrt-…` tokens.
2. Add them to the encrypted secrets:

   ```yaml
   gitlab_runner:
     backend_token: glrt-…
     frontend_token: glrt-…
   ```

3. Re-wrap the sops data key for the mac-home host age recipient:

   ```sh
   sops updatekeys secrets/secrets.yaml
   ```

   At activation, Nix derives a root-only age key from
   `/etc/ssh/ssh_host_ed25519_key` into `/var/lib/sops-nix/age.key` and sops uses
   that key file. The host key can therefore decrypt the shared secrets file;
   a dedicated age key and separate CI sops file is the stricter alternative.

4. No manual Colima start is needed. The runner's `pre_build_script` starts the
   **dedicated** CI Colima VM on the first job:

   ```sh
   /etc/profiles/per-user/weekenduo-ci/bin/colima status >/dev/null 2>&1 ||
     /etc/profiles/per-user/weekenduo-ci/bin/colima start \
       --cpu 6 --memory 12 --disk 60 --activate=false
   ```

   It then checks the CI Docker socket. The VM stays running between jobs.
   Do **not** point it at the personal `/Users/gentooway/.colima` socket; that
   would let CI jobs control personal containers/images. After the first job,
   record the CI daemon ID in
   `/Users/weekenduo-ci/.config/weekenduo-ci/runtime.json` (see the E2E runbook).

## Enable

Uncomment in `darwin/mac-home.nix`:

```nix
services.ciRunner.enable = true;
```

Rebuild:

```sh
sudo darwin-rebuild switch --flake "$HOME/configs/nixos-configs#mac-home"
```

This installs:

- system LaunchDaemon `org.nixos.local.weekenduo-ci-runner`, running as `weekenduo-ci`
  with `gitlab-runner run`;
- sops-rendered `/Users/weekenduo-ci/.gitlab-runner/config.toml`, owner/mode
  `weekenduo-ci` / `0600`, with two runners, concurrency 1, CI builds/cache,
  Docker/Testcontainers/status environment and an on-demand CI Colima
  `pre_build_script`;
- owned `~/ci-builds`, `~/ci-cache`, `~/ai/artifacts`, `~/Library/Logs` dirs.

No Home Manager user or GUI LaunchAgent is involved. The runner starts at boot
without a login session.

## Verify

```sh
sudo launchctl print system/org.nixos.local.weekenduo-ci-runner
stat -f '%Su %Sp %N' /Users/weekenduo-ci/.gitlab-runner/config.toml
sudo -u weekenduo-ci -H /etc/profiles/per-user/weekenduo-ci/bin/node --version
```

Expected: daemon running, config `weekenduo-ci` `-rw-------`, Node 22. GitLab
should show both runners online. Run a real test job to verify `node`, `go`,
`docker` and the CI Docker daemon.

The Nix store contains only sops placeholders; the decrypted tokens exist only
in the runtime config.

## Disable/rollback

Set `services.ciRunner.enable = false` and rebuild. The system daemon and old
user-agent plist are removed/unloaded; the hidden account and per-user profile
remain. Remove the account only deliberately: delete `users.users.weekenduo-ci`
and `users.knownUsers` entries (or the module import) and rebuild, accepting
home-directory deletion. Do not re-enable the GitLab merge gate.

## Limits

- Headless account only; nix-darwin cannot manage a GUI login password,
  SecureToken or FileVault.
- Runner creation/token issuance is manual; sops stores the issued tokens.
- First CI Colima VM creation happens during the first job and can take a few
  minutes; the VM stays running afterward. Personal Colima is never shared.
- Jobs can still fail before the VM is ready if the host is resource-constrained;
  inspect `colima status` and the runner logs.
- SAST verification, GitLab merge/runner/schedule settings and publication remain
  operator gates.
