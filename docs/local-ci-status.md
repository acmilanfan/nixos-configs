# Local CI/E2E status on mac-home

This optional SketchyBar indicator reports **observed activity on this laptop**,
not GitLab queue state or runner readiness. A hidden icon does not prove the runner
is registered, online, or ready. GitLab remains the CI control plane. Nothing in
this feature changes job/test exit codes or merge settings.

## Coverage and display

- One record for each laptop GitLab job, including product checks and E2E.
- One record for a manual top-level `scripts/run.mjs` invocation. A full parallel
  run is one logical run, not one per lane. Diagnostics/help are not runs.
- The item sits immediately left of the `?` help icon in the right-hand group
  and is **hidden whenever no run is active**, including after success/failure.
  Filesystem events make it reappear automatically for a new run; there is no
  periodic idle polling.
- Amber: running, with elapsed time; a count when runs overlap. Unknown owner
  identity is shown as `unknown` in the popup, never as success.
- Completion still sends a native result notification and retains recent history.
  A prior failed/canceled/interrupted result keeps the item red while another run
  is active, until **Acknowledge failures** in its popup (or `local-ci-status ack`).
  No completed result alone makes the item visible. When the last run finishes,
  its popup closes; history remains available through `local-ci-status list`.
- Popup: active runs first, then recent outcomes. At most 20 rows, with an
  overflow count. `local-ci-status list` includes the complete accepted active
  list and up to 20 recent results. CI rows open only their validated GitLab job
  URL; manual rows have no command/link action.

Hammerspoon watches status-directory changes, coalescing bursts for250ms. Only
while runs are active, a three-second timer updates elapsed time and checks for
missing finishes/crashes. At0 active runs the timer stops. SketchyBar itself is
event-only (`update_freq=0`); startup/wake/reload and explicit clicks can perform
one-shot scans. **Hammerspoon must be running for automatic activity updates**,
not just notifications. No additional daemon is installed.

The shared parent is watched so a producer directory created later is noticed.
Only correctly shaped status-directory paths schedule work; unrelated shared
files do not launch the observer. Event paths never become commands or authorize
producers: the Python reader still enforces its UID/project/file checks. Dropped
filesystem-event flags, parent changes and wake cause a recovery scan.

One helper runs asynchronously at a time, with one queued follow-up for changes
that occur while it runs. Its15-second deadline terminates only that owned helper,
never a test/job process. Malformed/failed output cannot mean idle: an existing
active timer remains enabled; without previously confirmed activity, the watcher
waits for another event/recovery rather than retrying periodically while idle.
Reload/stop invalidates old callbacks and chains existing Hammerspoon shutdown
cleanup. Real filesystem-event timing/delivery still depends on macOS.

Notifications are native macOS notifications from `/usr/bin/osascript`
(`display notification`, following the existing Newsboat helper pattern), not
Hammerspoon balloons. They appear under **Script Editor**; macOS may ask once for
notification permission. Title and body are passed as separate argv values to a
fixed script, never interpolated into code. No sound is played. Satisfy the
Script Editor permission in System Settings → Notifications if alerts are missing.

Alerts are claimed once at start and once at completion. Fresh runs
that finish between observations still produce one pair. Completed records older than 60 seconds are loaded
silently after a cold start. Reloads retain claims in the private cache. Claims
are persisted **before** dispatch: this gives at-most-once attempts, not guaranteed
delivery. SketchyBar, Hammerspoon, the logged-in desktop session, and macOS
notification permissions must be available; absent GUI services can lose an
alert, not fail a job. Start/result notifications contain source, project, label,
elapsed time and result only, not logs or test credentials.

## Nix configuration and activation

Only `nixos/mac-home/home.nix` imports/enables `services.localCiStatus`. Defaults:

```nix
services.localCiStatus = {
  enable = true;
  ciUser = "weekenduo-ci";
  interval = 3; # Active-only elapsed/crash timer; not idle polling.
  finalizationGraceSeconds = 15;
  successSeconds = 30;
  allowedProjects = [ "weekenduo/backend" "weekenduo/duomobile" ];
};
```

The module installs the packaged Python helper, executable bar plugin,
`~/.config/local-ci-status/config.json`, and the `enabled` marker. Other hosts
install none of these. Shared bar/Lua additions check the marker and remain inert
when disabled. The helper uses a pinned interpreter and bar binary, without shell
initialization. No extra daemon, CI credential, or GitLab API token is needed.

