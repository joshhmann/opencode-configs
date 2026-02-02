#!/bin/bash

# OpenCode Configs Installer
# This script installs opencode configuration files and sets up environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/opencode"
BACKUP_DIR="$CONFIG_DIR/backups/$(date +%Y%m%d-%H%M%S)"

# Source version utilities library
if [ -f "$SCRIPT_DIR/scripts/lib/version-utils.sh" ]; then
    source "$SCRIPT_DIR/scripts/lib/version-utils.sh"
fi

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

# Create backup with label
create_backup() {
    local label="$1"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="$CONFIG_DIR/backups/${timestamp}-${label}"

    print_info "Creating backup: ${label}"

    if [ ! -d "$CONFIG_DIR" ]; then
        print_warning "Config directory does not exist, nothing to backup"
        return 0
    fi

    mkdir -p "$backup_path"

    # Backup all JSON config files
    local backup_count=0
    for file in "$CONFIG_DIR"/*.json; do
        if [ -f "$file" ] && [ ! -L "$file" ]; then
            cp "$file" "$backup_path/"
            backup_count=$((backup_count + 1))
        fi
    done

    # Backup omo-mode script if it exists
    if [ -f "$CONFIG_DIR/omo-mode" ]; then
        cp "$CONFIG_DIR/omo-mode" "$backup_path/"
        backup_count=$((backup_count + 1))
    fi

    if [ $backup_count -eq 0 ]; then
        rmdir "$backup_path"
        print_warning "No files found to backup"
        return 0
    fi

    print_success "Backup created: $backup_path ($backup_count files)"
    return 0
}

# Restore from backup
restore_from_backup() {
    local backup_dir="$1"

    if [ ! -d "$backup_dir" ]; then
        print_error "Backup directory not found: $backup_dir"
        return 1
    fi

    print_info "Restoring from backup: $backup_dir"

    # Restore all JSON files
    local restore_count=0
    for file in "$backup_dir"/*.json; do
        if [ -f "$file" ]; then
            cp "$file" "$CONFIG_DIR/"
            restore_count=$((restore_count + 1))
        fi
    done

    # Restore omo-mode script if it exists in backup
    if [ -f "$backup_dir/omo-mode" ]; then
        cp "$backup_dir/omo-mode" "$CONFIG_DIR/"
        chmod +x "$CONFIG_DIR/omo-mode"
        restore_count=$((restore_count + 1))
    fi

    if [ $restore_count -eq 0 ]; then
        print_error "No files found in backup"
        return 1
    fi

    print_success "Restored $restore_count files from backup"
    return 0
}

# Download remote configs to temp directory
download_remote_configs() {
    local temp_dir="$1"
    local base_url="https://raw.githubusercontent.com/joshhmann/opencode-configs/main/configs"
    local configs="oh-my-opencode-free.json oh-my-opencode-balanced.json oh-my-opencode-performance.json"

    for config in $configs; do
        if ! curl -fsSL -m 30 "$base_url/$config" -o "$temp_dir/$config" 2>/dev/null; then
            echo "ERROR: Failed to download $config" >&2
            return 1
        fi
    done
    return 0
}

# Validate downloaded configs
validate_configs() {
    local temp_dir="$1"
    local has_error=0

    for config in "$temp_dir"/*.json; do
        if [ -f "$config" ]; then
            local basename=$(basename "$config")

            if ! python3 -c "import json; json.load(open('$config'))" 2>/dev/null; then
                echo "ERROR: Invalid JSON in $basename" >&2
                has_error=1
            fi
        fi
    done

    return $has_error
}

# Store SHA256 hashes of config files
store_config_hashes() {
    local hash_file="$CONFIG_DIR/.config-hashes"
    : > "$hash_file"  # Clear/create
    for config in "$CONFIG_DIR"/oh-my-opencode*.json; do
        if [ -f "$config" ]; then
            sha256sum "$config" >> "$hash_file"
        fi
    done
}

# Check if user has modified config files
has_user_modifications() {
    local hash_file="$CONFIG_DIR/.config-hashes"
    if [ ! -f "$hash_file" ]; then
        return 1  # No hash file, assume no modifications
    fi

    while read -r hash file; do
        if [ -f "$file" ]; then
            local current_hash=$(sha256sum "$file" | awk '{print $1}')
            if [ "$current_hash" != "$hash" ]; then
                return 0  # Modified
            fi
        fi
    done < "$hash_file"

    return 1  # No modifications
}

# Detect which config files have been modified
detect_modified_configs() {
    local hash_file="$CONFIG_DIR/.config-hashes"
    local modified=""

    if [ ! -f "$hash_file" ]; then
        return
    fi

    while read -r hash file; do
        if [ -f "$file" ]; then
            local current_hash=$(sha256sum "$file" | awk '{print $1}')
            if [ "$current_hash" != "$hash" ]; then
                modified="$modified $(basename "$file")"
            fi
        fi
    done < "$hash_file"

    echo "$modified"
}

# Detect installation type (git clone or curl download)
get_install_type() {
    if [ -d "$SCRIPT_DIR/.git" ]; then
        echo "git"
    else
        echo "curl"
    fi
}

# Get remote version from GitHub
get_remote_version() {
    local remote_url="https://raw.githubusercontent.com/joshhmann/opencode-configs/main/configs/oh-my-opencode-balanced.json"

    local remote_data
    remote_data=$(curl -fsSL --max-time 10 --connect-timeout 5 "$remote_url" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$remote_data" ]; then
        print_error "Failed to fetch remote version (network error)" >&2
        return 2
    fi

    local version
    version=$(echo "$remote_data" | grep '"_version"' | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)

    if [ -z "$version" ]; then
        print_error "Failed to extract version from remote config" >&2
        return 2
    fi

    echo "$version"
    return 0
}

# Check for updates
check_updates() {
    print_info "Checking for updates..."

    local install_type=$(get_install_type)

    if [ "$install_type" = "git" ]; then
        cd "$SCRIPT_DIR"

        if ! git fetch origin --quiet 2>/dev/null; then
            print_error "Failed to fetch from git remote"
            return 2
        fi

        local local_commit=$(git rev-parse HEAD 2>/dev/null)
        local remote_commit=$(git rev-parse origin/main 2>/dev/null)

        if [ -z "$local_commit" ] || [ -z "$remote_commit" ]; then
            print_error "Failed to get git commit information"
            return 2
        fi

        if [ "$local_commit" != "$remote_commit" ]; then
            print_success "Update available (git)"
            echo "  Local:  $local_commit"
            echo "  Remote: $remote_commit"
            return 0
        else
            print_success "No updates available (up to date)"
            return 1
        fi
    else
        local config_file="$CONFIG_DIR/oh-my-opencode-balanced.json"

        if [ ! -f "$config_file" ]; then
            print_error "Config file not found: $config_file"
            return 2
        fi

        if ! command -v get_config_version >/dev/null 2>&1; then
            print_error "version-utils.sh not loaded"
            return 2
        fi

        local local_version
        local_version=$(get_config_version "$config_file")
        if [ $? -ne 0 ] || [ -z "$local_version" ]; then
            print_error "Failed to extract local version"
            return 2
        fi

        local remote_version
        remote_version=$(get_remote_version)
        local get_result=$?

        if [ $get_result -ne 0 ]; then
            return $get_result
        fi

        version_compare "$local_version" "$remote_version"
        local compare_result=$?

        case $compare_result in
            0)
                print_success "No updates available (up to date)"
                echo "  Version: $local_version"
                return 1
                ;;
            1)
                print_warning "Local version is newer than remote"
                echo "  Local:  $local_version"
                echo "  Remote: $remote_version"
                return 1
                ;;
            2)
                print_success "Update available"
                echo "  Local:  $local_version"
                echo "  Remote: $remote_version"
                return 0
                ;;
            *)
                print_error "Version comparison failed"
                return 2
                ;;
        esac
    fi
}

perform_update() {
    local auto_confirm=false

    if [ "$1" = "--yes" ]; then
        auto_confirm=true
        shift
    fi

    print_info "Checking for updates..."

    check_updates
    local update_status=$?

    if [ $update_status -eq 1 ]; then
        print_info "No updates available"
        return 0
    elif [ $update_status -ne 0 ]; then
        print_error "Failed to check for updates"
        return 1
    fi

    if has_user_modifications; then
        local modified=$(detect_modified_configs)
        print_warning "You have modified config files: $modified"
        if ! $auto_confirm; then
            read -p "Continue and overwrite modifications? [y/N] " confirm
            [[ "$confirm" =~ [yY] ]] || return 1
        fi
    fi

    if ! $auto_confirm; then
        echo ""
        read -p "Apply update? [y/N] " confirm
        if [[ ! "$confirm" =~ [yY] ]]; then
            print_info "Update cancelled"
            return 0
        fi
    fi

    print_info "Creating backup..."
    if ! create_backup "pre-update"; then
        print_error "Failed to create backup"
        return 1
    fi

    local backup_dir
    backup_dir=$(ls -td "$CONFIG_DIR"/backups/*-pre-update 2>/dev/null | head -1)

    if [ -z "$backup_dir" ]; then
        print_error "Failed to locate backup directory"
        return 1
    fi

    print_info "Downloading updates..."
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    if ! download_remote_configs "$temp_dir"; then
        print_error "Download failed"
        restore_from_backup "$backup_dir"
        return 1
    fi

    print_info "Validating updates..."
    if ! validate_configs "$temp_dir"; then
        print_error "Validation failed - rolling back"
        restore_from_backup "$backup_dir"
        return 1
    fi

    print_info "Applying updates..."
    local update_count=0
    for file in "$temp_dir"/*.json; do
        if [ -f "$file" ]; then
            local basename
            basename=$(basename "$file")
            if [ "$basename" != "opencode.json" ]; then
                cp "$file" "$CONFIG_DIR/"
                update_count=$((update_count + 1))
            fi
        fi
    done

    if [ -L "$CONFIG_DIR/oh-my-opencode.json" ]; then
        rm "$CONFIG_DIR/oh-my-opencode.json"
    fi
    if [ -f "$CONFIG_DIR/oh-my-opencode-balanced.json" ]; then
        ln -sf "$CONFIG_DIR/oh-my-opencode-balanced.json" "$CONFIG_DIR/oh-my-opencode.json"
    fi

    store_config_hashes

    print_success "Update complete ($update_count files updated)"
    print_info "Backup stored at: $backup_dir"
    return 0
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

    store_config_hashes

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

AUTO_CONFIRM=false
PERFORM_UPDATE=false
CHECK_UPDATES=false

for arg in "$@"; do
    case "$arg" in
        --yes)
            AUTO_CONFIRM=true
            ;;
        --update)
            PERFORM_UPDATE=true
            ;;
        --check-updates)
            CHECK_UPDATES=true
            ;;
    esac
done

if [ "$PERFORM_UPDATE" = "true" ]; then
    if [ "$AUTO_CONFIRM" = "true" ]; then
        perform_update --yes
    else
        perform_update
    fi
    exit $?
fi

if [ "$CHECK_UPDATES" = "true" ]; then
    check_updates
    exit $?
fi

main "$@"
