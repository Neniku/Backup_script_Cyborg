# Changelog

All notable changes to this project will be documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) — [Semantic Versioning](https://semver.org/)

---

## [Unreleased]

### Added
- GitHub Actions CI: shellcheck linting, syntax validation, smoke test, auto-release on tags
- `.gitignore`
- `CHANGELOG.md`
- SSH key-based auth for SFTP via `SSH_KEY_PATH` environment variable
- `CYBORG_PASS` env var to avoid password in process list and shell history

### Changed
- Variables renamed: `param1/2/3/4` → `SOURCE_DIR`, `DEST_SERVER`, `REMOTE_USER`, `REMOTE_PASS`
- `smb_path` → `SMB_PATH`
- Password length increased from 16 to 24 characters
- `set -uo pipefail` (dropped `-e`; error handling is done explicitly via `FATAL_ERROR`)

### Fixed
- `cd` replaced with subshells — no longer mutates process working directory (SC2164)
- File list loop uses `mapfile` instead of word-splitting (handles filenames with spaces)
- `while IFS= read -r` for safe path handling in compression loop
- `generate_random_password` uses `openssl rand` to avoid modulo bias

### Security
- Encryption password no longer written to the main log file — only included in the email report

---

## [1.0.0]

### Added
- AES256 encryption with randomly generated password
- SHA256 integrity hashes for all encrypted archives
- Redundant dual upload: SFTP + SMB
- Checkpoint/resume system for interrupted backups
- Lock file to prevent concurrent executions
- CLI and GUI (Zenity) modes
- HTML email report

[Unreleased]: https://github.com/Neniku/Backup_script_Cyborg/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Neniku/Backup_script_Cyborg/releases/tag/v1.0.0
