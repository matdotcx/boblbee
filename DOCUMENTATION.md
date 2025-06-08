# Boblbee Documentation

Complete guide for the boblbee intelligent dotfiles management system for macOS and Ubuntu.

## Table of Contents

1. [Command Reference](#command-reference)
2. [Architecture](#architecture)
3. [Installation Guide](#installation-guide)
4. [Daily Workflow](#daily-workflow)
5. [Script Reference](#script-reference)
6. [Customization](#customization)
7. [Troubleshooting](#troubleshooting)
8. [Contributing](#contributing)

## Command Reference

All boblbee commands follow the `bb-*` naming convention for easy discovery and consistency.

### Core Commands

| Command | Description |
|---------|-------------|
| `bb-help` | Display all available boblbee commands with descriptions |
| `bb-status` | Check the current sync status of all components |
| `bb-sync` | Sync all configurations (zshrc, claude, ssh) |
| `bb-reload` | Reload shell configuration after changes |

### Setup Commands

| Command | Description |
|---------|-------------|
| `bb-setup` | Run complete system setup (for new machines) |
| `bb-upgrade` | Upgrade existing boblbee installation |

### Sync Commands

| Command | Description |
|---------|-------------|
| `bb-sync-zshrc` | Sync shell configuration between iCloud/git |
| `bb-sync-claude` | Sync Claude Code preferences to dotfiles |
| `bb-sync-ssh` | Sync SSH configuration (iCloud only) |

### Utility Commands

| Command | Description |
|---------|-------------|
| `bb-edit` | Open boblbee directory in your default editor |
| `prompthelp` | Display shell prompt symbol meanings |

## Architecture

### Design Philosophy

Boblbee follows these principles:
1. **Cross-platform**: Works on macOS and Ubuntu with intelligent OS detection
2. **Adaptive**: Works seamlessly with or without iCloud (macOS) or git-only (Ubuntu)
3. **Non-destructive**: Always backs up before modifying
4. **Transparent**: Clear about what each operation does
5. **Modular**: Use only what you need

### Sync Strategy

The system intelligently adapts based on platform and available services:

#### macOS with iCloud Drive

```
iCloud Drive (Primary)
    ↓ symlink
~/.zshrc, ~/.ssh
    ↓ sync
Git Repository (Backup)
```

- Configuration files live in iCloud
- Home directory contains symlinks
- Git repository serves as backup
- Changes sync instantly across devices

#### macOS without iCloud Drive

```
Git Repository (Primary)
    ↓ copy
~/.zshrc, ~/.ssh
```

- Configuration files live in git
- Home directory contains regular files
- Manual sync required via `bb-sync-*` commands

#### Ubuntu (CLI Servers)

```
Git Repository (Primary)
    ↓ bidirectional sync
~/.zshrc, ~/.ssh
```

- Configuration files live in git
- Simple bidirectional sync between git and home
- No iCloud dependency
- CLI-focused setup for development servers

### Directory Structure

```
boblbee/
├── .gitignore               # Git ignore rules
├── LICENSE                  # License information
├── README.md                # Quick start guide
├── DOCUMENTATION.md         # This file
├── assets/
│   └── .zshrc              # Cross-platform shell configuration
├── claude/                  # Claude Code integration
│   └── memory/
│       └── user.md         # Global Claude preferences
├── scripts/                 # All executable scripts
│   ├── detect-os.sh        # OS detection utility
│   ├── claude-sync.sh      # Claude memory sync
│   ├── claude.sh           # Claude setup (cross-platform)
│   ├── index.sh            # Main installer (cross-platform)
│   ├── new-machine.sh      # New machine helper (cross-platform)
│   ├── upgrade.sh          # Upgrade script (cross-platform)
│   ├── zshrc-sync.sh       # Shell sync (cross-platform)
│   ├── ssh-sync.sh         # SSH sync (cross-platform)
│   ├── ubuntu-essentials.sh # Ubuntu: Install tools, npm, Claude Code
│   ├── ubuntu-git-setup.sh  # Ubuntu: Configure git and SSH
│   ├── dots.sh             # macOS: System preferences
│   ├── macports.sh         # macOS: MacPorts setup
│   ├── touchid-sudo.sh     # macOS: TouchID for sudo
│   └── xcode.sh            # macOS: Xcode tools
└── templates/              # Starter templates
    └── CLAUDE.md           # Project memory template
```

### Component Details

#### Shell Configuration (.zshrc)

Features:
- Git-aware prompt with status indicators
- Comprehensive aliases and functions
- Development environment setup
- Boblbee command suite
- Platform-specific optimizations

#### Claude Code Integration

Memory hierarchy:
1. **User Memory**: Global preferences (synced via boblbee)
2. **Project Memory**: Per-project settings (in project repos)
3. **Local Memory**: Machine-specific overrides (never synced)

#### SSH Configuration

- Automatically symlinked on iCloud machines
- Preserves permissions (700 for .ssh, 600 for keys)
- Backs up existing configuration before changes

## Installation Guide

### Prerequisites

**macOS:**
- macOS 12+ (tested)
- Command Line Tools or Xcode
- Admin (sudo) access
- Internet connection

**Ubuntu:**
- Ubuntu 24.04+ (tested)
- sudo access
- Internet connection
- git (will be installed if missing)

### New Machine Setup

#### macOS Setup

1. **Download boblbee**
   ```bash
   mkdir -p ~/Developer/workspace/matdotcx/
   cd ~/Developer/workspace/matdotcx
   curl -L http://github.com/matdotcx/boblbee/archive/ubuntu.tar.gz | tar zxf -
   mv boblbee-ubuntu boblbee
   ```

2. **Run setup**
   ```bash
   cd boblbee/scripts
   ./index.sh
   ```

3. **Reload shell**
   ```bash
   source ~/.zshrc
   # or
   bb-reload
   ```

#### Ubuntu Setup

1. **Clone boblbee**
   ```bash
   git clone -b ubuntu https://github.com/matdotcx/boblbee.git ~/boblbee
   ```

2. **Run setup**
   ```bash
   cd ~/boblbee/scripts
   ./index.sh
   ```

3. **Reload shell**
   ```bash
   exec zsh  # Switch to zsh and reload
   # or log out and back in
   ```

#### Verify Installation

```bash
bb-status
```

### What Gets Installed

#### macOS Installation

1. **System Preferences**
   - Finder settings
   - Dock configuration
   - UI/UX preferences
   - Security settings

2. **Development Tools**
   - Xcode Command Line Tools
   - MacPorts (optional)
   - Package managers

3. **Shell Environment**
   - Custom prompt
   - Aliases and functions
   - Path configuration
   - Completion setup

4. **Dotfiles Management**
   - Smart sync system
   - Claude Code integration
   - SSH configuration

#### Ubuntu Installation

1. **Essential Packages**
   - build-essential
   - git, curl, zsh, vim
   - tree, htop, ripgrep, fd-find
   - npm (for Claude Code)

2. **Development Tools**
   - Claude Code (npm global install)
   - Git configuration
   - SSH key management

3. **Shell Environment**
   - zsh as default shell
   - Cross-platform prompt
   - Ubuntu-specific aliases
   - npm global bin in PATH

4. **Dotfiles Management**
   - Simple git-based sync
   - Claude Code integration
   - Local SSH management

## Daily Workflow

### Making Configuration Changes

1. **Edit your configuration**
   ```bash
   # Option 1: Direct edit
   vim ~/.zshrc
   
   # Option 2: Open in editor
   bb-edit
   ```

2. **Sync changes**
   ```bash
   # Sync specific component
   bb-sync-zshrc
   
   # Or sync everything
   bb-sync
   ```

3. **Apply changes**
   ```bash
   bb-reload
   ```

4. **Commit to git**
   ```bash
   cd ~/Developer/workspace/matdotcx/boblbee
   git add -A
   git commit -m "feat: add new aliases"
   git push
   ```

### Checking Status

```bash
# Full status check
bb-status

# Git status
cd ~/Developer/workspace/matdotcx/boblbee && git status
```

### Syncing Between Machines

1. **On the source machine**
   ```bash
   bb-sync
   # macOS:
   cd ~/Developer/workspace/matdotcx/boblbee
   # Ubuntu:
   cd ~/boblbee
   git push
   ```

2. **On the target machine**
   ```bash
   # macOS:
   cd ~/Developer/workspace/matdotcx/boblbee
   # Ubuntu:
   cd ~/boblbee
   git pull
   bb-sync
   bb-reload
   ```

## Script Reference

### Setup Scripts

#### index.sh
Main installation orchestrator with platform detection:
- **macOS**: Runs TouchID, Xcode, MacPorts, system preferences
- **Ubuntu**: Runs essentials, git setup, Claude Code installation
- **Both**: Claude setup, shell sync, SSH sync

#### dots.sh (macOS only)
Configures macOS system preferences including:
- Finder preferences
- Dock settings
- UI/UX configuration
- System behavior

#### ubuntu-essentials.sh (Ubuntu only)
Installs essential Ubuntu packages:
- Development tools (build-essential)
- npm and Claude Code
- Shell configuration
- Directory setup

#### ubuntu-git-setup.sh (Ubuntu only)
Configures git for shared workflow:
- Git global configuration
- SSH key setup and management
- GitHub token configuration
- Cross-platform compatibility

#### claude.sh
Sets up Claude Code memory integration:
- Creates config directory
- Establishes symlinks
- Preserves existing preferences

#### ssh-sync.sh
Manages SSH configuration with platform detection:
- **macOS**: Detects iCloud availability, creates symlinks when appropriate
- **Ubuntu**: Local SSH management, permission setting
- **Both**: Preserves permissions, backs up existing configs

#### zshrc-sync.sh
Handles shell configuration sync with platform detection:
- **macOS with iCloud**: Symlinks to iCloud, syncs to git backup
- **macOS without iCloud**: Bidirectional sync between git and home
- **Ubuntu**: Simple bidirectional sync between git and home
- **All**: Maintains proper permissions and backups

### Utility Scripts

#### upgrade.sh
Safely upgrades existing installations:
- Backs up current configuration
- Pulls latest changes
- Runs necessary setup scripts
- Preserves customizations

#### new-machine.sh
Helper for new machine setup with iCloud pre-configured.

## Customization

### Adding Custom Aliases

1. Edit `.zshrc`
2. Add your aliases in the appropriate section
3. Run `bb-sync-zshrc`
4. Reload with `bb-reload`

### Modifying System Preferences

1. Edit `scripts/dots.sh`
2. Add or modify `defaults write` commands
3. Test changes on a non-critical system first
4. Document any new settings

### Creating Project Templates

1. Add templates to `templates/` directory
2. Document usage in template header
3. Include in git repository

## Troubleshooting

### Common Issues

**"bb-command not found"**
- Run `source ~/.zshrc` or `bb-reload`
- Check if `.zshrc` was properly synced
- Verify boblbee installation path

**"Permission denied" errors**
- Some scripts require sudo access
- Check file permissions with `ls -la`
- Ensure scripts are executable: `chmod +x scripts/*.sh`

**Sync not working**
- Run `bb-status` to check configuration
- Verify git repository is accessible
- Check iCloud Drive availability
- Review sync script output for errors

**Changes not appearing**
- Ensure you've run the appropriate sync command
- Check if changes were saved to the correct location
- Verify symlinks with `ls -la ~/.*`

### Manual Recovery

If automated tools fail:

1. **Backup current state**
   ```bash
   cp ~/.zshrc ~/.zshrc.backup
   cp -r ~/.ssh ~/.ssh.backup
   ```

2. **Reset configuration**
   ```bash
   cd ~/Developer/workspace/matdotcx/boblbee
   git reset --hard origin/gold
   git pull
   ```

3. **Reinstall**
   ```bash
   ./scripts/index.sh
   ```

### Debug Mode

Enable verbose output:
```bash
set -x  # Enable debug mode
bb-sync
set +x  # Disable debug mode
```

## Contributing

### Guidelines

1. **Test thoroughly**: Changes should work on both iCloud and non-iCloud systems
2. **Document changes**: Update README and DOCUMENTATION
3. **Follow conventions**: Maintain consistent naming and style
4. **Preserve compatibility**: Don't break existing installations

### Testing Checklist

Before submitting changes:
- [ ] Test on fresh macOS installation
- [ ] Test on fresh Ubuntu 24.04 installation
- [ ] Test on system with existing configuration
- [ ] Test macOS with iCloud enabled
- [ ] Test macOS without iCloud
- [ ] Test Ubuntu CLI-only environment
- [ ] Verify upgrade path works on both platforms
- [ ] Update documentation
- [ ] Add helpful error messages

### Code Style

- Use consistent indentation (2 spaces)
- Add clear comments for complex logic
- Include error handling
- Make scripts idempotent when possible
- Follow existing naming conventions

### Submitting Changes

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Update documentation
6. Submit pull request

## Security Considerations

- Never commit secrets or credentials
- SSH keys remain in user control
- Scripts request sudo only when necessary
- Backups created before destructive operations
- No telemetry or phone-home features

## Support

- Check existing issues on GitHub
- Read error messages carefully
- Use `bb-status` for diagnostics
- Review script source for understanding
- Ask questions via GitHub issues

---

Remember: These are dotfiles. Read, understand, and customize them to your needs.