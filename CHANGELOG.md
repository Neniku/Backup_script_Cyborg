# Changelog

All notable changes to this project will be documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) — [Semantic Versioning](https://semver.org/)

---

## [Unreleased]

---

## [0.5] - 2026-11-06

### Added
- Nuovo script **`requirements.sh`** per verificare e installare automaticamente (`sudo ./requirements.sh`) tutte le dipendenze necessarie al client su Arch/Garuda (`pacman`), Debian/Ubuntu (`apt-get`), Fedora/RHEL (`dnf`) e openSUSE (`zypper`)
- Controllo bloccante **`check_requirements`** all'avvio di `Backup_Cyborg.sh`: lo script verifica la presenza di tutti i binari richiesti (`7z`, `zip`, `sha256sum`, `openssl`, `curl`, `sftp`, `scp`, `ssh-keygen`, `sshpass`, `smbclient`, `zenity`) prima di partire
- Cifratura simmetrica reale **AES-256** (standard WinZip AE-2 tramite `7z a -tzip -mem=AES256`) per i volumi `.zip` e per l'archivio dei log locali, con suddivisione automatica multi-volume oltre la soglia configurata
- Generazione del file **`diario-backup.log`** con il manifesto ricorsivo completo di tutti i file (`[FILE]` + dimensione in byte) e le directory (`[DIR]`) inclusi nell'archivio
- Allegato automatico di **`diario-backup.log`** (MIME `multipart/mixed`) insieme al report HTML nell'email inviata al sysadmin tramite `curl SMTP`, `sendmail` o `mail`
- Rilevamento automatico delle chiavi crittografiche **ECC** (`~/.ssh/id_ed25519` e `~/.ssh/id_ecdsa`) per SFTP (`PubkeyAcceptedAlgorithms`) e supporto `sshpass` per autenticazione a password (compatibilità traccia Umana)
- Firma digitale obbligatoria dei pacchetti SMB (`--signing=required` / `SMB_SIGNING`) con negoziazione automatica del protocollo (retrocompatibile SMB3/SMB2) e passaggio password tramite variabile d'ambiente `PASSWD` (invisibile in `ps aux`)
- Supporto completo al 5° parametro posizionale CLI (`ftp`, `sftp`, `smb`, `both` oppure indirizzo email) più 6° parametro opzionale per l'email

### Changed
- Snellimento e pulizia generale del codice di `Backup_Cyborg.sh` (unificazione helper SSH/SFTP/SCP e ricerca volumi tramite `find_backup_archives`)
- Aggiornata pipeline GitHub Actions CI (`ci.yml`) con linting ShellCheck anche su `requirements.sh`, test di installazione dipendenze e test funzionale completo di cifratura AES-256 e generazione `diario-backup.log`

### Fixed
- Corretto generatore di password casuali (`generate_random_password`): sostituito il filtro `-base64` (che impediva l'uscita dei caratteri speciali) con uno schema CSPRNG strutturato a 24 caratteri (4 maiuscole, 4 minuscole, 4 cifre, 4 simboli speciali e 8 caratteri misti permutati casualmente)
- Eliminazione immediata e tracciata in `diario-backup.log` dei volumi temporanei sul client subito dopo l'upload (`cleanup_local_archives`)
- Corretta indicizzazione dei parametri posizionali in `process_params` (non vengono più sfalsati se `secrets/config.env` è presente) e aggiunta validazione IP/email anche in modalità GUI Zenity (`--gui`)

---

## [0.3] - 2026-10-15

### Added
- Nuovo script unificato `Backup_Cyborg.sh` (ridotto da 2850 a 830 righe, -70% di codice)
- Supporto invio email con `curl SMTP` nativo (nessun client o MTA locale richiesto)
- Protezione e cifratura locale dei log e del report HTML in archivio `.zip` protetto da `LOG_PASSWORD`
- Supporto completo autenticazione SFTP con chiave privata SSH (`SSH_KEY_PATH`)
- Scansione automatica dei segreti con Gitleaks e CI GitHub Actions
- Guida all'uso `--help` formattata e supporto opzione `-v, --version`
- `.gitignore`, `CHANGELOG.md`, `CYBORG_PASS` env var

### Changed
- Variables renamed: `param1/2/3/4` → `SOURCE_DIR`, `DEST_SERVER`, `REMOTE_USER`, `REMOTE_PASS`
- `smb_path` → `SMB_PATH`
- Password length increased from 16 to 24 characters
- `set -uo pipefail` (dropped `-e`; error handling is done explicitly via `FATAL_ERROR`)

### Fixed
- `cd` replaced with subshells — no longer mutates process working directory (SC2164)
- Safe path handling in compression loop

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

[Unreleased]: https://github.com/Neniku/Backup_script_Cyborg/compare/0.5...HEAD
[0.5]: https://github.com/Neniku/Backup_script_Cyborg/compare/0.3...0.5
[0.3]: https://github.com/Neniku/Backup_script_Cyborg/releases/tag/0.3
[1.0.0]: https://github.com/Neniku/Backup_script_Cyborg/releases/tag/v1.0.0
