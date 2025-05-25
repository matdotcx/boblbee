# boblbee

## What is this?

`boblbee` is a collection of dotfiles, scripts, and widgets that I use to set up my Mac, to my own taste and specification. There are many dotfiles, but these are mine.

The name `boblbee` comes from [Point 65](https://boblbee.point65.com/pages/about-us-point-65-sweden) - a Swedish company founded in the late 90s to produce hard-case backpacks with spine protection, lumbar support, and loud colourways. I've used and loved them since the early 2000s, and carried my life in them, so it made sense to carry my digital detritus in one, too.

What makes this particular collection special is its intelligent sync system - it automatically adapts to machines with or without iCloud Drive, includes comprehensive macOS system configuration, and seamlessly integrates with modern tools like Claude Code. But at its heart, it's still just my dotfiles.

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

## What it's not

`boblbee` is not a one-stop shop for everyone and their dog; it's not intended to be something you run once, having not read the contents and understood the changes.

Don't use this if you're not at ease reading basic shell scripts, interpreting Apple's `defaults write` commands, or if you're unwilling to blast your machine config away and start over if something breaks.

## Important Notes

- **Read before running**: Understand what each script does
- **Backup first**: Some scripts modify system settings
- **macOS only**: Designed specifically for macOS
- **Requires admin**: Some features need sudo access

## Contributing

Feel free to fork, submit PRs, and open issues.

## License

This project is open source. Feel free to fork, modify, and share.

---

**Remember**: Never run code you haven't read and understood. These are my dotfiles, make them yours.