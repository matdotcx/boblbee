# Boblbee Documentation

Complete guide for the boblbee dotfiles management system for macOS and Ubuntu.

## Table of Contents

1. [Command Reference](#command-reference)
2. [Architecture](#architecture)
3. [Installation Guide](#installation-guide)
4. [Daily Workflow](#daily-workflow)
5. [Script Reference](#script-reference)
6. [Fleet Management](#fleet-management)
7. [Observability](#observability)
8. [Troubleshooting](#troubleshooting)

## Command Reference

All boblbee commands follow the `bb-*` naming convention. They're defined as shell functions in `.zshrc`.

### Core Commands

| Command | Description |
|---------|-------------|
| `bb-help` | Display all available boblbee commands with descriptions |
| `bb-status` | Check sync status of all components |
| `bb-sync` | Sync all configurations (zshrc, tmux, ghostty, motd, claude, ssh) |
| `bb-reload` | Reload shell configuration |

### Setup Commands

| Command | Description |
|---------|-------------|
| `bb-setup` | Run complete system setup (`index.sh`) |
| `bb-upgrade` | Upgrade existing boblbee installation |

### Sync Commands

| Command | Description |
|---------|-------------|
| `bb-sync-zshrc` | Sync shell configuration (three-way with iCloud, or two-way) |
| `bb-sync-tmux` | Sync tmux configuration and Manganese themes |
| `bb-sync-ghostty` | Sync Ghostty terminal config and themes (macOS only) |
| `bb-sync-zed` | Sync Zed editor config and themes (macOS only) |
| `bb-sync-claude` | Commit Claude Code preferences to git |
| `bb-sync-ssh` | Sync SSH configuration (copies from iCloud on macOS) |
| `bb-sync-motd` | Sync message of the day |

### Fleet Commands

| Command | Description |
|---------|-------------|
| `bb-status-fleet` | One-line-per-host status: commit, zshrc type/hash, plugins, MacPorts, agent dir perms |
| `bb-sync-fleet` | Pull boblbee + run sync scripts on every host in `hosts/elements.txt` |
| `bb-update-fleet` | Pull boblbee + update OS packages/tooling on every host (uses `ssh -A` for sudo; `-r` reboots hosts that need it) |

### Utility Commands

| Command | Description |
|---------|-------------|
| `bb-update` | Update OS packages + tooling (MacPorts/apt, recommended macOS updates, Claude Code) on the local host; `-r` reboots if needed |
| `bb-edit` | Open boblbee directory in your default editor |
| `prompthelp` | Display shell prompt symbol meanings |

## Architecture

### Design Principles

1. **Copy, not symlink**: All dotfiles are real local files. Symlinks to iCloud are fragile - they break when iCloud evicts files or delays materialisation on boot.
2. **Newest wins**: Sync compares mtime across all locations and propagates the most recently modified version.
3. **Single canonical path**: The repo lives at `~/Developer/workspace/matdotcx/boblbee` on every host, every platform. No path detection or fallback logic.
4. **Shared libraries**: Common code lives in `scripts/lib/`. No script duplicates helpers inline.
5. **Auto-detect branch**: Scripts use `get_default_branch()` instead of hardcoded branch names.

### Shared Libraries

#### `scripts/lib/config.sh`

Centralised configuration values sourced by all scripts:

| Value | Purpose |
|-------|---------|
| `BOBLBEE_CANONICAL_PATH` | Single repo path (`~/Developer/workspace/matdotcx/boblbee`) |
| `ICLOUD_BASE` | iCloud Drive root |
| `ICLOUD_SYNC_DIR` / `ICLOUD_SYNC_PATH` | Sync directory within iCloud (`Ark/Sync/System`) |
| `HELIUM_FQDN` / `HELIUM_IP` | Central monitoring server |
| `HELIUM_REGISTER_SCRIPT` | Path to registration script on helium |
| `NODE_EXPORTER_VERSION` | Pinned version for node_exporter installs |
| `REPO_HTTPS` | HTTPS clone URL (avoids agent-forwarding dependency for fleet pulls) |
| `get_default_branch()` | Auto-detect current branch from git (cached per run) |

#### `scripts/lib/lib.sh`

Shared helper functions:

| Function | Purpose |
|----------|---------|
| `log_info`, `log_success`, `log_warn`, `log_error` | Coloured log output |
| `log_message` | Timestamped structured logging to stderr |
| `check_icloud()` | Detect iCloud: directory exists + not evicted (ls traversal test) |
| `get_file_mtime()` | Cross-platform file mtime as epoch seconds |
| `find_newest_file()` | Return the path of the newest file among given arguments |
| `check_permissions()` | Verify write access to a file's parent directory |
| `backup_file()` | Timestamped backup of regular files (skips symlinks) |
| `commit_dotfiles_changes()` | Stage, diff-check, and commit files in the repo |
| `sync_dotfile()` | The unified three-way/two-way sync helper (see below) |

Also provides colour code variables: `GREEN`, `RED`, `YELLOW`, `BLUE`, `CYAN`, `DIM`, `NC`.

### The `sync_dotfile()` Helper

This is the core sync function used by `zshrc-sync.sh` and `motd-sync.sh`. Signature:

```
sync_dotfile <display_name> <home_file> <repo_file> <icloud_file> <git_add_pattern>
```

It:
1. Checks if iCloud is available (via `check_icloud()`)
2. Builds a list of locations to compare (2 or 3 depending on iCloud)
3. Finds the newest file by mtime
4. Propagates the newest to all other locations
5. Migrates symlinks to real files if encountered
6. Commits repo changes to git

### Sync Strategy by Platform

#### macOS with iCloud Drive

```
Home (~/.zshrc)  <->  iCloud Drive  <->  Git Repository
      ^                    ^                    ^
      |                    |                    |
  local copy         cross-host sync      version history
```

Three-way sync. All three locations are compared; newest wins. iCloud provides cross-device sharing; the git repo provides version control and fleet distribution.

#### macOS without iCloud / Ubuntu

```
Home (~/.zshrc)  <->  Git Repository
      ^                    ^
      |                    |
  local copy         version history
```

Two-way sync. iCloud is skipped entirely.

#### SSH (special case)

SSH does not use `sync_dotfile()`. `ssh-sync.sh` picks a source in priority order:

1. **iCloud Drive** (preferred) — copies **portable files** (keys, config, authorized_keys) from iCloud to `~/.ssh/` as a local directory. Read-only from iCloud, write to local.
2. **ark-config fallback** (no iCloud) — when iCloud Drive is absent, `script/bootstrap` symlinks `~/.ssh/config` to `ark-config/boblbee/ssh_config` and **decrypts** the private keys from `ark-config/boblbee/*.age` into `~/.ssh/`. This is the non-iCloud path that keeps headless / signed-out Macs (and any host with the private repo cloned) in sync. See the [ark-config](https://github.com/matdotcx/ark-config) convention.
3. **local only** (neither available) — leaves `~/.ssh` untouched apart from fixing permissions.

On macOS it also stores key passphrases in Keychain via `ssh-add --apple-use-keychain` so you're never prompted again. If `~/.ssh` is a symlink (legacy), it's automatically migrated to a real directory.

Why keys are **decrypted/copied** but config is **symlinked** under the ark-config path: ssh enforces strict permissions and refuses keys it considers too exposed, and a private key symlinked into a git working tree is fragile (a branch switch or `git clean` would pull it out from under `ssh`). The config is safe to symlink, so edits flow straight back to the version-controlled repo.

##### The bootstrap key (`id_bootstrap`)

Private keys are stored in ark-config **encrypted at rest** as `*.age` files. A single
passphrase-less ed25519 key, `id_bootstrap`, unlocks everything. It has two jobs:

- **GitHub read-only deploy key** on ark-config, so a host can clone/pull the private repo.
- **age identity**, so `script/bootstrap` can `age -d` the `*.age` secrets.

It lives in a vault and is seeded once per host at `~/.config/boblbee/id_bootstrap`
(`0600`, override with `BOBLBEE_BOOTSTRAP_KEY`). Because it's passphrase-less and stays on
the host, the daily auto-sync decrypts non-interactively. The deploy key is what lets a
**brand-new** host clone the private repo (step 2 below); once cloned, ongoing ark-config
pulls use the normal `id_github` key that bootstrap decrypts into `~/.ssh`.

**Provisioning a brand-new host — one seed:**

```bash
# 1. seed the single bootstrap key from your vault
install -m 600 /path/from/vault/id_bootstrap ~/.config/boblbee/id_bootstrap

# 2. clone boblbee (public) and ark-config (private, via the deploy key)
git clone https://github.com/matdotcx/boblbee.git ~/Developer/workspace/matdotcx/boblbee
GIT_SSH_COMMAND="ssh -i ~/.config/boblbee/id_bootstrap -o IdentitiesOnly=yes" \
  git clone git@github.com:matdotcx/ark-config.git ~/Developer/workspace/matdotcx/ark-config

# 3. run the sync — decrypts keys into ~/.ssh and links the config
~/Developer/workspace/matdotcx/boblbee/scripts/ssh-sync.sh
```

Requires the `age` binary (`sudo port install age` / `brew install age` / `apt install age`).

## Installation Guide

### Prerequisites

**macOS:**
- macOS 12+
- Admin (sudo) access
- Internet connection

**Ubuntu:**
- Ubuntu 24.04+
- sudo access
- Internet connection
- git (installed by `ubuntu-essentials.sh` if missing)

### New Machine Setup

Both platforms use the same path and branch:

```bash
mkdir -p ~/Developer/workspace/matdotcx && cd ~/Developer/workspace/matdotcx
git clone https://github.com/matdotcx/boblbee.git
cd boblbee/scripts
./index.sh
```

Then reload your shell:
```bash
source ~/.zshrc    # or: exec zsh
```

### What Gets Installed

#### macOS (`index.sh` runs, in order)

1. `touchid-sudo.sh` - TouchID for sudo (requires sudo)
2. `xcode.sh` - Xcode Command Line Tools
3. `macports.sh` - MacPorts package manager (requires sudo)
4. `dots.sh` - System preferences (Finder, Dock, UI/UX, security)
5. `claude.sh` - Claude Code memory integration
6. `zshrc-sync.sh` - Shell configuration sync
7. `tmux-sync.sh` - Tmux config and Manganese themes
8. `ghostty-sync.sh` - Ghostty terminal config and themes
9. `zed-sync.sh` - Zed editor config and themes
10. `motd-sync.sh` - Message of the day
11. `ssh-sync.sh` - SSH keys from iCloud + Keychain storage
12. `tailscale-setup.sh` - Tailscale VPN
13. `observability-collector.sh` - Prometheus node_exporter
14. `pam-ssh-agent-sudo.sh` - SSH agent sudo authentication
15. `setup-gpg-signing.sh` - Git GPG commit signing
16. `hostname-fqdn.sh` - Set HostName to FQDN (requires sudo)

#### Ubuntu (`index.sh` runs, in order)

1. `ubuntu-essentials.sh` - Essential packages (build-essential, git, curl, zsh, vim, ripgrep, fd-find, htop, tree, npm)
2. `ubuntu-git-setup.sh` - Git config and SSH key setup
3. `claude.sh` - Claude Code memory integration
4. `zshrc-sync.sh` - Shell configuration sync
5. `tmux-sync.sh` - Tmux config and themes
6. `motd-sync.sh` - Message of the day
7. `ssh-sync.sh` - Local SSH management
8. `tailscale-setup.sh` - Tailscale VPN
9. `observability-collector.sh` - Prometheus node_exporter
10. `setup-gpg-signing.sh` - Git GPG commit signing
11. `hostname-fqdn.sh` - (skips on non-macOS)

### Upgrading

```bash
cd ~/Developer/workspace/matdotcx/boblbee
./scripts/upgrade.sh
```

The upgrade script:
- Pulls the latest from the current branch (auto-detected)
- Checks for symlinks that need migration to copies
- Re-runs all sync scripts
- Preserves existing configurations

## Daily Workflow

### Making Changes

1. Edit your config directly (`vim ~/.zshrc`) or via `bb-edit`
2. Sync: `bb-sync` (or `bb-sync-zshrc` for just shell)
3. Apply: `bb-reload`

### Checking Status

```bash
bb-status         # Local sync status
bb-status-fleet   # Status across all hosts
```

### Syncing Between Machines

```bash
# On the source machine
bb-sync
cd ~/Developer/workspace/matdotcx/boblbee && git push

# On the target machine
cd ~/Developer/workspace/matdotcx/boblbee && git pull
bb-sync
bb-reload
```

Or use fleet sync to push to all hosts at once:
```bash
bb-sync-fleet
```

## Script Reference

### Setup & Orchestration

| Script | Platform | Description |
|--------|----------|-------------|
| `index.sh` | Both | Main installer - runs all setup scripts in dependency order |
| `upgrade.sh` | Both | Safe upgrade: git pull, re-run syncs, preserve config |
| `detect-os.sh` | Both | Provides `is_macos()`, `is_ubuntu()`, `has_icloud()` |

### Sync Scripts

| Script | Platform | Description |
|--------|----------|-------------|
| `zshrc-sync.sh` | Both | Three-way/two-way `.zshrc` sync via `sync_dotfile()` |
| `motd-sync.sh` | Both | Three-way/two-way `.motd` sync via `sync_dotfile()` |
| `tmux-sync.sh` | Both | Bidirectional sync for `tmux.conf`, `tmux-base.conf`, and theme files |
| `ghostty-sync.sh` | macOS | Bidirectional config sync + bidirectional theme sync (Manganese Dark/Light) |
| `zed-sync.sh` | macOS | Bidirectional sync for Zed `settings.json`, `keymap.json`, and themes |
| `ssh-sync.sh` | Both | macOS: copy portable files from iCloud, store keys in Keychain. Ubuntu: permissions only |
| `claude-sync.sh` | Both | Install hooks from `assets/claude-hooks/` to `~/.claude/hooks/`; sync `~/.claude/settings.json` and Claude memory (newest wins, commits to git) |
| `claude.sh` | Both | Initial Claude Code setup (config dir, symlink to user.md) |

### Platform Setup

| Script | Platform | Description |
|--------|----------|-------------|
| `dots.sh` | macOS | System preferences: Finder, Dock, UI/UX, security |
| `macports.sh` | macOS | Install MacPorts, configure `/etc/paths.d/macports` |
| `touchid-sudo.sh` | macOS | Enable TouchID for sudo |
| `xcode.sh` | macOS | Install Xcode Command Line Tools |
| `ubuntu-essentials.sh` | Ubuntu | Install packages, npm, configure zsh as default shell |
| `ubuntu-git-setup.sh` | Ubuntu | Git global config, SSH key setup |
| `hostname-fqdn.sh` | macOS | Set HostName to `LocalHostName.domain` from DNS search domains (skips Tailscale) |
| `tailscale-setup.sh` | Both | Install and configure Tailscale VPN |
| `setup-gpg-signing.sh` | Both | Configure Git GPG commit signing |
| `pam-ssh-agent-sudo.sh` | macOS | Build and install `pam_ssh_agent_auth` for passwordless sudo via SSH agent |

### Observability

| Script | Platform | Description |
|--------|----------|-------------|
| `observability-collector.sh` | Both | Install node_exporter and register with helium |
| `install-collector.sh` | Both | Download and install node_exporter for the correct platform/arch |

### Fleet

| Script | Description |
|--------|-------------|
| `status-fleet.sh` | One SSH round-trip per host: checks commit, zshrc type/hash, plugins, MacPorts, agent dir perms |
| `sync-fleet.sh` | Fetches via HTTPS (no agent forwarding needed), merges, runs sync scripts on each host |
| `system-update.sh` | Update OS packages + tooling on the local host (MacPorts/apt, recommended macOS updates, Claude Code); `-r` reboots if needed |
| `update-fleet.sh` | Pull + run `system-update.sh` on each host; uses `ssh -A` so remote sudo authenticates via the forwarded agent (`pam_ssh_agent_auth`) |
| `run-on-hosts.sh` | Run arbitrary commands across hosts in `hosts/elements.txt` |

## Fleet Management

### Host List

Hosts are listed in `hosts/elements.txt`, one per line. Lines starting with `#` are ignored.

### Status Checks

`bb-status-fleet` (or `./scripts/status-fleet.sh`) gathers per-host info in one SSH call:

| Column | Green | Yellow | Red |
|--------|-------|--------|-----|
| COMMIT | Matches local HEAD | Different commit (drift) | `norepo` |
| ZSHRC | `file` (correct) | `symlink` (needs migration) | `missing` |
| ZSHRC-HASH | Matches repo hash | Different hash (drift) | - |
| PLUGINS | Loaded | - | `not loaded` |
| MACPORTS | `yes` | `no` | - |
| AGENTDIR | `700` or `absent` | - | Wrong permissions |

### Fleet Sync

`bb-sync-fleet` (or `./scripts/sync-fleet.sh`):
1. SSHs to each host
2. Fetches over HTTPS (public repo, no agent forwarding dependency)
3. Fast-forward merges
4. Runs `zshrc-sync.sh`, `ssh-sync.sh`, `tmux-sync.sh`, `motd-sync.sh`

Environment variables:
- `PARALLEL=1` - Run all hosts concurrently
- `DRY_RUN=1` - Print what would run without executing
- `HOSTS_FILE=path` - Override default host list

### Fleet Update

`bb-update-fleet` (or `./scripts/update-fleet.sh`):
1. SSHs to each host **with agent forwarding (`ssh -A`)** so remote `sudo`
   authenticates via `pam_ssh_agent_auth` — load your key first (`ssh-add -l`)
2. Fetches over HTTPS + fast-forward merges (so the newest `system-update.sh` runs)
3. Runs `system-update.sh`, which on **macOS** does `port selfupdate` +
   `port upgrade outdated`, recommended `softwareupdate -i -r`, and `claude update`;
   on **Ubuntu** does `apt-get update`/`upgrade`/`autoremove` and `claude update`

A restart is never forced. Hosts that need one are listed in the summary; pass
`-r` (e.g. `bb-update-fleet -r`) to reboot those hosts (scheduled 1 minute out
so the SSH session closes cleanly). `node_exporter` is out of scope — its version
is pinned in `config.sh` and updated via the normal sync path.

Same `PARALLEL=1` / `DRY_RUN=1` / `HOSTS_FILE=path` / `SSH_OPTS=...` knobs as
fleet sync.

## Observability

### How It Works

During `index.sh` setup:
1. `observability-collector.sh` runs automatically
2. Installs `node_exporter` for the platform (version pinned in `config.sh`)
3. Creates a systemd service (Linux) or LaunchAgent (macOS)
4. Registers with helium via SSH (if reachable)
5. Helium's Prometheus starts scraping metrics on port 9100

Set `SKIP_OBSERVABILITY=1` to skip.

### Manual Registration

If helium wasn't reachable during setup:
```bash
ssh -A helium '~/observability/scripts/register-host.sh $(hostname) <your-ip>'
```

## Troubleshooting

### "bb-command not found"

- Run `source ~/.zshrc` or `bb-reload`
- Verify boblbee is at `~/Developer/workspace/matdotcx/boblbee`
- Check that `.zshrc` is a real file (not a broken symlink): `ls -la ~/.zshrc`

### SSH keeps asking for passphrase

On macOS, run `bb-sync-ssh` - it calls `ssh-add --apple-use-keychain` to store passphrases in Keychain permanently. You'll be prompted once per key, then never again.

### iCloud files not syncing

- Check iCloud Drive is enabled and the sync directory exists
- `check_icloud()` verifies the directory is traversable (not evicted)
- If iCloud is unavailable, scripts fall back to two-way sync automatically

### Symlink detected where a file should be

The refactored system uses copies, not symlinks. If a sync script finds a symlink at `~/.zshrc` or `~/.motd`, it automatically migrates it to a real file by reading the symlink target and creating a copy.

### Fleet host unreachable

- Verify Tailscale is running: `tailscale status`
- Check SSH BatchMode works: `ssh -o BatchMode=yes hostname true`
- The fleet scripts use `ConnectTimeout=5` - increase via `SSH_OPTS` env var if needed

### Manual Recovery

```bash
# Backup current state
cp ~/.zshrc ~/.zshrc.backup
cp -r ~/.ssh ~/.ssh.backup

# Reset and reinstall
cd ~/Developer/workspace/matdotcx/boblbee
git pull
./scripts/index.sh
```

### Debug Mode

```bash
set -x
bb-sync
set +x
```

---

Remember: These are dotfiles. Read, understand, and customise them to your needs.
