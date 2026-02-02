# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-02-02

### Added
- Version metadata in all config files (`_version`, `_updated`, `_schema_version`, `_source`)
- Update checking via `install.sh --check-updates` flag
- Update checking via `omo-mode check-update` subcommand
- Update application via `install.sh --update` flag with `--yes` for non-interactive mode
- Update application via `omo-mode update` subcommand with `--yes` for non-interactive mode
- Atomic update mechanism with automatic backup creation
- Config validation before applying updates
- Modified config detection using SHA256 hashes
- User prompts before overwriting modified configs
- Version utilities library (`scripts/lib/version-utils.sh`)
- Backup management functions (create_backup, restore_from_backup, list_backups)

### Changed
- Enhanced install.sh with reusable backup functions
- Updated omo-mode to source version utilities

## [1.0.0] - 2026-01-30

### Added
- Initial release with 6 configuration modes:
  - Free mode (opencode/kimi-k2.5-free)
  - Balanced mode (kimi-for-coding/k2p5)
  - Performance mode (kimi-for-coding/k2p5 with fallbacks)
  - Gemini Free mode (with Gemini flash fallback)
  - Gemini Balanced mode (Google-first)
  - Gemini Performance mode (Google-first with extensive fallbacks)
- Mode switching via `omo-mode` script
- Shell aliases (omof, omob, omop, etc.)
- Installation script (`install.sh`)
- Automatic backup during installation
- Support for oh-my-opencode schema
