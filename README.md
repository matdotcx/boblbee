# boblbee

## What is this?

`boblbee` is a collection of dotfiles, scripts, and widgets that I use to set up my development environments (macOS and Ubuntu), to my own taste and specification. There are many dotfiles, but these are mine.

The name `boblbee` comes from [Point 65](https://boblbee.point65.com/pages/about-us-point-65-sweden) - a Swedish company founded in the late 90s to produce hard-case backpacks with spine protection, lumbar support, and loud colourways. I've used and loved them since the early 2000s, and carried my life in them, so it made sense to carry my digital detritus in one, too.

What makes this particular collection special is its intelligent sync system - it automatically adapts to different platforms (macOS and Ubuntu) and environments (with or without iCloud Drive), includes comprehensive system configuration, fleet management across multiple hosts, and integrates with modern tools like Claude Code. But at its heart, it's still just my dotfiles.

## Key Features

- **Cross-Platform**: Works on both macOS and Ubuntu with intelligent OS detection
- **Copy-Not-Symlink**: All dotfiles are real local files, never symlinks - immune to iCloud eviction and boot-time delays
- **Three-Way Sync**: Newest-mtime-wins across home, git repo, and iCloud (when available)
- **Shared Library Architecture**: Common helpers extracted to `scripts/lib/` - no duplicated code across scripts
- **Fleet Management**: Status checks and sync across all hosts with one command
- **SSH Keychain Integration**: macOS Keychain stores SSH passphrases permanently - no repeated prompts
- **Encrypted SSH Secrets**: On hosts without iCloud, SSH keys/config come from the private [`ark-config`](#ssh-keys--private-config-ark-config) repo, encrypted at rest with `age` and unlocked by a single vault-held bootstrap key
- **Claude Code Integration**: Syncs AI assistant preferences across devices
- **Observability**: Automatic Prometheus node_exporter setup with central registration
- **Nightly Self-Update**: Each host pulls boblbee at 00:48 and re-runs the syncs when there are new commits
- **Per-Host Agents**: Scheduled jobs that belong to one machine, assigned by hostname in `hosts/agent-assignments.txt`

## Quick Start

### macOS Setup

```bash
# Clone boblbee
mkdir -p ~/Developer/workspace/matdotcx && cd ~/Developer/workspace/matdotcx
git clone https://github.com/matdotcx/boblbee.git

# Run the setup
cd boblbee/scripts
./index.sh
```

### Ubuntu Setup

```bash
# Clone boblbee
mkdir -p ~/Developer/workspace/matdotcx && cd ~/Developer/workspace/matdotcx
git clone https://github.com/matdotcx/boblbee.git

# Run the setup
cd boblbee/scripts
./index.sh
```

Both platforms use the same canonical repo path: `~/Developer/workspace/matdotcx/boblbee`.

This will:
- **macOS**: Configure system preferences, install Xcode tools, set up MacPorts, sync Ghostty config, configure TouchID sudo, set up Tailscale, GPG signing, PAM SSH agent sudo, and FQDN hostname
- **Ubuntu**: Install essential packages, configure git and SSH, set up npm and Claude Code, install Tailscale and GPG signing
- **Both**: Sync shell config, tmux, motd, SSH keys, install Claude Code integration, set up observability collector, install the host's per-host agents and the nightly self-update, then switch the boblbee remote from HTTPS to SSH

### Upgrading Existing Installation

```bash
cd ~/Developer/workspace/matdotcx/boblbee
./scripts/upgrade.sh
```

### SSH keys & private config (`ark-config`)

> **Setup note — don't forget this on a new host.** SSH config and keys are **not**
> stored in this (public) repo. They live in a **private companion repo,
> [`ark-config`](https://github.com/matdotcx/ark-config)**, checked out as a sibling of
> boblbee (`~/Developer/workspace/matdotcx/ark-config`).

On a Mac signed into **iCloud Drive**, SSH material syncs from iCloud as before — no
extra steps. On a Mac **without iCloud** (headless/CI/signed-out), `ssh-sync.sh` falls
back to `ark-config`, where the private keys are stored **encrypted at rest** as `*.age`
files. On Ubuntu, `ssh-sync.sh` only checks `~/.ssh` permissions; run `script/bootstrap`
yourself to wire the keys and config from `ark-config`. A single passphrase-less ed25519 key — **`id_bootstrap`** —
unlocks everything: it's both the read-only GitHub **deploy key** that clones the private
repo and the **`age` identity** that decrypts the keys. Keep it in your vault; seed it
once per host.

**Bringing up a brand-new host (one seed):**

```bash
# 0. age must be present:  sudo port install age  /  brew install age  /  apt install age

# 1. seed the single bootstrap key from your vault
install -m 600 /path/from/vault/id_bootstrap ~/.config/boblbee/id_bootstrap

# 2. clone boblbee (public) and ark-config (private, via the deploy key)
mkdir -p ~/Developer/workspace/matdotcx && cd ~/Developer/workspace/matdotcx
git clone https://github.com/matdotcx/boblbee.git
GIT_SSH_COMMAND="ssh -i ~/.config/boblbee/id_bootstrap -o IdentitiesOnly=yes" \
  git clone git@github.com:matdotcx/ark-config.git

# 3. run setup as normal — ssh-sync decrypts keys into ~/.ssh and links the config
cd boblbee/scripts && ./index.sh
```

Override the key path with `BOBLBEE_BOOTSTRAP_KEY` if you keep it elsewhere. Full
mechanism (including why config is symlinked but keys are decrypted) is in
[DOCUMENTATION.md](DOCUMENTATION.md#ssh-special-case).

**Re-implementing this yourself?** `ark-config` is just a private git repo with a
per-consuming-repo directory layout (`ark-config/boblbee/…`); boblbee discovers it as a
sibling via `ARK_CONFIG_PATH` in `scripts/lib/config.sh`. Point that at your own private
repo and you get the same encrypted-secrets-with-one-bootstrap-key pattern.

## Command Reference

Once installed, you'll have access to the `bb-*` command suite:

### Getting Help
```bash
bb-help      # Show all boblbee commands
bb-status    # Check sync status of all components
prompthelp   # Understand shell prompt symbols
```

### Syncing
```bash
bb-sync          # Sync all configurations
bb-sync-zshrc    # Sync shell configuration
bb-sync-tmux     # Sync tmux configuration and themes
bb-sync-ghostty  # Sync Ghostty terminal config (macOS only)
bb-sync-zed      # Sync Zed editor config and themes (macOS only)
bb-sync-claude   # Sync Claude Code preferences
bb-sync-ssh      # Sync SSH configuration
bb-sync-motd     # Sync message of the day
```

### Fleet Management
```bash
bb-status-fleet  # Show config status across all hosts (one-line-per-host)
bb-sync-fleet    # Pull boblbee + run sync on every host in hosts/elements.txt
bb-update        # Update OS packages + tooling on this host (-r to reboot if needed)
bb-update-fleet  # Update OS packages + tooling on every host (-r to reboot if needed)
```

`hosts/elements.txt` is your real host list and is gitignored; copy
`hosts/elements.example.txt` to start one.

`bb-update-fleet` needs
SSH agent forwarding (`ssh -A` / `pam_ssh_agent_auth`) so remote `sudo` is
passwordless — load your key (`ssh-add -l`) before running.

### Utilities
```bash
bb-setup     # Run complete setup (for new machines)
bb-upgrade   # Upgrade existing installation
bb-edit      # Open boblbee in your editor
bb-reload    # Reload shell configuration
```

## Architecture

### Sync Strategy

All dotfiles are **real local files** - never symlinks. This avoids iCloud eviction breaking your shell on boot and removes the fragile dependency on iCloud file availability.

The sync uses **newest-mtime-wins**: whichever copy (home, repo, or iCloud) was modified most recently becomes the source of truth and is propagated to the other locations.

**macOS with iCloud Drive:**
```
~/.zshrc (local copy) <-> iCloud Drive <-> Git Repository
```
Three-way sync. iCloud provides cross-host sharing; git provides version history.

**macOS without iCloud / Ubuntu:**
```
~/.zshrc (local copy) <-> Git Repository
```
Two-way bidirectional sync. SSH is the exception: without iCloud it sources keys/config
from the private `ark-config` sibling repo instead — see
[SSH keys & private config](#ssh-keys--private-config-ark-config).

### Shared Libraries

All scripts source from `scripts/lib/`:

- **`lib.sh`** - Colour codes, logging, iCloud detection, file mtime comparison, backup, git commit helpers, and the unified `sync_dotfile()` function
- **`config.sh`** - Centralised configuration: canonical repo path, iCloud paths, observability endpoints, fleet HTTPS remote, and `get_default_branch()` helper

### Directory Structure

```
boblbee/
├── assets/
│   ├── .zshrc               # Cross-platform shell configuration
│   ├── .motd                # Message of the day
│   ├── claude-settings.json # Claude Code user settings (~/.claude/settings.json)
│   ├── claude-hooks/        # Claude Code hook scripts (installed to ~/.claude/hooks)
│   ├── gitignore_global     # Global gitignore (git-config-shared.sh)
│   ├── ghostty-config       # Ghostty terminal config
│   ├── ghostty-themes/      # Manganese Dark/Light themes
│   ├── terminal-themes/     # Manganese Terminal.app profiles
│   ├── zed/                 # Zed editor settings, keymap and themes
│   ├── tmux.conf            # Main tmux config
│   ├── tmux-base.conf       # Shared tmux settings
│   └── tmux-theme-*.conf    # Manganese tmux themes
├── claude/                  # Claude Code integration
│   └── memory/
│       └── user.md          # Global AI assistant preferences
├── docs/                    # Runbooks and task notes
├── hosts/
│   ├── elements.example.txt # Fleet host list template (copy to elements.txt, which is gitignored)
│   ├── agent-assignments.txt # Which per-host agent profiles each host gets
│   ├── agents/              # Per-host agent profiles (bin/, launchd/, install.sh)
│   └── manual-os-updates.txt # Hosts where macOS updates are installed by hand
├── script/
│   └── bootstrap            # Wire private configs from ark-config into place
├── ssh_config.example       # Placeholder SSH config (used when ark-config is absent)
├── scripts/
│   ├── lib/
│   │   ├── config.sh        # Shared configuration values (incl. ark-config path)
│   │   ├── lib.sh           # Shared helper functions
│   │   └── git-safe-sync.sh # Serialised commit-and-push helper used by agent profiles
│   ├── index.sh             # Main installer (cross-platform)
│   ├── upgrade.sh           # Upgrade existing installations
│   ├── self-update.sh       # Nightly pull + sync (LaunchAgent on macOS, cron on Linux)
│   ├── host-agents.sh       # Install this host's agent profiles
│   ├── detect-os.sh         # OS detection (is_macos, is_ubuntu, is_cli_only)
│   ├── *-sync.sh            # Sync scripts (zshrc, tmux, ghostty, zed, motd, claude, ssh)
│   ├── claude.sh            # Install Claude Code if missing; local copy of claude/memory/user.md
│   ├── git-config-shared.sh # Shared git config (GitHub HTTPS→SSH rewrite, aliases, global gitignore)
│   ├── dots.sh              # macOS system preferences
│   ├── macports.sh          # macOS MacPorts setup
│   ├── touchid-sudo.sh      # macOS TouchID for sudo
│   ├── xcode.sh             # macOS Xcode CLI tools
│   ├── ubuntu-essentials.sh # Ubuntu package installation
│   ├── ubuntu-git-setup.sh  # Ubuntu git and SSH setup
│   ├── setup-gpg-signing.sh # Git GPG signing
│   ├── tailscale-setup.sh   # Tailscale VPN setup
│   ├── pam-ssh-agent-sudo.sh # SSH agent sudo auth (macOS)
│   ├── hostname-fqdn.sh     # FQDN hostname (macOS)
│   ├── observability-collector.sh # Prometheus node_exporter setup
│   ├── install-collector.sh # node_exporter binary installer
│   ├── status-fleet.sh      # Fleet status reporting
│   ├── sync-fleet.sh        # Fleet sync orchestration
│   ├── system-update.sh     # Update OS packages + tooling (local host)
│   ├── update-fleet.sh      # Fleet update orchestration
│   └── run-on-hosts.sh      # Run commands across hosts
└── templates/
    └── CLAUDE.md            # Project memory template
```

## Observability

During setup, boblbee installs a Prometheus `node_exporter` and registers the host with a central monitoring server (helium). Set `SKIP_OBSERVABILITY=1` before running setup to skip this.

- **Linux**: `node_exporter` on port 9100, as a systemd user service
- **macOS**: `node_exporter` on port 9100, as the LaunchAgent `org.iaconelli.node-exporter`
- It listens on the host's Tailscale address when there is one, otherwise on localhost (never `0.0.0.0`)
- Its textfile collector reads `~/.local/share/prometheus/textfile`, where the nightly self-update writes `boblbee.prom` and agent profiles write their own `.prom` files
- Helium registration happens automatically over SSH if reachable

## What it's not

`boblbee` is not a one-stop shop for everyone and their dog; it's not intended to be something you run once, having not read the contents and understood the changes.

Don't use this if you're not at ease reading basic shell scripts, interpreting Apple's `defaults write` commands, or if you're unwilling to blast your machine config away and start over if something breaks.

## Documentation

For detailed information, see [DOCUMENTATION.md](DOCUMENTATION.md).

## License

This project is open source and available under the MIT License.

---

**Remember**: Never run code you haven't read and understood. These are my dotfiles, make them yours.
