# boblbee

## What is this?

`boblbee` is a collection of dotfiles, scripts, and widgets that I use to set up my development environments (macOS and Ubuntu), to my own taste and specification. There are many dotfiles, but these are mine.

The name `boblbee` comes from [Point 65](https://boblbee.point65.com/pages/about-us-point-65-sweden) - a Swedish company founded in the late 90s to produce hard-case backpacks with spine protection, lumbar support, and loud colourways. I've used and loved them since the early 2000s, and carried my life in them, so it made sense to carry my digital detritus in one, too.

What makes this particular collection special is its intelligent sync system - it automatically adapts to different platforms (macOS and Ubuntu) and environments (with or without iCloud Drive), includes comprehensive system configuration, and seamlessly integrates with modern tools like Claude Code. But at its heart, it's still just my dotfiles.

## Key Features

- **Cross-Platform**: Works on both macOS and Ubuntu with intelligent OS detection
- **Smart Sync**: Automatically adapts to iCloud and non-iCloud environments
- **Claude Code Integration**: Syncs AI assistant preferences across devices
- **Intelligent Configuration**: Shell, SSH, and system preferences management
- **Observability Integration**: Automatic metrics collection and reporting to central monitoring
- **Comprehensive Setup**: Full system configuration automation
- **Modular Design**: Use what you need, ignore what you don't

## Quick Start

### macOS Setup

#### Option 1: MacPorts Installation (Recommended)

```bash
# Install via MacPorts with essential tools
sudo port install boblbee +essentials

# Or with development tools
sudo port install boblbee +development

# Run the setup
boblbee-setup
```

#### Option 2: Manual Installation

```bash
# Download and extract boblbee
mkdir -p ~/Developer/workspace/matdotcx/ && cd ~/Developer/workspace/matdotcx
curl -L http://github.com/matdotcx/boblbee/archive/ubuntu.tar.gz | tar zxf - && mv boblbee-ubuntu boblbee

# Run the setup
cd boblbee/scripts
./index.sh
```

### Ubuntu Setup

```bash
# Clone boblbee
git clone -b ubuntu https://github.com/matdotcx/boblbee.git ~/boblbee

# Run the setup
cd ~/boblbee/scripts
./index.sh
```

This will:
- **macOS**: Configure system preferences, install Xcode tools, set up MacPorts/Homebrew
- **Ubuntu**: Install build-essential, configure apt packages, set up npm and Claude Code
- Install Claude Code integration and preferences
- Configure shell with platform-specific smart sync
- Set up SSH (iCloud on macOS, local on Ubuntu)
- Install observability collector and register with central monitoring
- Create all necessary symlinks and configurations

### Upgrading Existing Installation

**macOS:**
```bash
cd ~/Developer/workspace/matdotcx/boblbee
./scripts/upgrade.sh
```

**Ubuntu:**
```bash
cd ~/boblbee
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
bb-sync       # Sync all configurations (zshrc, claude, ssh)
bb-sync-zshrc # Sync shell configuration only
bb-sync-claude# Sync Claude Code preferences only
bb-sync-ssh   # Sync SSH configuration (iCloud only)
```

### Utilities
```bash
bb-setup     # Run complete setup (for new machines)
bb-upgrade   # Upgrade existing installation
bb-edit      # Open boblbee in your editor
bb-reload    # Reload shell configuration
```

### Development Tools
```bash
scripts/setup-gpg-signing.sh  # Configure Git GPG signing with existing keys
```

## Daily Usage

After making changes to your configuration:

```bash
# Quick sync everything
bb-sync

# Check what needs syncing
bb-status

# Reload to apply changes
bb-reload
```

## Architecture

### Sync Strategy

Boblbee uses an intelligent two-tier approach:

**macOS with iCloud Drive:**
- Primary storage: iCloud Drive
- Backup: Git repository
- Files are symlinked for instant sync

**macOS without iCloud Drive:**
- Primary storage: Git repository
- Files are copied locally

**Ubuntu (CLI servers):**
- Primary storage: Git repository
- Simple bidirectional sync
- No iCloud dependency

### Directory Structure

```
boblbee/
├── assets/
│   └── .zshrc               # Cross-platform shell configuration
├── claude/                  # Claude Code integration
│   └── memory/
│       └── user.md          # Your AI assistant preferences
├── scripts/                 # Setup and sync scripts
│   ├── detect-os.sh         # OS detection utility
│   ├── index.sh             # Main installer (cross-platform)
│   ├── install-collector.sh # Prometheus node_exporter installer
│   ├── observability-collector.sh  # Metrics collection setup
│   ├── tailscale-setup.sh   # Optional Tailscale installer
│   ├── ubuntu-*.sh          # Ubuntu-specific setup scripts
│   ├── *-sync.sh            # Sync utilities
│   └── ...                  # macOS system setup scripts
└── templates/               # Starter templates
    └── CLAUDE.md            # Project memory template
```

## Observability Integration

Every machine set up with boblbee automatically installs and configures a Prometheus node exporter, reporting metrics to a central monitoring server (helium).

### What Gets Installed

- **Linux**: `node_exporter` on port 9100 (standard Prometheus exporter)
- **macOS**: Detects existing macOS exporter on port 9101, or installs node_exporter

### How It Works

During `index.sh` setup:
1. `observability-collector.sh` runs automatically
2. Installs the appropriate exporter for the platform
3. Creates a systemd service (Linux) or LaunchAgent (macOS)
4. Registers with helium via SSH (if reachable)
5. Helium's Prometheus starts scraping metrics immediately

### Scripts

| Script | Description |
|--------|-------------|
| `install-collector.sh` | Downloads and installs node_exporter for the correct platform/architecture |
| `observability-collector.sh` | Wrapper that installs exporter and registers with helium |
| `tailscale-setup.sh` | Optional - installs Tailscale for remote machines to reach helium |

### Manual Registration

If helium wasn't reachable during setup, register later:

```bash
ssh -A helium '~/observability/scripts/register-host.sh $(hostname) <your-ip> [port]'
```

The port argument is optional (default: 9100). Use 9101 for macOS exporter.

### Skipping Observability

Set `SKIP_OBSERVABILITY=1` before running setup to skip collector installation.

## Customization

### Shell Configuration

The `.zshrc` includes:
- Smart git-aware prompt
- Useful aliases and functions
- Development environment setup
- Boblbee command suite

### System Preferences

Edit `scripts/dots.sh` to customize:
- Finder preferences
- Dock configuration
- System UI/UX settings
- Security preferences

## Documentation

For detailed information, see [DOCUMENTATION.md](DOCUMENTATION.md):
- Complete setup instructions
- Troubleshooting guide
- Architecture details
- Contributing guidelines

## What it's not

`boblbee` is not a one-stop shop for everyone and their dog; it's not intended to be something you run once, having not read the contents and understood the changes.

Don't use this if you're not at ease reading basic shell scripts, interpreting Apple's `defaults write` commands, or if you're unwilling to blast your machine config away and start over if something breaks.

## Important Notes

- **Read before running**: Understand what each script does
- **Backup first**: Some scripts modify system settings
- **Cross-platform**: Works on macOS and Ubuntu 24.04+
- **Requires admin**: Some features need sudo access

## MacPorts Installation

boblbee is available as a MacPorts port with automatic dependency management. The Portfile includes three installation variants:

- **Default** (`+essentials`): Core tools plus zsh enhancements, fzf, ripgrep, tree, GitHub CLI
- **Development** (`+development`): Adds Python testing tools, linters, and system utilities
- **Complete** (`+complete`): Everything above plus tmux, deno, and additional tools

### Installation Variants

```bash
# Basic installation with essentials (recommended)
sudo port install boblbee +essentials

# Add development tools
sudo port install boblbee +development  

# Complete installation
sudo port install boblbee +complete
```

### Dependencies Included

The MacPorts installation automatically handles all dependencies identified in the `.zshrc` analysis:
- **Core**: zsh, git, curl, python3, ssh, coreutils
- **Shell**: zsh-syntax-highlighting, zsh-autosuggestions  
- **Tools**: fzf, ripgrep, tree, gh, nodejs/npm
- **Optional**: pytest, ruff, pre-commit, htop, eza, tmux, deno, uv

See [`macports/README.md`](macports/README.md) for detailed installation instructions and troubleshooting.

## Contributing

I welcome contributions that improve the project. If you've found a bug, have an idea for a feature, or want to improve the documentation:

1. Fork the repository
2. Test your changes on both macOS (with/without iCloud) and Ubuntu systems
3. Make sure the upgrade path works for existing users
4. Update the documentation if needed
5. Submit a pull request with a clear description

The best contributions are often the simplest ones - fixing typos, clarifying documentation, or adding error handling where it's missing.

## License

This project is open source and available under the MIT License. Use it, modify it, learn from it, make it your own. If you build something cool with it, I'd love to hear about it.

---

**Remember**: Never run code you haven't read and understood. These are my dotfiles, make them yours.