Implementation tests/builds do **not** activate this configuration. Applying the
normal mac-home rebuild (`sup` / the repository's documented Darwin rebuild) is
a separate operator action requiring authorization. Its existing configuration
onChange hooks may reload SketchyBar. **Reload Config in Hammerspoon after the
rebuild** to load `nanowm.ci_watch`; reloading only SketchyBar does not start the
event watcher. Notifications do not depend on Hammerspoon. Do not use `hs -c`
as a substitute. Do not source the whole `sketchybarrc` as a test: its existing
tail stops/starts the system-info daemon.

For rollback, disable/remove the mac-home opt-in and perform the usual separately
authorized rebuild; the shared marker guards make the integration inert. Stop
existing producers first if immediate cessation of publishing is desired. Private
history can remain; do not delete it while diagnosing duplicate notifications.

## Producer permissions and privacy

The publisher is optional: macOS plus the producer's enabled marker, or explicit
`WD_CI_STATUS_ENABLE=1`. `WD_CI_STATUS_ENABLE=0` disables reporting. CI opts in via
the secret-free runner configuration example; it never writes desktop settings.

Each producer owns `/Users/Shared/weekenduo-ci-status-<uid>` (0755, no foreign
write), with atomic regular JSON records (0644, no foreign write). The observer
accepts only the login UID and configured `weekenduo-ci` UID, if that account
exists. Missing CI account is harmless. Files/directories must not be symlinks,
foreign-owned, writable by others, hardlinked files, malformed, or oversized.
Schema/version, filenames, times, labels and exact HTTPS GitLab job URLs are
checked independently by publisher and observer. Unsafe records are ignored;
malformed content/paths are not printed in diagnostics. Records are not an audit
or security authority.

**Shared records are readable by other local users.** They deliberately contain
minimal project/job/suite metadata and owner UID/PID/start identity. They must
never contain environment dumps, command arguments, output, tokens, signing keys,
or test credentials. CI gets no write access to a personal home/config/cache.

Publisher retention: up to 128 terminal records, expiring after 24 hours; never
prune active/foreign/unsafe files. At 256 entries per producer, new reporting is
refused rather than broadly cleaning. Publisher failures are advisory.

Observer state is login-user-owned `~/.cache/local-ci-status` (0700), with locked
atomic state (0600), up to 512 seen run IDs and 20 recent outcomes. A separate
sticky-failure flag survives source expiry/history pruning until acknowledgment.
At the seen-ID limit, current active records take priority; oldest vanished
unknown claims may be discarded without inventing a terminal result. A
conservative notification-time floor prevents replay of evicted IDs; unseen
older runs may lose an alert under this exceptional capacity pressure. Existing
retained runs still receive their result attempt, and sticky failures persist.

## Crash, cancellation and preparation

Owner identity is UID + PID + UTC process start time, not a process-name heuristic
or heartbeat age. A definitely absent/reused owner gets a 15-second finalization
grace, then an **interrupted** result. An inaccessible/ambiguous process remains
unknown. Sleep/wake alone cannot become failure or success; no test/job owner
process is killed.
A late explicit result replaces the inference without a duplicate result alert.

CI starts after immutable suite bootstrap and the runtime guard, before dependency
installation; the job-script shell is its owner. A separate `after_script` reads
the actual `CI_JOB_STATUS`; missing/unknown finish status never means passed.
Runner timeout/force cancellation may skip finalization; reconciliation handles
this honestly as interruption. Manual hooks observe existing signal-exit paths
and preserve teardown budgets, not install competing signal handlers.

The runner example offers an **optional** `pre_build_script` from the immutable
CI-owned control checkout. Replace `CONTROL_SHA` with the reviewed E2E commit and
use that exact control checkout's `#ci` shell/publisher. The duplicate start keeps
the original time and refreshes owner identity. With no available pre-build
publisher, earliest bootstrap is **not observed**; the normal hook starts later.
Account creation, runtime isolation, runner registration, final suite pins and
GitLab activation/merge-policy validation remain separate rollout gates.

## Non-secret troubleshooting

```sh
local-ci-status list       # read accepted activity/history; claims fresh notices
local-ci-status interval   # read active-only timer interval, no claims/GUI action
local-ci-status ack        # acknowledge the sticky error; does not change job results
sketchybar --query ci_status  # read-only bar inspection after activation
```

No icon while idle is expected. Missing icon during a run: check Hammerspoon is
running with its rebuilt config, plus mac-home opt-in, marker, helper/plugin and bar
configuration. No notifications: check the marker, Script Editor/notification
permissions, and macOS Do Not Disturb; absent notifications do not cause replay. Missing activity:
check producer opt-in and ownership/modes (not raw logs/environment), configured
account/project allowlists, and the finite record cap. Corrupt/unsafe private
state yields a bounded advisory rather than silently following a link. Preserve
the state for diagnosis; do not grant broader permissions to make it work.

Tests use isolated fixtures under `~/ai/artifacts/nixos-configs/local-ci-indicator/`
and mocked GUI/process-start boundaries. Python: `PYTHONDONTWRITEBYTECODE=1 python3
-m unittest discover -s tests/local-ci-status -v`. Lua:
`lua tests/local-ci-status/test_watcher.lua` with the locked Lua interpreter.
Live icon/notification proof requires a separately authorized controlled desktop
check after activation; fixture tests cannot prove cross-account GUI delivery.
