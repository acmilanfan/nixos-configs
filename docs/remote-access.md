# Private SSH and tmux access

Terminal access works in both directions between **mac-home** and each personal
Linux laptop, even on different networks. Tailscale provides the private network;
ordinary OpenSSH provides key authentication and filesystem access. There is no
remote desktop, router port forwarding or public agent API. SSH agent forwarding
is disabled by default in the supplied client aliases (not forbidden server-side).

| SSH alias | Tailscale machine name | Flake host |
| --- | --- | --- |
| `mac-home` | `mac-home` | `mac-home` |
| `yogabook` | `yogabook` | `yogabook-gen10` |
| `t480` | `t480-nixos` | `t480-home` |

All connections use **gentooway**, the owner of the existing tmux sessions.
mac-work and vm-hyprland do not opt into this setup.

## 1. Prepare locally on each machine

Keep local console access throughout initial setup. Password and root SSH login
are disabled; there is deliberately no password-based bootstrap. A failed remote
login must not be your only way to repair configuration.

Create a [personal Tailscale account](https://login.tailscale.com/start), using an
identity provider with MFA. All three devices must join the **same** tailnet.
No Tailscale auth key needs to be put in Git or a Nix expression.

On mac-home, use only the Nix-managed **CLI-only tailscaled** service, not the
Tailscale GUI/App Store/Homebrew app at the same time. If a different variant is
already installed, stop and follow Tailscale's
[variant migration guidance](https://tailscale.com/docs/concepts/macos-variants)
before enabling this daemon. It is managed by launchd and can run without the
GUI user being logged in; it is not controlled by macOS's VPN settings.

This change introduces new Nix files. Normal Git-backed flake evaluation excludes
untracked files: review and add the new modules to Git's index (or commit them)
before rebuilding. Nothing in this guide stages or commits them automatically.

From this repository, on the corresponding machine:

```sh
# mac-home only
sudo darwin-rebuild switch --flake .#mac-home

# Yogabook only
sudo nixos-rebuild switch --flake .#yogabook-gen10

# T480 only
sudo nixos-rebuild switch --flake .#t480-home
```

These are deployment instructions, not commands executed by the regression tests.

## 2. Enroll each device

Run the appropriate command locally, then open the printed login URL and sign
into the same account. Use the names below so the SSH aliases match:

```sh
# mac-home
sudo tailscale up --hostname=mac-home --ssh=false

# Yogabook
sudo tailscale up --hostname=yogabook --ssh=false --netfilter-mode=off

# T480
sudo tailscale up --hostname=t480-nixos --ssh=false --netfilter-mode=off
```

Do **not** enable Tailscale SSH (`--ssh`), advertise routes, or enable an exit node.
The Linux module also enforces `--ssh=false` and `--netfilter-mode=off` on
activation: the NixOS firewall, rather than Tailscale's accept-all tunnel rules,
controls incoming traffic. Only SSH is explicitly opened on `tailscale0`; UDP
41641 is opened for encrypted Tailscale transport, not for SSH.

All three managed daemons also set `TS_DISABLE_SSH_SERVER=true` at startup. This
blocks Tailscale's separate SSH server even if an old `RunSSH=true` preference is
present, so it cannot bypass ordinary OpenSSH authentication before a later
preference-setting step. Verify the deployed service environment locally:

```sh
# mac-home: expect TS_DISABLE_SSH_SERVER => true in the environment
sudo launchctl print system/com.tailscale.tailscaled | grep TS_DISABLE_SSH_SERVER
# Linux: expect TS_DISABLE_SSH_SERVER=true
systemctl show tailscaled -p Environment | grep TS_DISABLE_SSH_SERVER
```

If enrolling an already-configured node, `tailscale up` can ask for its existing
non-default flags. Inspect them rather than using `--reset` blindly. If a name
already exists, Tailscale may add a suffix; check the Machines page and resolve
the conflict or update the matching SSH alias.

```sh
tailscale status
tailscale ip -4 mac-home
tailscale ip -4 yogabook
tailscale ip -4 t480-nixos
tailscale ping mac-home       # from either laptop
tailscale ping yogabook       # from mac-home
tailscale ping t480-nixos     # from mac-home
```

Relayed connections are valid; a direct connection is not required. A ping proves
the tunnel, not SSH authorization. If one times out, inspect `tailscale status`
and `tailscale netcheck` on both ends before changing SSH keys.

## 3. Create and exchange SSH public keys

On **each** machine as gentooway, create a separate key for this access. If either
`~/.ssh/id_ed25519_remote` or its `.pub` file already exists, inspect/reuse it;
**do not overwrite it**. Private keys stay on the machine that generated them.

```sh
umask 077
mkdir -p ~/.ssh
chmod 700 ~/.ssh
# Run only if the private/public key paths do not already exist:
ssh-keygen -t ed25519 -a 64 -f ~/.ssh/id_ed25519_remote -C "$(whoami)@$(hostname)-remote"
```

Choose a passphrase at the prompt. To avoid repeated prompts during a login
session, load the key into the local agent (no forwarding is required):

```sh
ssh-add ~/.ssh/id_ed25519_remote
cat ~/.ssh/id_ed25519_remote.pub
ssh-keygen -lf ~/.ssh/id_ed25519_remote.pub
```

Transfer **only the one-line `.pub` contents** through a trusted channel or using
the machines' local consoles. Verify its fingerprint against the source:

| Destination `~/.ssh/authorized_keys` | Add these public keys |
| --- | --- |
| mac-home | Yogabook's and T480's |
| Yogabook | mac-home's |
| T480 | mac-home's |

On each destination, preserve existing entries and append the appropriate keys
with a local editor. Do not replace the whole file with `>` or copy a private key:

```sh
umask 077
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
nvim ~/.ssh/authorized_keys
ssh-keygen -lf ~/.ssh/authorized_keys
```

Each key occupies one complete line. Files must belong to gentooway; an incorrectly
owned/writable home or `.ssh` directory can cause OpenSSH to refuse keys.
These runtime files are intentionally not generated or overwritten by Nix.

## 4. Verify and connect

At each **destination's local console**, obtain its server fingerprint:

```sh
# mac-home
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# Linux (sudo may be needed to access the directory)
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Then from a laptop connect to mac-home, and from mac-home connect to each laptop:

```sh
ssh mac-home
ssh yogabook
ssh t480
```

On first connection compare the displayed fingerprint with the one obtained
locally. Accept it only if it matches. Do not disable host-key checking or blindly
delete a changed known-host entry. The client first looks up a registered peer
with `tailscale ip -4`, then uses `tailscale nc` to its Tailscale address; this
doesn't depend on macOS short-name DNS search settings. Standard tailnet IPv4
addresses are required for these aliases.

Verify each deployed daemon's effective policy locally, especially on macOS where
an unmanaged, earlier sshd include could override single-value directives:

```sh
# mac-home
sudo /usr/sbin/sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|authenticationmethods|permitrootlogin|allowusers) '
# Linux
sudo sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|authenticationmethods|permitrootlogin|allowusers) '
```

Expected: passwords/keyboard-interactive/root are `no`, authentication is
`publickey`, and the only allowed user entries are
`gentooway@100.64.0.0/10` and `gentooway@fd7a:115c:a1e0::/48`.
On macOS the normal SSH listener remains enabled: these are **sshd user/source
restrictions**, not interface-level firewall isolation or proof of Tailscale
membership. CGNAT `100.64.0.0/10` is not exclusive to Tailscale, and another network
can use the same CGNAT/ULA address ranges. Such a source can pass this address
allowlist, but still needs an authorized private key. Typical LAN/public source
addresses outside these ranges are rejected; no LAN password fallback is provided.

For failures, use `ssh -vv mac-home` (or the other alias). Check enrollment,
hostname, key ownership, and the offered `id_ed25519_remote` key. Do not paste
private keys or unredacted diagnostic logs into an issue.

## Working with existing tmux sessions and files

```sh
ssh mac-home 'tmux ls'
ssh -t mac-home 'tmux attach-session -t SESSION_NAME'
# Watch without sending input:
ssh -t mac-home 'tmux attach-session -r -t SESSION_NAME'
```

Replace `SESSION_NAME` with one listed by `tmux ls`; the same commands work with
`yogabook` or `t480`. A second client can attach without kicking the local client
off (omit `-d`). Both clients share the session; a read-only client cannot control
it, but either client's terminal size can affect the layout.

Detach with **Ctrl+b, then d**. Inside an existing local tmux, the first Ctrl+b is
handled locally: send **Ctrl+b, Ctrl+b, then d** to detach the remote tmux instead.
Do not type `exit` in an agent pane or kill the tmux server just to disconnect.
Disconnecting SSH leaves tmux and its agents running. If `tmux ls` shows no
sessions, check the user and whether the application was started inside tmux;
plain GUI terminal processes cannot be attached retroactively.

Shell commands, scp and sftp work normally; SSH doesn't auto-attach tmux:

```sh
ssh mac-home 'ls -la ~/Projects'
scp ./example.txt mac-home:~/
sftp mac-home
```

Keep agent servers on their existing loopback addresses; remote terminal access
does not require exposing their web/API ports.

## Availability, security and rollback

- Both ends need internet access, Tailscale enrollment, and an awake destination.
  Tailscale does not wake a sleeping laptop. mac-home already has `no-sleep`:
  `no-sleep on` keeps it running with the lid closed, and `no-sleep off` restores
  normal sleep. This is system-wide and affects battery use; enable it deliberately.
  On Linux, keep the destination awake using its existing power settings; this
  change does not override lid/suspend behavior.
- The Linux profile uses host-wide loose reverse-path filtering for compatibility
  with Tailscale policy routing. It is less strict than NixOS's default and has
  not been shown necessary on these two laptops; testing stricter filtering is
  a follow-up requiring Linux runtime access, not something the macOS fixtures
  establish. No subnet or exit-node routing is enabled.
- A reboot terminates tmux processes and running agents. Session-layout restore
  is not process preservation. FileVault can require a local unlock before macOS
  and the background services can start; this isn't a remote power-on solution.
- A new personal tailnet's default access policy is broad. Review ACLs/grants
  before inviting anyone or sharing a device; restrict who can reach these nodes'
  TCP/22. Enrollment alone does not authorize SSH: the matching private key is
  still required. Keep node keys valid; reauthenticate expired nodes locally.
- For a lost device, remove it from the Tailscale Machines page **and** remove its
  public key from the other machines' `authorized_keys`. Protect the Tailscale
  account with MFA. Removing a key does not end an already-authenticated SSH
  session; review active sessions separately.
- To stop network access immediately, run `sudo tailscale down` locally. This
  disconnects existing remote access too. To undo the configuration, remove the
  remote-access imports from the affected host's system/home modules and rebuild
  locally. On Linux this restores the previous disabled SSH server; mac-home
  returns to the existing common key-only SSH configuration (without the new
  source-address restriction). Remove dedicated keys/known-host entries only
  after verifying which files/entries belong to this setup.

## Repository verification vs live acceptance

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/remote-access -p 'test_*.py' -v
```

Tests evaluate all five host configurations, check intended host/firewall/auth
scope, parse generated client config with `ssh -G`, parse daemon directives with
`sshd -T` using a throwaway fixture host key, and execute the proxy's shell logic
against present/missing-peer fixtures. Source snapshots include Git-tracked files
and explicitly reviewed new task files, never arbitrary untracked files. Artifacts go under
`~/ai/artifacts/nixos-configs/remote-access/`; tests do not enroll, activate, or
read live private keys. `sshd -T` validates configuration, not actual login/CIDR
admission, and macOS parsing does not replace a Linux runtime test.

After rollout, test mac-home ↔ Yogabook and mac-home ↔ T480 on **different
networks**: list/attach the same running tmux session, detach, reconnect, and
confirm the same pane/process is still running. Also check that an unlisted key,
root login and SSH from ordinary LAN sources outside the allowlist cannot
authenticate. Those live checks remain
manual; repository checks alone do not establish working remote connectivity.
