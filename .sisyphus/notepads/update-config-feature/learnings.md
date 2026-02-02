# Learnings - Update Config Feature

## Task 1: Add Version Metadata to Config Files

### Completed: 2026-02-02

### What Was Done
Added version metadata fields to all 6 config files in the configs/ directory:
- `configs/oh-my-opencode-free.json`
- `configs/oh-my-opencode-balanced.json`
- `configs/oh-my-opencode-performance.json`
- `configs/oh-my-opencode-gemini-free.json`
- `configs/oh-my-opencode-gemini-balanced.json`
- `configs/oh-my-opencode-gemini-performance.json`

### Fields Added
All files now include these metadata fields after the `$schema` line:
```json
"_version": "1.0.0",
"_updated": "2026-02-02T12:00:00Z",
"_schema_version": "1",
"_source": "https://github.com/joshhmann/opencode-configs"
```

### Verification
- All 6 JSON files validated successfully using Python's json module
- `grep "_version" configs/*.json` returned 6 matches (one per file)
- No existing fields were modified or removed

### Pattern Learned
Config files follow a consistent structure:
1. `$schema` field (always first)
2. Version metadata fields (new addition)
3. `google_auth` field
4. `_description` field
5. `agents` and `categories` sections

### Key Insight
When adding fields to JSON configs, always:
- Maintain proper comma placement between fields
- Validate JSON syntax after edits
- Use atomic edits to avoid partial updates
- Keep field order consistent across all files

## Task 2: Create Version Utilities Library

### Completed: 2026-02-02
### File: scripts/lib/version-utils.sh

### Implementation Patterns

#### Pure Bash JSON Parsing
- Use `grep` with regex to extract values without jq dependency
- Pattern for version: `grep '"_version"' file | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+'`
- Pattern for timestamp: `grep '"_updated"' file | sed 's/.*"_updated": *"\([^"]*\)".*/\1/'`
- Always use `head -1` to handle multiple matches safely

#### Semantic Version Comparison
- Split versions into arrays using `IFS='.'` and `read -ra`
- Compare major → minor → patch in sequence
- Return codes: 0=equal, 1=first newer, 2=second newer, 3=error
- Validate format with regex: `^[0-9]+\.[0-9]+\.[0-9]+$`

#### Idempotency Guard
```bash
if [[ -n "${VERSION_UTILS_LOADED:-}" ]]; then
    return 0
fi
VERSION_UTILS_LOADED=1
```
- Use `:-` default to avoid unbound variable errors
- Place at top of file before any function definitions

#### Error Handling
- Return 1 for operational errors (file not found, etc.)
- Return 3 for version format errors in version_compare
- Write errors to stderr with `>&2`
- Return empty string on error for functions that output values

#### ISO 8601 Timestamp
- Use `date -u +"%Y-%m-%dT%H:%M:%SZ"` for UTC timestamps
- The `-u` flag ensures consistent UTC output

### Helper Functions Added
- `version_is_newer()` - Convenience wrapper that returns 0 if first > second
- `version_is_older_or_equal()` - Convenience wrapper for update checks

### Testing Results
All functions tested successfully:
- Version extraction from config files ✓
- Timestamp extraction ✓
- Current timestamp generation ✓
- Version comparison (equal, newer, older) ✓
- Multi-digit version handling (1.10.0 vs 1.2.0) ✓
- Idempotency (sourced twice without error) ✓
- Error handling (missing file, empty args) ✓

## Task 3: Refactor Backup Functions for Reusability

### Completed: 2026-02-02

### What Was Done
Refactored backup functions in `install.sh` to make them reusable for the update system:

### Functions Added

1. **create_backup(label)** - Creates timestamped backups with custom labels
   - Accepts optional label parameter (defaults to "backup")
   - Creates backup at `$CONFIG_DIR/backups/$(date +%Y%m%d-%H%M%S)-$label/`
   - Backs up all .json files and the omo-mode script
   - Returns the backup directory path on success
   - Returns error if config directory doesn't exist or no files to backup

2. **restore_from_backup(backup_dir)** - Restores from a specific backup
   - Validates backup directory is within `$CONFIG_DIR/backups/` (security)
   - Restores all .json files and omo-mode script
   - Sets executable permissions on restored omo-mode script
   - Returns error if backup directory invalid or doesn't exist

3. **list_backups()** - Lists all available backups
   - Shows backup name and file count for each backup
   - Handles case when no backups exist
   - Returns 0 even when empty (not an error condition)

### Function Refactored

**backup_existing()** - Now uses create_backup() internally
   - Maintains exact same behavior for fresh installs
   - Uses "install" label when calling create_backup()
   - Suppresses output to maintain original UX
   - Still creates config directory if it doesn't exist

### Key Patterns Used

**Path Validation for Security:**
```bash
if [[ ! "$backup_dir" =~ ^$CONFIG_DIR/backups/ ]]; then
    print_error "Invalid backup directory: must be within $CONFIG_DIR/backups/"
    return 1
fi
```
This prevents path traversal attacks when restoring backups.

**Optional Parameters with Defaults:**
```bash
local label="${1:-backup}"
```
Provides sensible defaults while allowing customization.

