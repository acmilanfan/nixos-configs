# Linux CI runner runbook

This is the operator checklist for the two NixOS GitLab runners
(`yogabook-gen10` and `t480-home`). They run alongside the existing macOS
runner. This iteration covers `develop` and merge requests only; `main` is
out of scope.

## Scope and safety

- Route A: the Linux runners join the existing `weekenduo-laptop-ci` pool.
  The Mac runner stays registered and online as fallback.
- `weekenduo-laptop-full` is an extra tag for `e2e-full` and
  `e2e-full-manual`. Initially it belongs to the Mac and yogabook only.
- t480 starts with the common tag and runs product checks + smoke only. It
  gets the full tag only after a measured manual full run passes.
- Both projects must keep **Settings → Merge requests → Pipelines must
  succeed OFF**. Pending jobs must not block merges.
- Keep the existing backend `develop` schedule (`0 3 * * *`, UTC,
  `WD_CI_E2E=full`). Do not add a frontend nightly schedule.
- Do not disable hosted/shared runners in this iteration. The job tag is what
  routes work to the local runners.
- Do not run untrusted fork code on these shell runners. Shell jobs execute
  repository and dependency scripts as `weekenduo-ci`, and Docker group
  membership is effectively root-equivalent.
- The CI Docker daemon is **CI-only**. Supabase CLI teardown performs a
  Docker-wide prune; never point these jobs at personal containers.
- No administrative API tokens enter the worker environment.

## Prerequisites

1. GitLab project owner (or maintainer with runner rights) access to
   `weekenduo/backend` and `weekenduo/duomobile`.
2. The job-token allowlists:
   - `weekenduo/wd-e2e` allows `weekenduo/backend` and `weekenduo/duomobile`.
   - `weekenduo/backend` allows `weekenduo/duomobile`.
   - `weekenduo/duomobile` allows `weekenduo/backend`.
3. The pipeline user can read the private `weekenduo/wd-e2e` include.
4. The Mac runner is online and healthy before starting.
5. The suite commit containing the Linux runtime changes has been published
   first; the product `include.ref`, `WD_CI_SUITE_SHA` and
   `WD_CI_TEMPLATE_SHA` all name that same full SHA.

## Activate a host

From the nixos-configs checkout:

```sh
cd ~/configs/nixos-configs
sudo nixos-rebuild switch --flake .#yogabook-gen10
# later, after yogabook is green:
sudo nixos-rebuild switch --flake .#t480-home
```

The module creates the `weekenduo-ci` account (uid 599), enables Docker with
`data-root = /home/docker`, and starts the `weekenduo-ci-runner.service` unit.
The service fails until the token file exists. Do not rebuild or restart the
runner while a job is active; the service gets a seven-minute graceful stop,
but the job may still need a retry.

## Create the GitLab runners

Create two **project-scoped** runners per host:

| Host | Project | Description | Tags |
| --- | --- | --- | --- |
| yogabook | `weekenduo/backend` | `weekenduo-yogabook-backend` | `weekenduo-laptop-ci`, `weekenduo-laptop-full` |
| yogabook | `weekenduo/duomobile` | `weekenduo-yogabook-frontend` | `weekenduo-laptop-ci`, `weekenduo-laptop-full` |
| t480 | `weekenduo/backend` | `weekenduo-t480-backend` | `weekenduo-laptop-ci` |
| t480 | `weekenduo/duomobile` | `weekenduo-t480-frontend` | `weekenduo-laptop-ci` |

For every runner:

- Lock it to the current project.
- Disable “Run untagged jobs”.
- Do not add it to other projects.
- Copy the `glrt-…` authentication token; it is shown once.

Add `weekenduo-laptop-full` to both existing Mac runners in GitLab. Do not
change their tokens or their Nix configuration.

## Token file

Create the root-only credential file on each host:

```sh
sudo install -d -m 0750 -o root -g root /etc/weekenduo-ci
sudo install -m 0600 -o root -g root /dev/null /etc/weekenduo-ci/runner.env
sudoedit /etc/weekenduo-ci/runner.env
```

Content:

```sh
BACKEND_TOKEN=glrt-...
FRONTEND_TOKEN=glrt-...
```

The service reads the file through systemd `LoadCredential`; the generated
config is written to `/run/weekenduo-ci/config.toml` (mode 0600, owned by
`weekenduo-ci`). Never put these tokens in Git, the Nix store, the home
directory, job arguments, or logs.

### Automated token setup

After the host configuration is active, the helper can install both tokens
without hand-editing a root file:

```sh
sudo weekenduo-ci-set-tokens
```

It prompts without echo, validates both `glrt-` tokens, writes
`/etc/weekenduo-ci/runner.env` atomically as `root:root` mode 0600, and
restarts `weekenduo-ci-runner`. It still requires both project runners to
exist; a missing or malformed token is rejected.

Start and inspect the service:

```sh
sudo systemctl enable --now weekenduo-ci-runner
sudo systemctl status weekenduo-ci-runner
sudo journalctl -u weekenduo-ci-runner -n 50 --no-pager
```

