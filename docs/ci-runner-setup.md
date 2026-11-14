# Moving the local CI runner to another Mac

This is the complete operator checklist for moving the laptop GitLab runner to
another Mac, including a dedicated headless CI Mac mini. The runner is a system
LaunchDaemon, so no GUI login is required for CI.

The desktop indicator is separate and currently mac-home-only; a headless CI
mini does not need it.

## 1. Nix host configuration

Add a Darwin host to the flake, or reuse an existing host that imports the CI
module. A minimal host module:

```nix
# darwin/ci-mini.nix
{ ... }:
{
  imports = [
    ./common.nix          # or a minimal equivalent
    ./ci-runner.nix
  ];

  system.primaryUser = "gentooway";
  networking.hostName = "ci-mini";
  services.ciRunner.enable = true;
}
```

```nix
# flake.nix darwinConfigurations
"ci-mini" = mkDarwin {
  system = macSystem;
  darwinModule = ./darwin/ci-mini.nix;
  user = "gentooway";
  homeModule = ./nixos/ci-mini/home.nix;
};
```

`homeModule` is for the normal admin user and can be minimal:

```nix
{ ... }:
{
  home.username = "gentooway";
  home.homeDirectory = "/Users/gentooway";
  home.stateVersion = "26.05";
}
```

The CI account is separate and is created by `darwin/ci-runner.nix`:

```nix
users.knownUsers = [ "weekenduo-ci" ];
users.users.weekenduo-ci = {
  uid = 599;
  gid = 20;
  home = "/Users/weekenduo-ci";
  createHome = true;
  isHidden = true;
  shell = "/bin/bash";
  packages = [ nodejs_22 go git curl docker colima gitlab-runner ];
};
```

It is hidden and headless; no password or GUI login is needed. If UID 599 is
already used on the new machine, override `services.ciRunner.uid`. Removing the
user from `users.knownUsers` allows nix-darwin to delete the account/home.

The flake's `secrets` submodule must be checked out. The normal admin account
used by `system.primaryUser` must already exist and be able to apply a Darwin
rebuild (normally a GUI admin session or Full Disk Access over SSH).

## 2. Add the host age recipient to sops

On the new Mac:

```sh
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
```

Add the resulting public recipient to `.sops.yaml`, alongside the existing
recipients, in every relevant `creation_rules` entry. For example:

```yaml
keys:
  - &admin_gpg F45F0EE88195A11F983842515B3566CDE26D887A
  - &mac_home_age age1m2j...
  - &ci_mini_age age1NEW...

creation_rules:
  - path_regex: secrets/.*\.ya?ml$
    pgp: *admin_gpg
    age: age1m2j...,age1NEW...
```

Then re-wrap the data key from a machine with the admin GPG key:

```sh
sops updatekeys secrets/secrets.yaml
```

Commit the encrypted secrets change and the parent submodule pointer locally,
and publish the encrypted secrets commit to the private submodule remote before
the new host evaluates the flake. Nix fetches submodules by commit SHA.

On activation Nix derives `/var/lib/sops-nix/age.key` from
`/etc/ssh/ssh_host_ed25519_key`; the host key can decrypt the shared secrets
file. A dedicated age key/separate CI secrets file is the stricter alternative.

## 3. GitLab project runners

Create one project runner in each project:

- `weekenduo/backend`
- `weekenduo/duomobile`

Settings:

- tag: `weekenduo-laptop-ci`
- locked to the project
- run untagged jobs: no
- copy each `glrt-…` authentication token

If moving an existing runner, you may reuse its token instead of creating a new
one. Pause or remove the old runner so two hosts do not compete for the same
registration.

Add both tokens to the encrypted secrets:

```yaml
gitlab_runner:
  backend_token: glrt-…
  frontend_token: glrt-…
```

Run `sops updatekeys secrets/secrets.yaml` again after editing the file.

## 4. Isolated Colima runtime

The CI runner uses a dedicated `weekenduo-ci` Colima VM, never the personal
Docker VM. The runner's `pre_build_script` starts the CI VM on demand and fails
closed if Docker is unavailable.

First start, as the service account:

```sh
sudo -u weekenduo-ci -H /bin/bash -c '
set -euo pipefail
export PATH=/etc/profiles/per-user/weekenduo-ci/bin:/usr/bin:/bin:/usr/sbin:/sbin
colima start --cpu 6 --memory 12 --disk 60 --activate=false
export DOCKER_HOST=unix:///Users/weekenduo-ci/.colima/default/docker.sock
docker info --format "{{.ID}}"
'
```

Record the ID. Create the runtime policy:

```sh
sudo -u weekenduo-ci -H /bin/bash -c '
set -euo pipefail
export PATH=/etc/profiles/per-user/weekenduo-ci/bin:/usr/bin:/bin:/usr/sbin:/sbin
export DOCKER_HOST=unix:///Users/weekenduo-ci/.colima/default/docker.sock
id=$(docker info --format "{{.ID}}")
mkdir -p /Users/weekenduo-ci/.config/weekenduo-ci
umask 077
printf "{\n  \"user\": \"weekenduo-ci\",\n  \"home\": \"/Users/weekenduo-ci\",\n  \"dockerSocket\": \"/Users/weekenduo-ci/.colima/default/docker.sock\",\n  \"dockerId\": \"%s\",\n  \"buildRoot\": \"/Users/weekenduo-ci/ci-builds\",\n  \"artifactRoot\": \"/Users/weekenduo-ci/ai/artifacts\"\n}\n" "$id" > /Users/weekenduo-ci/.config/weekenduo-ci/runtime.json
chmod 600 /Users/weekenduo-ci/.config/weekenduo-ci/runtime.json
'
```