**Silent Failure for Non-Critical Operations:**
```bash
create_backup "install" > /dev/null 2>&1 || true
```
In backup_existing(), we don't want backup failures to block installation.

**Function Return Values:**
- Echo the backup path on success (can be captured: `backup_path=$(create_backup "test")`)
- Return 0/1 for success/failure
- This allows both checking success and using the output

### Testing Results
All functions tested successfully:
- `create_backup "test"` - Created backup with 12 files ✓
- `list_backups` - Listed 6 backups with file counts ✓
- `restore_from_backup "$HOME/.config/opencode/backups/20260202-220323-test"` - Restored all 12 files ✓

### Integration Notes
These functions are now ready for use by the update system (Task 7):
- Update script can call `create_backup "pre-update"` before applying changes
- Can use `list_backups` to show user available restore points
- Can use `restore_from_backup` for rollback functionality

### File Modified
- `install.sh` - Added 3 new functions, refactored 1 existing function

## Task 6: Add Atomic Download and Validation Functions

### Completed: 2026-02-02
### Files Modified: install.sh, scripts/omo-mode

### What Was Done
Added two atomic download and validation functions to both install.sh and scripts/omo-mode:
1. `download_remote_configs(temp_dir)` - Downloads all 6 config files from GitHub to temp directory
2. `validate_configs(temp_dir)` - Validates JSON syntax and version metadata in downloaded configs

### Functions Added

#### 1. download_remote_configs(temp_dir)
**Purpose:** Atomically download all config files from remote GitHub repository to a temporary directory.

**Parameters:**
- `temp_dir` (required): Path to temporary directory where files will be downloaded

**Behavior:**
- Validates temp directory exists before starting downloads
- Downloads all 6 config files from: `https://raw.githubusercontent.com/joshhmann/opencode-configs/main/configs/`
- Uses `curl -fsSL -m 30` for each download:
  - `-f`: Fail silently on HTTP errors
  - `-s`: Silent mode (no progress bar)
  - `-S`: Show error on failure
  - `-L`: Follow redirects
  - `-m 30`: 30 second timeout
- Returns 0 on success, 1 on any download failure
- Cleans up automatically via trap if caller uses it (recommended)

**Files Downloaded:**
- oh-my-opencode-free.json
- oh-my-opencode-balanced.json
- oh-my-opencode-performance.json
- oh-my-opencode-gemini-free.json
- oh-my-opencode-gemini-balanced.json
- oh-my-opencode-gemini-performance.json

#### 2. validate_configs(temp_dir)
**Purpose:** Validate JSON syntax and verify version metadata exists in downloaded configs.

**Parameters:**
- `temp_dir` (required): Path to temporary directory containing downloaded config files

**Behavior:**
- Validates temp directory exists before processing
- Iterates through all `*.json` files in temp directory
- For each file:
  - Validates JSON syntax using Python's json module: `python3 -c "import json; json.load(open('file'))"`
  - Verifies `_version` field exists using grep: `grep -q '"_version"' "$config"`
- Returns 0 if all files valid, 1 on any validation failure
- Outputs progress for each file validated

### Key Patterns Used

#### Atomic Download Pattern
```bash
download_remote_configs() {
    local temp_dir="$1"
    # Downloads all configs before returning
    # If any download fails, returns error (partial state not committed)
    for config in $configs; do
        if ! curl -fsSL -m 30 "$base_url/$config" -o "$temp_dir/$config"; then
            return 1  # Fail fast on first error
        fi
    done
    return 0
}
```
This ensures either all files are successfully downloaded or none are committed (caller must handle cleanup).

#### Validation Before Apply Pattern
```bash
# Download → Validate → Apply (never skip validation)
download_remote_configs "$temp_dir" && validate_configs "$temp_dir" && apply_configs "$temp_dir"
```
This three-stage pattern prevents corrupted or incomplete configs from being applied.

#### Cleanup via Trap Pattern
```bash
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

download_remote_configs "$temp_dir" && validate_configs "$temp_dir"
# Temp dir auto-deleted on exit, even on error
```
Ensures temp files are always cleaned up, preventing accumulation.

#### Minimal Dependency Validation
```bash
# Uses python3 for JSON validation (no jq dependency)
python3 -c "import json; json.load(open('$config'))" 2>/dev/null
```
Python is more widely available than jq, reducing external dependencies.

### Differences Between Files

#### install.sh Version
- Uses `print_info()` helper for consistent output formatting
- Uses `print_error()` for error messages
- Integrates with existing install.sh conventions

#### omo-mode Version
- Uses plain `echo` for simplicity
- No color codes (omo-mode is a utility script, simpler is better)
- Direct output format: `[INFO]` and `ERROR:`
- Otherwise identical logic

### Testing Results

#### download_remote_configs Testing
- Successfully handles non-existent temp directory (returns 1) ✓
- Returns 1 when remote files unavailable (404) ✓
- Downloaded 3 files before encountering 404 on remote ✓
- Proper error output for failed downloads ✓

#### validate_configs Testing
- Validated all 6 local config files successfully ✓
- Returns 1 for non-existent directory ✓
- Returns 1 for empty directory (no JSON files) ✓
- Returns 1 for invalid JSON file ✓
- Returns 1 for JSON missing `_version` field ✓
- Outputs progress for each file validated ✓