## Record the Docker policy

The runtime guard pins the Docker daemon ID. Run the helper as the CI user:

```sh
sudo -u weekenduo-ci -H /etc/profiles/per-user/weekenduo-ci/bin/weekenduo-ci-record-docker
sudo -u weekenduo-ci -H cat /home/weekenduo-ci/.config/weekenduo-ci/runtime.json
```

Expected shape:

```json
{
  "user": "weekenduo-ci",
  "home": "/home/weekenduo-ci",
  "dockerSocket": "/var/run/docker.sock",
  "dockerId": "<live daemon id>",
  "buildRoot": "/home/weekenduo-ci/ci-builds",
  "artifactRoot": "/home/weekenduo-ci/ai/artifacts"
}
```

The policy must be a regular file owned by `weekenduo-ci`, mode 0600. If the
Docker daemon is replaced, jobs fail closed until the helper is rerun.

## Verify

```sh
systemctl status weekenduo-ci-runner
sudo -u weekenduo-ci -H /etc/profiles/per-user/weekenduo-ci/bin/node --version
sudo -u weekenduo-ci -H /etc/profiles/per-user/weekenduo-ci/bin/go version
sudo -u weekenduo-ci -H /etc/profiles/per-user/weekenduo-ci/bin/cypress --version
sudo -u weekenduo-ci -H /etc/profiles/per-user/weekenduo-ci/bin/docker info --format '{{.ID}}'
sudo -u weekenduo-ci -H /etc/profiles/per-user/weekenduo-ci/bin/gitlab-runner verify --config /run/weekenduo-ci/config.toml
```

Expected: Node 22, Cypress 13.17.0, both runners online with the expected
tags. The first product job also runs
`node .ci-work/suite/scripts/ci/runtime.mjs --check` in its before-script;
confirm that passes rather than bypassing it.

## Force Linux validation

The Mac and Linux runners share the common tag, so GitLab may choose either.
To prove the Linux route:

1. Pause the Mac runners in GitLab (and the other Linux runner when testing
   t480).
2. Run a backend `develop` pipeline: `format`, `vet`, `race-tests`, `sast`.
3. Run a frontend `develop` pipeline: `secret-scan`, `unit-tests`,
   `web-build`.
4. Run `e2e-smoke` from both projects.
5. Run one manual `e2e-full` on yogabook.
6. Confirm the job logs name `weekenduo-yogabook-*` or
   `weekenduo-t480-*`, and inspect the `.ci-artifacts` manifest.
7. Unpause the Mac (and the other Linux runner).

Record job URLs, the suite SHA, runner names, Cypress version, Docker ID and
wall times under `~/ai/artifacts/weekenduo-ci/`. Do not record tokens.

## t480 full-run decision

t480 has 4 cores / 8 threads. It starts without the full tag.

1. Temporarily add `weekenduo-laptop-full` to both t480 runners.
2. Pause the Mac and yogabook runners.
3. Run a manual `e2e-full` from backend.
4. Record wall time, lane timings, Cypress retries/flakes, peak load/RAM and
   free disk.
5. If it is green and the wall time is acceptable, keep the tag. Otherwise
   remove it and leave the nightly on Mac/yogabook.
6. Never raise t480 `concurrent` above 1 without a product-check + smoke
   measurement showing headroom.

## t480 power

- Keep t480 on AC.
- `keepAwake = true` ignores lid close and idle suspend through logind.
- Check the desktop session’s own power settings too; GNOME can override
  logind. If the session still suspends on AC, leave the lid open.
- There is no auto-wake in this iteration. Jobs queue while a host sleeps.

## Token rotation and runner maintenance

- Rotate: edit `/etc/weekenduo-ci/runner.env`, then
  `sudo systemctl restart weekenduo-ci-runner`. Confirm both runners
  reconnect.
- Pause: use GitLab’s “Pause runner”, not a service stop, for planned
  scheduling pauses.
- Stop: `sudo systemctl stop weekenduo-ci-runner`. Do not stop Docker while a
  job is active.
- Rebuild/runner restart: wait for active jobs or accept a retry. The service
  gets a seven-minute graceful stop.

## Rollback

1. Pause the Linux runners in GitLab and stop
   `weekenduo-ci-runner.service`.
2. If the new suite is at fault, revert the two product `develop` pins to
   `cfc28f931f16d2c129956da37aac8f34754595d4`.
3. Keep the Mac runners online; they are the fallback.
4. Do not re-enable the merge gate.
5. Do not delete the Linux account, Docker data, or artifacts until the
   rollback is understood.
6. If the CI Docker daemon must be cleaned, do it only with no active job and
   only against the CI daemon.

## Do not

- Do not use a personal Docker daemon or personal containers for these jobs.
- Do not put admin API tokens in the worker environment.
- Do not change `main` in this iteration.
- Do not re-enable “Pipelines must succeed”.
- Do not run untrusted fork code on these runners.
