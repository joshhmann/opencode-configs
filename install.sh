#!/bin/bash

# OpenCode Configs Installer
# This script installs opencode configuration files and sets up the environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/opencode"
BACKUP_DIR="$CONFIG_DIR/backups/$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if opencode is installed
check_opencode() {
    if ! command -v opencode &> /dev/null; then
        print_error "opencode is not installed!"
        echo "Please install opencode first: https://opencode.ai"
        exit 1
    fi
    print_success "opencode found: $(opencode --version)"
}

# Backup existing configs
backup_existing() {
    if [ -d "$CONFIG_DIR" ]; then
        print_info "Backing up existing configs to $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
        
        # Backup existing json files
        for file in "$CONFIG_DIR"/*.json; do
            if [ -f "$file" ] && [ ! -L "$file" ]; then
                cp "$file" "$BACKUP_DIR/"
                print_info "Backed up: $(basename "$file")"
            fi
        done
        
        print_success "Backup complete"
    else
        print_info "Creating config directory: $CONFIG_DIR"
        mkdir -p "$CONFIG_DIR"
    fi
}

# Install configuration files
install_configs() {
    print_info "Installing configuration files..."
    
    # Copy all config files
    cp "$SCRIPT_DIR/configs/"*.json "$CONFIG_DIR/"
    
    # Create symlink for default mode (balanced)
    if [ -L "$CONFIG_DIR/oh-my-opencode.json" ]; then
        rm "$CONFIG_DIR/oh-my-opencode.json"
    fi
    
    ln -sf "$CONFIG_DIR/oh-my-opencode-balanced.json" "$CONFIG_DIR/oh-my-opencode.json"
    
    print_success "Configuration files installed"
}

# Install omo-mode script
install_script() {
    print_info "Installing omo-mode script..."
    
    cp "$SCRIPT_DIR/scripts/omo-mode" "$CONFIG_DIR/omo-mode"
    chmod +x "$CONFIG_DIR/omo-mode"
    
    print_success "omo-mode script installed"
}

# Add aliases to shell config
install_aliases() {
    print_info "Setting up shell aliases..."
    
    local shell_rc=""
    local current_shell="$(basename "$SHELL")"
    
    case "$current_shell" in
        bash)
            shell_rc="$HOME/.bashrc"
            ;;
        zsh)
            shell_rc="$HOME/.zshrc"
            ;;
        fish)
            shell_rc="$HOME/.config/fish/config.fish"
            ;;
        *)
            print_warning "Unknown shell: $current_shell"
            print_warning "Please manually add aliases to your shell config"
            return
            ;;
    esac
    
    if [ -f "$shell_rc" ]; then
        # Check if aliases already exist
        if grep -q "# Oh My OpenCode mode aliases" "$shell_rc"; then
            print_warning "Aliases already exist in $shell_rc"
            print_info "Skipping alias installation"
        else
            cat >> "$shell_rc" << 'EOF'

# Oh My OpenCode mode aliases
alias omof='~/.config/opencode/omo-mode free'
alias omob='~/.config/opencode/omo-mode balanced'
alias omop='~/.config/opencode/omo-mode performance'
alias omo='~/.config/opencode/omo-mode'
EOF
            print_success "Aliases added to $shell_rc"
            print_info "Run 'source $shell_rc' to use aliases in current session"
        fi
    else
        print_warning "Shell config not found: $shell_rc"
        print_warning "Please manually add the aliases"
    fi
}

# Create sample opencode.json if it doesn't exist
create_opencode_config() {
    if [ ! -f "$CONFIG_DIR/opencode.json" ]; then
        print_info "Creating sample opencode.json..."
        
        cat > "$CONFIG_DIR/opencode.json" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "oh-my-opencode",
    "opencode-antigravity-auth@1.4.3"
  ],
  "provider": {
    "opencode": {
      "models": {
        "kimi-k2.5-free": {
          "name": "Kimi K2.5 Free",
          "limit": { "context": 256000, "output": 8192 },
          "modalities": { "input": ["text", "image", "pdf"], "output": ["text"] }
        },
        "kimi-k2.5": {
          "name": "Kimi K2.5 (OpenCode)",
          "limit": { "context": 256000, "output": 8192 },
          "modalities": { "input": ["text", "image", "pdf"], "output": ["text"] }
        },
        "glm-4.7-free": {
          "name": "GLM-4.7 Free",
          "limit": { "context": 128000, "output": 8192 },
          "modalities": { "input": ["text", "image"], "output": ["text"] }
        }
      }
    },
    "kimi-for-coding": {
      "models": {
        "k2p5": {
          "name": "Kimi K2.5 for Coding",
          "limit": { "context": 256000, "output": 8192 },
          "modalities": { "input": ["text", "image", "pdf"], "output": ["text"] }
        }
      }
    }
  }
}
EOF
        print_success "Sample opencode.json created"
        print_warning "IMPORTANT: You need to configure your API keys in opencode.json"
        print_info "See README.md for configuration instructions"
    else
        print_info "opencode.json already exists, skipping"
    fi
}

# Print final instructions
print_instructions() {
    echo ""
    echo "=========================================="
    echo "  OpenCode Configs Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Available modes:"
    echo "  omo         - Show current mode/status"
    echo "  omof        - Free mode (free → subscription → antigravity)"
    echo "  omob        - Balanced mode (subscription → antigravity)"
    echo "  omop        - Performance mode (subscription → opencode → antigravity)"
    echo ""
    echo "Configuration files location: $CONFIG_DIR"
    echo ""
    echo "Next steps:"
    echo "  1. Configure your API keys in: $CONFIG_DIR/opencode.json"
    echo "  2. Run: source ~/.bashrc (or your shell config)"
    echo "  3. Start using: opencode /path/to/project"
    echo ""
    echo "For more info: https://github.com/yourusername/opencode-configs"
    echo ""
}

# Main installation
main() {
    echo "=========================================="
    echo "  OpenCode Configs Installer"
    echo "=========================================="
    echo ""
    
    check_opencode
    backup_existing
    install_configs
    install_script
    install_aliases
    create_opencode_config
    
    print_instructions
}

# Run main function
main "$@"