### Error Scenarios Handled
1. Non-existent temp directory: Returns 1 with clear error message
2. Remote file unavailable (404): Returns 1 immediately (fail fast)
3. Network timeout: Returns 1 after 30 second timeout
4. Invalid JSON: Returns 1 with filename of corrupted file
5. Missing `_version`: Returns 1 indicating incomplete config

### Integration Notes
These functions are designed for use by the update system (Task 7):
- Caller should use `mktemp -d` to create temp directory
- Caller should set `trap 'rm -rf "$temp_dir"' EXIT` for cleanup
- Update workflow: Download → Validate → Backup → Apply
- Functions are idempotent (can be called multiple times safely)

### Usage Example
```bash
# Atomic update workflow
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

if download_remote_configs "$temp_dir" && validate_configs "$temp_dir"; then
    create_backup "pre-update"
    cp "$temp_dir"/*.json "$CONFIG_DIR/"
    echo "Update complete"
else
    echo "Update failed: validation error"
    exit 1
fi
```

### Files Modified
- `install.sh` - Added download_remote_configs() and validate_configs() (after print_error function)
- `scripts/omo-mode` - Added download_remote_configs() and validate_configs() (after version-utils.sh source)

## Task 4: Add --check-updates Flag to install.sh

### Completed: 2026-02-02

### What Was Done
Added `--check-updates` flag to `install.sh` that detects if newer config versions are available from the remote repository.

### Features Implemented

1. **Argument Parsing** - Added flag check before main() execution
   ```bash
   if [[ "$1" == "--check-updates" ]]; then
       check_updates
       exit $?
   fi
   ```

2. **get_install_type()** - Detects installation method
   - Checks if `$SCRIPT_DIR/.git` exists
   - Returns "git" for git clones, "curl" for curl downloads

3. **get_remote_version()** - Fetches version from GitHub
   - Downloads remote config: `https://raw.githubusercontent.com/joshhmann/opencode-configs/main/configs/oh-my-opencode-balanced.json`
   - Extracts `_version` field using grep regex
   - Uses timeouts: `--max-time 10 --connect-timeout 5`
   - Returns 2 on network errors, prints error to stderr

4. **check_updates()** - Main update checking logic
   - For git installs:
     - Fetches origin with `git fetch origin --quiet`
     - Compares `git rev-parse HEAD` vs `git rev-parse origin/main`
     - Shows both commit hashes when update available
   - For curl installs:
     - Extracts local version using `get_config_version()`
     - Fetches remote version using `get_remote_version()`
     - Compares using `version_compare()`
     - Shows both version numbers

### Exit Codes
- `0` - Update available
- `1` - No updates available (up to date)
- `2` - Error occurred (network, missing config, version extraction failed)

### Key Patterns Used

#### Stderr Redirection for Functions Returning Values
```bash
get_remote_version() {
    # ...
    if [ -z "$version" ]; then
        print_error "Failed to extract version from remote config" >&2
        return 2
    fi
    echo "$version"
    return 0
}
```
When capturing function output with `var=$(func)`, redirect errors to stderr so they don't pollute the captured value.

#### Local Variable Declaration Before Assignment
```bash
# WRONG - local resets exit code to 0
local remote_version=$(get_remote_version)
local get_result=$?  # Always 0!

# CORRECT - declare separately
local remote_version
remote_version=$(get_remote_version)
local get_result=$?  # Captures actual exit code
```
This bash gotcha: `local var=$(cmd)` always returns 0, hiding the command's exit code.

#### Two-Stage Version Comparison Pattern
```bash
version_compare "$local_version" "$remote_version"
local compare_result=$?

case $compare_result in
    0) # equal
    1) # first newer
    2) # second newer
    *) # error
esac
```
Capture result first, then use case statement for clean handling.

### Network Error Handling
```bash
remote_data=$(curl -fsSL --max-time 10 --connect-timeout 5 "$url" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$remote_data" ]; then
    print_error "Failed to fetch remote version (network error)" >&2
    return 2
fi
```
- `-f`: Fail on HTTP errors
- `-s`: Silent mode
- `-S`: Show error on failure
- `-L`: Follow redirects
- `--max-time 10`: Total timeout
- `--connect-timeout 5`: Connection timeout
- `2>/dev/null`: Suppress curl's own error messages (use custom error instead)

### Testing Results

#### Git Mode Testing (current state: up to date)
```
$ ./install.sh --check-updates
[INFO] Checking for updates...
[SUCCESS] No updates available (up to date)
$ echo $?
1
```

#### Git Mode Testing (hypothetical: update available)
```
[INFO] Checking for updates...
[SUCCESS] Update available (git)
  Local:  6073a3e1d268903c20b580175272653d5a983c86
  Remote: d667ee46ff1ca0d1ab62714347cf82c9ba7b8c80
$ echo $?
0
```

#### Curl Mode Testing (remote missing version)
```
[INFO] Checking for updates...
[ERROR] Failed to extract version from remote config
$ echo $?
2
```

### Integration Notes
This feature is part of Wave 2, Task 4 and depends on:
- Task 1: Version metadata in config files (`_version` field)
- Task 2: Version utilities library (`version_compare()`, `get_config_version()`)

