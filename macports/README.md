# MacPorts Installation for boblbee

This directory contains the MacPorts Portfile for installing boblbee and its dependencies through the MacPorts package manager.

## Prerequisites

1. **Install MacPorts**: Download and install from [macports.org](https://www.macports.org/install.php)
2. **Update MacPorts**: 
   ```bash
   sudo port selfupdate
   ```

## Installation Options

### Option 1: Local Installation (Recommended for Development)

1. **Clone the repository**:
   ```bash
   git clone https://github.com/matdotcx/boblbee.git
   cd boblbee
   ```

2. **Install locally from the Portfile**:
   ```bash
   # Basic installation with essentials
   sudo port install +local +essentials
   
   # With development tools
   sudo port install +local +essentials +development
   
   # Complete installation
   sudo port install +local +complete
   ```

3. **Run setup**:
   ```bash
   boblbee-setup
   ```

### Option 2: Official Port (Future)

Once submitted to MacPorts, you'll be able to install with:
```bash
# Basic installation
sudo port install boblbee

# With development tools  
sudo port install boblbee +development

# Complete installation
sudo port install boblbee +complete
```

## Installation Variants

### Default (`+essentials`)
Includes core dependencies and essential development tools:
- **Core**: zsh, git, curl, python3, ssh, coreutils
- **Shell**: zsh-syntax-highlighting, zsh-autosuggestions
- **Tools**: fzf, ripgrep, tree, gh (GitHub CLI)
- **Node.js**: nodejs18, npm8

### Development (`+development`) 
Adds Python development tools:
- **Python**: pytest, ruff, pre-commit
- **System**: htop, eza

### Complete (`+complete`)
Everything above plus:
- **Additional**: tmux, deno, uv

## Post-Installation

1. **Run the setup**:
   ```bash
   boblbee-setup
   ```

2. **Configure GitHub token** (optional but recommended):
   ```bash
   security add-generic-password -a ${USER} -s gh-token -w YOUR_GITHUB_TOKEN
   ```

3. **Sync configurations**:
   ```bash
   bb-sync
   ```

4. **Reload your shell**:
   ```bash
   source ~/.zshrc
   ```

## Dependency Analysis

The Portfile was created by analyzing the `.zshrc` file to identify all dependencies:

### Required Tools
- `git` - Git operations and prompt integration
- `curl` - Network operations and API calls
- `python3` - Timestamp generation and development tools
- `ssh` - SSH key management and authentication

### Shell Enhancements
- `zsh-syntax-highlighting` - Command syntax highlighting
- `zsh-autosuggestions` - History-based command suggestions
- `fzf` - Fuzzy finding for files and commands
- `ripgrep` - Fast text search (used in `fif` function)

### Development Integration
- `gh` - GitHub CLI for repository operations
- `tree` - Directory structure visualization
- `nodejs18` + `npm8` - Node.js development environment

### Optional Tools
- Python testing and linting: `pytest`, `ruff`, `pre-commit`
- System monitoring: `htop`
- Enhanced file listing: `eza`
- Terminal multiplexer: `tmux`
- Modern JavaScript runtime: `deno`
- Python package manager: `uv`

## Troubleshooting

### Common Issues

**Port installation fails**:
```bash
sudo port clean boblbee
sudo port install boblbee +essentials
```

**Dependencies missing**:
```bash
# Check installed ports
port installed
# Install missing dependencies manually
sudo port install missing-dependency
```

**Setup script can't find tools**:
Ensure MacPorts is in your PATH:
```bash
export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
```

## Contributing

If you encounter issues with the Portfile or want to suggest improvements:

1. Test the Portfile locally
2. Update dependencies in the Portfile as needed
3. Submit a pull request with your changes
4. Document any new dependencies or requirements

## MacPorts Submission Process

To submit this port to MacPorts officially:

1. **Test thoroughly** on clean macOS systems
2. **Create proper checksums** using `port file`
3. **Submit via Trac** at https://trac.macports.org
4. **Follow MacPorts guidelines** for port submission

The Portfile follows MacPorts best practices and should be ready for submission once tested.