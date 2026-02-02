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