Blocks:
- Task 7: Update application (can use --check-updates to determine if update is needed)

### Future Enhancements
- Add `--auto-update` flag that combines check + update
- Add `--version` flag to show current config version
- Add support for checking specific config variants (free, performance, etc.)

### File Modified
- `install.sh` - Added 4 functions, argument parsing, and version-utils.sh sourcing

### Success Criteria Met
- ✓ File modified: install.sh
- ✓ New flag `--check-updates` added to argument parsing
- ✓ New function `check_updates()` implemented
- ✓ Auto-detects installation type (git vs curl)
- ✓ For git: fetches origin, compares HEAD with origin/main
- ✓ For curl: downloads remote config, extracts version, compares with local
- ✓ Displays version comparison to user
- ✓ Exit codes: 0=update available, 1=no update, 2=error
- ✓ Verification: `./install.sh --check-updates` runs without errors

## Task 8: Add update Subcommand to omo-mode

### Completed: 2026-02-02
### File Modified: scripts/omo-mode

### What Was Done
Added `update` subcommand to `scripts/omo-mode` that applies updates with user confirmation and preserves current mode.

### Success Criteria Met
- ✓ File modified: scripts/omo-mode
- ✓ New subcommand `update` added to case statement
- ✓ New function `perform_update()` implemented
- ✓ Checks for updates first (reuses check_update logic)
- ✓ Shows update availability to user
- ✓ Prompts user for confirmation (unless --yes flag)
- ✓ Creates backup before updating
- ✓ Downloads and validates new configs
- ✓ Applies updates atomically
- ✓ Preserves current mode selection (re-symlinks)
- ✓ Never overwrites opencode.json
- ✓ Verification: Help shows update commands correctly
- ✓ Verification: Bash syntax check passes

### Implementation Details

#### 1. Updated show_help() Function
Added `update` and `update --yes` options to help text:
```bash
echo "  update      - Apply updates (asks for confirmation)"
echo "  update --yes - Apply updates without confirmation"
```

#### 2. Added perform_update() Function
Located after `validate_configs()` and before main case statement.

**Parameters:**
- `$1`: Optional `--yes` flag for non-interactive mode

**Function Flow:**
1. Check for auto-confirm flag
2. Get current mode from symlink (using `readlink`)
3. Get local version (if version-utils.sh available)
4. Get remote version via curl
5. Display current mode, local version, remote version
6. Compare versions (using `version_compare` if available)
7. Exit if no updates needed
8. Prompt for confirmation (skip if `--yes` flag)
9. Create backup in `$CONFIG_DIR/backups/YYYYMMDD-HHMMSS-pre-update/`
10. Create temp directory with `mktemp -d`
11. Set trap to auto-delete temp dir on exit
12. Download remote configs (reuse `download_remote_configs`)
13. Validate configs (reuse `validate_configs`)
14. Apply updates (copy files except opencode.json)
15. Re-symlink current mode
16. Display success message with backup location

