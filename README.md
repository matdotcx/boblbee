# boblbee

A smart dotfiles management system for macOS that adapts to your environment.

## Overview

`boblbee` is an intelligent dotfiles framework that automatically handles synchronization across machines with or without iCloud Drive. It includes comprehensive macOS system configuration, development environment setup, and seamless integration with modern tools like Claude Code.

The name comes from [Boblbee backpacks](https://boblbee.point65.com) - Swedish hardshell backpacks designed to protect and carry your essentials. Just like the backpack, this project protects and carries your digital essentials across all your Macs.

## Key Features

- **Smart Sync**: Automatically adapts to iCloud and non-iCloud environments
- **Claude Code Integration**: Syncs AI assistant preferences across devices
- **Intelligent Configuration**: Shell, SSH, and system preferences management
- **Comprehensive Setup**: Full macOS configuration automation
- **Modular Design**: Use what you need, ignore what you don't

## Quick Start

### First Time Setup

```bash
# Download and extract boblbee
mkdir -p ~/Developer/workspace/gl52/ && cd ~/Developer/workspace/gl52
curl -L http://github.com/matdotcx/boblbee/archive/gold.tar.gz | tar zxf - && mv boblbee-gold boblbee

# Run the setup
cd boblbee/scripts
./index.sh
```

This will:
- Configure macOS system preferences
- Set up development tools
- Install Claude Code integration
- Configure shell with smart sync
- Set up SSH (if using iCloud)
- Create all necessary symlinks

### Upgrading Existing Installation

```bash
cd ~/Developer/workspace/gl52/boblbee
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

**With iCloud Drive:**
- Primary storage: iCloud Drive
- Backup: Git repository
- Files are symlinked for instant sync

**Without iCloud Drive:**
- Primary storage: Git repository
- Files are copied locally

### Directory Structure

```
boblbee/
├── .zshrc                    # Shell configuration
├── claude/                   # Claude Code integration
│   └── memory/
│       └── user.md          # Your AI assistant preferences
├── scripts/                  # Setup and sync scripts
│   ├── index.sh             # Main installer
│   ├── *-sync.sh            # Sync utilities
│   └── ...                  # System setup scripts
└── templates/               # Starter templates
    └── CLAUDE.md            # Project memory template
```

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

## Important Notes

- **Read before running**: Understand what each script does
- **Backup first**: Some scripts modify system settings
- **macOS only**: Designed specifically for macOS
- **Requires admin**: Some features need sudo access

## Contributing

1. Fork the repository
2. Test changes on both iCloud and non-iCloud systems
3. Update documentation
4. Submit a pull request

## License

This project is open source. Feel free to fork, modify, and share.

---

**Remember**: Never run code you haven't read and understood. These are my dotfiles, make them yours.