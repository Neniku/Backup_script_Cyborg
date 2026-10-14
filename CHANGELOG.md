# Changelog

All notable changes to this project will be documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) — [Semantic Versioning](https://semver.org/)

---

## [Unreleased]

---

## [0.3] - 2026-10-15

### Added
- Nuovo script unificato `Backup_Cyborg.sh` (ridotto da 2850 a 830 righe, -70% di codice)
- Supporto invio email con `curl SMTP` nativo (nessun client o MTA locale richiesto)
- Protezione e cifratura locale dei log e del report HTML in archivio `.zip` protetto da `LOG_PASSWORD`
- Supporto completo autenticazione SFTP con chiave privata SSH (`SSH_KEY_PATH`)
- Scansione automatica dei segreti con Gitleaks e CI GitHub Actions
- Guida all'uso `--help` formattata e supporto opzione `-v, --version`

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