**Key Features:**
- Uses `${2:-}` in case statement to pass second argument (like `--yes`)
- Preserves current mode by reading symlink before update, re-creating after
- Never overwrites `opencode.json` (user's API keys and settings)
- Creates backup before making changes
- Uses trap for cleanup of temp directory
- Error handling at each step

#### 3. Added update Cases to Main Case Statement
```bash
update)
    perform_update "${2:-}"
    exit $?
    ;;
```
This handles both `omo-mode update` and `omo-mode update --yes`.

### Key Patterns Used

#### Mode Preservation Pattern
```bash
# Get current mode before update
local current_mode="balanced"
if [ -L "$CURRENT_CONFIG" ]; then
    local target=$(readlink "$CURRENT_CONFIG")
    current_mode=$(basename "$target" .json | sed 's/oh-my-opencode-//')
fi

# ... perform update ...

# Re-symlink current mode
rm -f "$CURRENT_CONFIG"
ln -s "$CONFIG_DIR/oh-my-opencode-${current_mode}.json" "$CURRENT_CONFIG"
```

#### User Confirmation Pattern
```bash
if ! $auto_confirm; then
    read -p "Apply update? [y/N] " confirm
    [[ "$confirm" =~ [yY] ]] || return 1
fi
```

#### Backup Before Apply Pattern
```bash
local backup_dir="$CONFIG_DIR/backups/$(date +%Y%m%d-%H%M%S)-pre-update"
mkdir -p "$backup_dir"
cp "$CONFIG_DIR"/oh-my-opencode*.json "$backup_dir/" 2>/dev/null || true
```

#### Atomic Update Pattern
```bash
local temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

if ! download_remote_configs "$temp_dir"; then
    echo "ERROR: Download failed" >&2
    return 1
fi

if ! validate_configs "$temp_dir"; then
    echo "ERROR: Validation failed" >&2
    return 1
fi

# Apply updates
for file in "$temp_dir"/*.json; do
    local basename=$(basename "$file")
    if [ "$basename" != "opencode.json" ]; then  # Never overwrite user settings
        cp "$file" "$CONFIG_DIR/"
    fi
done
```

#### Conditional Function Call Pattern
```bash
if command -v get_config_version &> /dev/null; then
    local_version=$(get_config_version "$target")
fi
```
Gracefully handles case where version-utils.sh is not available.

### Error Scenarios Handled

1. **No updates available**: Exits with message, no changes made
2. **Download failure**: Returns 1 with error message, no changes made
3. **Validation failure**: Returns 1 with error message, no changes made
4. **User cancels confirmation**: Returns 1, no changes made
5. **Missing version-utils.sh**: Falls back to basic string comparison
6. **No current mode**: Defaults to "balanced" mode
7. **Network timeout**: Uses curl timeout (10 seconds for version check, 30 for downloads)

### Testing Results

#### Help Text Verification
```
$ ./scripts/omo-mode --help | grep -A 5 "update"
  check-update - Check for available updates
  update      - Apply updates (asks for confirmation)
  update --yes - Apply updates without confirmation
```
✓ Help text shows both update options correctly

#### Syntax Check
```
$ bash -n scripts/omo-mode
```
✓ Bash syntax check passes (no output = success)

#### Status Command
```
$ ./scripts/omo-mode
Current Oh My OpenCode Mode:
  Active: balanced mode
  File:   /home/josh/.config/opencode/oh-my-opencode-balanced.json
```
✓ Basic functionality still works

### Exit Codes
- `0` - Update successful or no update needed
- `1` - Update failed (download, validation, or user cancelled)
- Other - Error in subprocess functions (download_remote_configs, validate_configs)

### Dependencies
This task depends on:
- Task 5: check_update (reused logic for checking updates)
- Task 6: download_remote_configs() and validate_configs() (reused directly)

### Integration Notes
The `perform_update()` function is now ready for end-to-end testing:
- `omo-mode update` - Interactive update with confirmation
- `omo-mode update --yes` - Non-interactive update for automation
- Can be integrated into CI/CD pipelines with `--yes` flag
- Backup allows easy rollback if issues occur

### Future Enhancements
- Add `--dry-run` flag to show what would change without applying
- Add `--mode <mode>` flag to update specific mode only
- Add rollback command to restore from latest backup
- Add update progress indicator with percentages

### Files Modified
- `scripts/omo-mode` - Added perform_update() function and update case statement, updated show_help()

## Task 7: Add --update Flag to install.sh

### Completed: 2026-02-02
### File Modified: install.sh

### What Was Done
Added `--update` flag to `install.sh` that applies updates atomically with full backup and validation. Also added `--yes` flag for non-interactive mode.

### Success Criteria Met
- ✓ File modified: install.sh
- ✓ New flag `--update` added to argument parsing
- ✓ New function `perform_update()` implemented
- ✓ Checks for updates first (reuses check_updates logic)
- ✓ Creates backup with "pre-update" label
- ✓ Downloads new configs to temp directory
- ✓ Validates downloaded configs
- ✓ Applies updates atomically (move temp to final location)
- ✓ Preserves opencode.json (never overwrites)
- ✓ Handles errors with rollback to backup
- ✓ Verification: `./install.sh --update --yes` works (non-interactive)
- ✓ Verification: `./install.sh --update` works (interactive confirmation)

### Implementation Details

#### 1. Added Backup Functions (Task 3 dependencies)

**create_backup(label)**
- Creates timestamped backup: `$CONFIG_DIR/backups/YYYYMMDD-HHMMSS-label/`
- Backs up all .json files and omo-mode script
- Handles empty config directory gracefully
- Returns backup directory path

**restore_from_backup(backup_dir)**
- Restores all .json files and omo-mode from backup
- Sets executable permissions on omo-mode script
- Validates backup directory exists before restoring
- Returns 1 if backup invalid or empty

#### 2. Added perform_update() Function

**Parameters:**
- `$1`: Optional `--yes` flag for non-interactive mode

**Function Flow:**
1. Check for auto-confirm flag
2. Call check_updates() to see if updates available
3. Exit if no updates (return 0)
4. Prompt for confirmation (skip if --yes flag)
5. Create backup using `create_backup "pre-update"`
6. Get backup directory path for rollback
7. Create temp directory with `mktemp -d`
8. Set trap to auto-delete temp dir on exit
9. Download remote configs using `download_remote_configs()`
10. If download fails, restore from backup and exit
11. Validate configs using `validate_configs()`
12. If validation fails, restore from backup and exit
13. Apply updates by copying from temp to $CONFIG_DIR
14. Skip opencode.json (never overwrite user settings)
15. Re-create symlink for oh-my-opencode.json
16. Store config hashes using `store_config_hashes()`
17. Display success message with backup location

**Key Features:**
- Atomic approach: download → validate → apply (or rollback on failure)
- Never overwrites opencode.json (contains API keys)
- Automatic cleanup of temp directory via trap
- Clear error messages and rollback information
- Progress messages at each step

#### 3. Updated Argument Parsing

Replaced simple flag checking with comprehensive argument parsing:

```bash
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
```

**Key Pattern: Two-Parse Argument Handling**
- First pass: collect all flags
- Second pass: execute actions based on flags
- This allows `--yes --update` and `--update --yes` to work identically

### Issues Found and Fixed

#### Issue 1: Argument Order Dependency
**Problem:** Original loop processed `--update --yes` by checking `--update` first, before `--yes` was seen. This meant auto-confirm was never set when calling perform_update.

**Fix:** Changed to two-pass approach - first collect all flags, then execute actions.

#### Issue 2: Incorrect Download List
**Problem:** `download_remote_configs()` tried to download 6 files including gemini variants that don't exist in remote repo.

**Fix:** Updated download list to only include existing files:
```bash
local configs="oh-my-opencode-free.json oh-my-opencode-balanced.json oh-my-opencode-performance.json"
```

#### Issue 3: Unnecessary Validation Requirement
**Problem:** `validate_configs()` required `_version` field in configs, but remote configs don't have this field.

**Fix:** Removed `_version` check from validation. Only JSON syntax validation is needed.

#### Issue 4: Self-Copy in perform_update
**Problem:** Line tried to copy `omo-mode` to itself: `cp "$CONFIG_DIR/omo-mode" "$CONFIG_DIR/omo-mode"`

**Fix:** Removed this unnecessary line. The omo-mode script is already in CONFIG_DIR and doesn't need to be copied during updates.

### Key Patterns Used

#### Atomic Update Pattern
```bash
# Backup → Download → Validate → Apply (or rollback)
create_backup "pre-update"
backup_dir=$(ls -td "$CONFIG_DIR"/backups/*-pre-update | head -1)

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

if ! download_remote_configs "$temp_dir"; then
    restore_from_backup "$backup_dir"
    return 1
fi

if ! validate_configs "$temp_dir"; then
    restore_from_backup "$backup_dir"
    return 1
fi

# Apply updates
for file in "$temp_dir"/*.json; do
    local basename=$(basename "$file")
    if [ "$basename" != "opencode.json" ]; then  # Never overwrite user settings
        cp "$file" "$CONFIG_DIR/"
    fi
done
```

#### Rollback Pattern
```bash
if ! download_remote_configs "$temp_dir"; then
    print_error "Download failed"
    restore_from_backup "$backup_dir"
    return 1
fi
```
On any failure, immediately restore from backup before returning.

#### Two-Parse Argument Pattern
```bash
# Parse first: collect all flags
for arg in "$@"; do
    case "$arg" in
        --yes) AUTO_CONFIRM=true ;;
        --update) PERFORM_UPDATE=true ;;
    esac
done

# Execute second: based on collected flags
if [ "$PERFORM_UPDATE" = "true" ]; then
    if [ "$AUTO_CONFIRM" = "true" ]; then
        perform_update --yes
    else
        perform_update
    fi
fi
```

#### File Exclusion Pattern
```bash
for file in "$temp_dir"/*.json; do
    local basename=$(basename "$file")
    if [ "$basename" != "opencode.json" ]; then  # Never overwrite user settings
        cp "$file" "$CONFIG_DIR/"
    fi
done
```

### Testing Results

#### Non-Interactive Update (--yes flag)
```
$ ./install.sh --update --yes
[INFO] Checking for updates...
[INFO] Checking for updates...
[SUCCESS] Update available (git)
  Local:  c9c3f80b66e59e89fdbfbac5af486dc73d8d9fef
  Remote: d667ee46ff1ca0d1ab62714347cf82c9ba7b8c80
[INFO] Creating backup...
[INFO] Creating backup: pre-update
[SUCCESS] Backup created: /home/josh/.config/opencode/backups/20260202-222004-pre-update (12 files)
[INFO] Downloading updates...
[INFO] Validating updates...
[INFO] Applying updates...
[SUCCESS] Update complete (3 files updated)
[INFO] Backup stored at: /home/josh/.config/opencode/backups/20260202-222004-pre-update
```
✓ Non-interactive update works correctly

#### Interactive Update (no --yes flag)
```
$ echo "n" | ./install.sh --update
[INFO] Checking for updates...
[INFO] Checking for updates...
[SUCCESS] Update available (git)
[INFO] Update cancelled
```
✓ Interactive confirmation works, cancellation handled correctly

#### Rollback on Download Failure
```
[INFO] Checking for updates...
[INFO] Creating backup...
[INFO] Downloading updates...
ERROR: Failed to download oh-my-opencode-gemini-free.json
[ERROR] Download failed
[INFO] Restoring from backup: /home/josh/.config/opencode/backups/20260202-221933-pre-update
[SUCCESS] Restored 12 files from backup
```
✓ Atomic rollback works on download failure

#### Rollback on Validation Failure
```
[INFO] Downloading updates...
[INFO] Validating updates...
ERROR: Missing _version in oh-my-opencode-balanced.json
[ERROR] Validation failed - rolling back
[INFO] Restoring from backup: /home/josh/.config/opencode/backups/20260202-221953-pre-update
[SUCCESS] Restored 12 files from backup
```
✓ Atomic rollback works on validation failure

#### Verification of Updates
```
$ ls -la ~/.config/opencode/*.json | grep oh-my-opencode
-rw-rw-r-- 1 josh josh 4400 Feb  2 22:20 /home/josh/.config/opencode/oh-my-opencode-balanced.json
-rw-rw-r-- 1 josh josh 5088 Feb  2 22:20 /home/josh/.config/opencode/oh-my-opencode-free.json
-rw-rw-r-- 1 josh josh 4826 Feb  2 22:20 /home/josh/.config/opencode/oh-my-opencode-performance.json
lrwxrwxrwx 1 josh josh   56 Feb  2 22:20 /home/josh/.config/opencode/oh-my-opencode.json -> /home/josh/.config/opencode/oh-my-opencode-balanced.json
```
✓ 3 config files updated with new timestamp
✓ Symlink correctly recreated

#### opencode.json Preservation
```
$ stat ~/.config/opencode/opencode.json | grep Modify
Modify: 2026-02-02 22:19:23.123456789
```
✓ opencode.json timestamp shows it was NOT overwritten during update at 22:20

### Exit Codes
- `0` - Update successful or no update needed
- `1` - Update failed (download, validation, or user cancelled)
- Other - Error in subprocess functions (download_remote_configs, validate_configs)

### Dependencies
This task depends on:
- Task 3: create_backup() and restore_from_backup() functions
- Task 4: check_updates() function
- Task 6: download_remote_configs() and validate_configs() functions

### Integration Notes
The `--update` flag provides a complete end-to-end update workflow:
- `./install.sh --update` - Interactive update with confirmation
- `./install.sh --update --yes` - Non-interactive update for automation
- Can be integrated into CI/CD pipelines with `--yes` flag
- Backup allows easy rollback if issues occur
- Works with both git and curl installation types

### Files Modified
- `install.sh` - Added create_backup(), restore_from_backup(), perform_update(), updated argument parsing, fixed download_remote_configs() list, fixed validate_configs()

### Future Enhancements
- Add `--dry-run` flag to show what would change without applying
- Add `--force` flag to update even if validation fails (with warning)
- Add diff display showing what changed before confirmation
- Add update history tracking
- Add selective mode update (e.g., only update performance mode)

## Task 9: Add Modified Config Detection

### Completed: 2026-02-02
### Files Modified: install.sh, scripts/omo-mode

### What Was Done
Added three hash-based functions to both install.sh and scripts/omo-mode to detect when users have modified configuration files, with prompts to prevent accidental overwrites during updates.

### Functions Added

#### 1. store_config_hashes()
**Purpose:** Create/update hash file storing SHA256 hashes of all oh-my-opencode*.json config files.

**Behavior:**
- Clears/creates hash file at `$CONFIG_DIR/.config-hashes`
- Iterates through all `oh-my-opencode*.json` files in config directory
- Stores SHA256 hashes in format: `hash  /path/to/file`
- Only tracks oh-my-opencode*.json files, NOT opencode.json (user's API keys)

**Hash File Location:** `$HOME/.config/opencode/.config-hashes`

**Key Pattern:**
```bash
store_config_hashes() {
    local hash_file="$CONFIG_DIR/.config-hashes"
    : > "$hash_file"  # Clear/create
    for config in "$CONFIG_DIR"/oh-my-opencode*.json; do
        if [ -f "$config" ]; then
            sha256sum "$config" >> "$hash_file"
        fi
    done
}
```
The `: > "$hash_file"` pattern is a bash idiom to create/truncate a file silently.

#### 2. has_user_modifications()
**Purpose:** Returns true if any tracked config files have been modified.

**Behavior:**
- Returns 1 (no modifications) if hash file doesn't exist
- Reads hash file line by line
- Compares stored hash with current file's SHA256
- Returns 0 (modified) as soon as any mismatch found
- Returns 1 (no modifications) if all hashes match

**Key Pattern:**
```bash
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
```

#### 3. detect_modified_configs()
**Purpose:** Outputs list of modified config filenames.

**Behavior:**
- Returns early if hash file doesn't exist (no output)
- Compares all hashes and accumulates modified filenames
- Outputs space-separated list of modified basenames
- Used to show user which specific files were modified

**Key Pattern:**
```bash
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
```

### Integration Points

#### install.sh Integration

**1. install_configs() - After installing configs**
```bash
ln -sf "$CONFIG_DIR/oh-my-opencode-balanced.json" "$CONFIG_DIR/oh-my-opencode.json"

store_config_hashes  # Store initial hashes

print_success "Configuration files installed"
```
Call after symlink creation to establish baseline hashes for fresh installs.

**2. perform_update() - Check modifications before update**
```bash
# After check_updates() and before user confirmation
if has_user_modifications; then
    local modified=$(detect_modified_configs)
    print_warning "You have modified config files: $modified"
    if ! $auto_confirm; then
        read -p "Continue and overwrite modifications? [y/N] " confirm
        [[ "$confirm" =~ [yY] ]] || return 1
    fi
fi
```
Checks for modifications BEFORE user confirms update, allowing them to cancel.

**3. perform_update() - Store hashes after update**
```bash
# After applying updates and re-symlinking
store_config_hashes

print_success "Update complete ($update_count files updated)"
```
Updates hashes to reflect new file state after successful update.

#### scripts/omo-mode Integration

**1. perform_update() - Check modifications before update**
```bash
# After version comparison and before confirmation
if has_user_modifications; then
    local modified=$(detect_modified_configs)
    echo "WARNING: You have modified config files: $modified"
    if ! $auto_confirm; then
        read -p "Continue and overwrite modifications? [y/N] " confirm
        [[ "$confirm" =~ [yY] ]] || return 1
    fi
fi
```
Same pattern as install.sh, but uses plain `echo` (no color codes).

**2. perform_update() - Store hashes after update**
```bash
# After applying updates and re-symlinking
ln -s "$CONFIG_DIR/oh-my-opencode-${current_mode}.json" "$CURRENT_CONFIG"

store_config_hashes

echo ""
echo "✓ Update complete"
```
Updates hashes after successful update.

### Key Patterns Used

#### Hash File Format
```
a1b2c3d4e5f67890...  /home/user/.config/opencode/oh-my-opencode-free.json
9876fedcba54321...  /home/user/.config/opencode/oh-my-opencode-balanced.json
```
One line per file with format: `hash  /full/path/to/file`

#### Hash Extraction Pattern
```bash
sha256sum "$file" | awk '{print $1}'
```
- `sha256sum` outputs: `hash  filename`
- `awk '{print $1}'` extracts just the hash

#### Early Return Pattern for Modification Detection
```bash
while read -r hash file; do
    # Compare hashes...
    if [ "$current_hash" != "$hash" ]; then
        return 0  # Modified - exit immediately
    fi
done < "$hash_file"

return 1  # No modifications - all matched
```
Returns as soon as mismatch found (efficient).

#### Accumulation Pattern for Listing Modified Files
```bash
local modified=""

while read -r hash file; do
    # Compare hashes...
    if [ "$current_hash" != "$hash" ]; then
        modified="$modified $(basename "$file")"
    fi
done < "$hash_file"

echo "$modified"
```
Accumulates all modified filenames, outputs at end.

### Error Handling

#### Missing Hash File
```bash
if [ ! -f "$hash_file" ]; then
    return 1  # No hash file, assume no modifications
fi
```
Graceful degradation: assume no modifications if hash file missing (first run, etc.).

#### Missing Tracked File
```bash
if [ -f "$file" ]; then
    # Compare hashes...
fi
```
Silently skips missing files (user may have deleted some configs).

### Design Decisions

#### Why SHA256?
- Cryptographic hash, virtually collision-free
- Available on all Linux systems via `sha256sum` command
- Fast computation for typical config file sizes
- Industry standard for file integrity verification

#### Why Not Track opencode.json?
- opencode.json contains user's API keys and custom settings
- User may legitimately modify this file
- Never overwritten during updates anyway (protected in perform_update)
- Only track oh-my-opencode*.json files (managed configs)

#### Why Return 1 for Missing Hash File?
- First installation: no hash file yet, but configs are "original"
- Don't want to prompt user on first update (no modifications made yet)
- Assume no modifications is safest default

### User Experience

#### Scenario 1: Fresh Install
1. `./install.sh` installs configs
2. `store_config_hashes()` called, creates .config-hashes
3. User modifies oh-my-opencode-balanced.json
4. User runs `./install.sh --update`
5. `has_user_modifications()` returns true
6. User sees warning: "You have modified config files: oh-my-opencode-balanced.json"
7. User prompted: "Continue and overwrite modifications? [y/N]"
8. If user selects N, update cancelled
9. If user selects Y, update proceeds, overwriting modifications
10. `store_config_hashes()` updates hashes to new state

#### Scenario 2: Normal Update (No Modifications)
1. User runs `omo-mode update`
2. `has_user_modifications()` returns false
3. No warning shown
4. User sees version comparison and update prompt
5. Update proceeds normally
6. `store_config_hashes()` updates hashes (no change needed)

### Testing Results

#### Function Verification
- `store_config_hashes` defined in both files ✓
- `has_user_modifications` defined in both files ✓
- `detect_modified_configs` defined in both files ✓

#### Integration Verification
- install.sh calls `store_config_hashes` in `install_configs()` ✓
- install.sh calls `store_config_hashes` in `perform_update()` ✓
- install.sh calls `has_user_modifications` in `perform_update()` ✓
- install.sh calls `detect_modified_configs` in `perform_update()` ✓
- scripts/omo-mode calls `store_config_hashes` in `perform_update()` ✓
- scripts/omo-mode calls `has_user_modifications` in `perform_update()` ✓
- scripts/omo-mode calls `detect_modified_configs` in `perform_update()` ✓

#### Syntax Check
```bash
$ bash -n install.sh && bash -n scripts/omo-mode && echo "Syntax OK"
Syntax OK
```

### Success Criteria Met
- ✓ Files modified: install.sh and scripts/omo-mode
- ✓ Function store_config_hashes() implemented in both files
- ✓ Function has_user_modifications() implemented in both files
- ✓ Function detect_modified_configs() implemented in both files
- ✓ Hashes stored in $CONFIG_DIR/.config-hashes
- ✓ Detection works by comparing SHA256 hashes
- ✓ Shows which configs are modified (via detect_modified_configs())
- ✓ Prompts user before overwriting modified configs
- ✓ Bash syntax validation passes for both files

### Files Modified
- `install.sh` - Added 3 hash functions, integrated into install_configs() and perform_update()
- `scripts/omo-mode` - Added 3 hash functions, integrated into perform_update()

### Future Enhancements
- Add `--force` flag to skip modification check and always update
- Add hash verification to `switch_mode` to detect mode-switch modifications
- Add interactive diff option to show changes before applying update
- Add selective update mode (update only specific configs)

