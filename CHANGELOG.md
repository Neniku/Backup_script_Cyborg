# Changelog

Tutte le modifiche principali fatte allo script nel tempo.

---

## [0.5] - 2026-11-06

### Cosa cambia
- Aggiunto `requirements.sh` per controllare al volo se mancano pacchetti sul client e installarli direttamente lanciandolo con `sudo` (supporta Arch/Garuda, Debian/Ubuntu, Fedora e openSUSE). Se manca qualcosa, `Backup_Cyborg.sh` ora si ferma subito all'avvio.
- Passato definitivamente a `7z` per creare i `.zip` (tolti `zip` e `openssl` che erano ridondanti): il vecchio comando `zip -e` di Linux usava ZipCrypto, mentre con `7z -tzip -mem=AES256` i volumi `.zip` e i log locali sono cifrati davvero in AES-256.
- Sistemato il file di log come richiesto dalla consegna: ora si chiama `diario-backup.log`, salva al suo interno l'elenco completo di tutte le cartelle e i file inseriti nel backup e viene allegato direttamente alla mail inviata al sysadmin.
- Pulizia immediata sul client: appena finisce l'upload sul server, gli archivi `.zip` temporanei vengono cancellati subito dal PC locale prima di chiudere il log.
- Migliorata la gestione di SFTP e SMB:
  - Per SFTP cerca da solo le chiavi ECC (`id_ed25519` o `id_ecdsa`), e se invece si usa la password (modalità Umana) passa da `sshpass` senza bloccarsi a chiedere l'input a terminale.
  - Per SMB attivata la firma digitale dei pacchetti (`--signing=required`) lasciando la negoziazione automatica tra SMB3 e SMB2 per non avere problemi di compatibilità con server Windows più vecchi, e nascosta la password dai processi (`PASSWD`).
- Sistemato il generatore delle password casuali a 24 caratteri (prima con `-base64` non uscivano mai i caratteri speciali) e corretto l'ordine dei 5 parametri passati da riga di comando.

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