This file is intentionally manual: it pins the verified CI daemon ID. The
runtime guard rejects a different daemon, wrong user, unsafe roots, or public
listeners.

## 5. Enable and rebuild

The module is enabled by `services.ciRunner.enable = true` on the new host.
Rebuild:

```sh
sudo darwin-rebuild switch --flake "$HOME/configs/nixos-configs#ci-mini"
```

This creates the hidden account, per-user toolchain profile, sops config copy
daemon and runner LaunchDaemon. Do not rebuild while a CI job is active: the
runner restart interrupts it.

## 6. GitLab settings

### Merge policy

Both projects: **Settings → Merge requests → Pipelines must succeed: OFF**.
Preserve approvals, branch protection and conflict checks. Verify
`only_allow_merge_if_pipeline_succeeds=false`.

### Job-token permissions

Settings → CI/CD → Job token permissions (older GitLab: Token Access):

- `weekenduo/wd-e2e` allows **weekenduo/backend** and **weekenduo/duomobile**.
- `weekenduo/backend` allows **weekenduo/duomobile**.
- `weekenduo/duomobile` allows **weekenduo/backend**.

The pipeline user also needs read access to the private `weekenduo/wd-e2e`
include.

### Schedule

One backend `develop` schedule is sufficient:

- cron `0 3 * * *`
- timezone UTC
- variable `WD_CI_E2E=full`

Do not create a duplicate frontend nightly schedule.

### Publication order

When publishing a suite change:

1. Publish the exact E2E commit.
2. Update both product `include.ref`, `WD_CI_SUITE_SHA` and
   `WD_CI_TEMPLATE_SHA` to that commit.
3. Publish the products.
4. Keep root MR workflow rules in each product root file aligned.

SAST remains fail-closed until an operator verifies the effective analyzers,
pins image digests/platforms and validates the report schema. Do not set
`verified: true` just to make a pipeline green.

## 7. Verify

```sh
sudo launchctl print system/org.nixos.local.weekenduo-ci-runner
sudo launchctl print system/org.nixos.local.weekenduo-ci-config
sudo -u weekenduo-ci /bin/ls -l /Users/weekenduo-ci/.gitlab-runner/config.toml
sudo -u weekenduo-ci /usr/bin/grep -c '^  token = "glrt-' \
  /Users/weekenduo-ci/.gitlab-runner/config.toml
sudo -u weekenduo-ci -H /etc/profiles/per-user/weekenduo-ci/bin/docker info \
  --format '{{.ID}}'
```

Expected:

- runner and config-copy daemons running;
- config is a regular `weekenduo-ci` `-rw-------` file (not a `/run/secrets`
  symlink);
- two tokens;
- Docker ID matches `runtime.json`;
- GitLab shows both runners online;
- a real smoke job succeeds and publishes a status record.

The first job is slower because it starts Colima and installs dependencies.
The VM stays running between jobs.

## 8. Optional desktop indicator

`services.localCiStatus` is separate and currently enabled only on mac-home.
A headless CI mini should not import it. If a GUI Mac also runs jobs, configure
the indicator on that desktop and keep the CI account in the accepted producer
UIDs.

## 9. Sizing and tuning

Measured on the current 14-vCPU/48-GB Mac with the CI VM at 6 vCPU/12 GB:

- CI VM RSS was about 1.5 GB and CPU was low outside Docker-heavy work.
- The bottleneck was host load: Vitest used about 128% of one core, while many
  Spotlight `mdworker` processes indexed `ci-builds` and `node_modules`.
- CI build trees are now marked `.metadata_never_index`; keep those markers.

Recommendations:

- **Do not increase Colima CPU/RAM just because product jobs feel slow.** Product
  builds run on the host; Colima CPU only helps Docker/Supabase work.
- Keep 6 vCPU/12 GB for one job until a full E2E run shows Docker CPU/memory
  pressure (`docker stats`, VM CPU). Then try 8 vCPU/16 GB.
- Dedicated CI Mac mini sizing:
  - 16 GB RAM: 6 vCPU/10 GB VM, 80 GB disk (full E2E may be tight).
  - 24 GB RAM: 8 vCPU/16 GB VM, 100 GB disk.
  - 32-48 GB RAM: 8-10 vCPU/24 GB VM, 150 GB disk.
  - Leave at least 8 GB RAM and 2-4 host CPUs for macOS and the runner.
- Keep `concurrent = 1` unless you deliberately want parallel jobs; the two
  runner registrations are for backend/frontend, not simultaneous capacity.
- For a dedicated mini, keep it awake (energy settings/`pmset`), logged in is
  not required, and monitor disk space; Docker images and source artifacts grow.
- Avoid rebuilding or restarting the runner during a job; cancel/retry it.

## 10. Rollback

Pause both runners in GitLab and disable the schedule. Set
`services.ciRunner.enable = false` and rebuild. The system daemons are removed;
the hidden account and per-user profile remain. Remove `users.knownUsers` only
deliberately, as it can delete the account/home. Do not re-enable the merge
gate unless explicitly requested.
