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
- **Claude Code Integration**: Syncs AI assistant preferences across devices
- **Observability**: Automatic Prometheus node_exporter setup with central registration

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
- **Both**: Sync shell config, tmux, motd, SSH keys, install Claude Code integration, set up observability collector

### Upgrading Existing Installation

```bash
cd ~/Developer/workspace/matdotcx/boblbee
./scripts/upgrade.sh
```

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
bb-sync-claude   # Sync Claude Code preferences
bb-sync-ssh      # Sync SSH configuration
bb-sync-motd     # Sync message of the day
```

### Fleet Management
```bash
bb-status-fleet  # Show config status across all hosts (one-line-per-host)
bb-sync-fleet    # Pull boblbee + run sync on every host in hosts/elements.txt
```

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
Two-way bidirectional sync.

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
│   ├── ghostty-config       # Ghostty terminal config
│   ├── ghostty-themes/      # Manganese Dark/Light themes
│   ├── tmux.conf            # Main tmux config
│   ├── tmux-base.conf       # Shared tmux settings
│   └── tmux-theme-*.conf    # Manganese tmux themes
├── claude/                  # Claude Code integration
│   └── memory/
│       └── user.md          # Global AI assistant preferences
├── hosts/
│   └── elements.txt         # Fleet host list
├── scripts/
│   ├── lib/
│   │   ├── config.sh        # Shared configuration values
│   │   └── lib.sh           # Shared helper functions
│   ├── index.sh             # Main installer (cross-platform)
│   ├── upgrade.sh           # Upgrade existing installations
│   ├── detect-os.sh         # OS detection (is_macos, is_ubuntu, has_icloud)
│   ├── *-sync.sh            # Sync scripts (zshrc, tmux, ghostty, motd, claude, ssh)
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
│   └── run-on-hosts.sh      # Run commands across hosts
└── templates/
    └── CLAUDE.md            # Project memory template
```

## Observability

During setup, boblbee installs a Prometheus `node_exporter` and registers the host with a central monitoring server (helium). Set `SKIP_OBSERVABILITY=1` before running setup to skip this.

- **Linux**: `node_exporter` on port 9100
- **macOS**: `node_exporter` on port 9100, managed via LaunchAgent
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
