# 🤖 Backup Script — Cyborg

> Evolution of [Backup_script_Umano](https://github.com/Neniku/Backup_script_Umano) — a hardened, automated Linux backup solution with encryption, integrity verification, and redundant remote storage.

![Language](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux-FCC624?style=flat&logo=linux&logoColor=black)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat)

---

## What it does

Automates the full backup lifecycle for a local directory:

1. Recursively archives the source (including hidden files) into split ZIP archives
2. Encrypts each archive with a randomly generated password
3. Computes **SHA256 hashes** for integrity verification
4. Uploads redundantly to both **SFTP** and **SMB** destinations
5. Generates an **HTML report** and sends it via email
6. Cleans up local artifacts after successful upload

---

## Key Features

| Feature | Details |
|---|---|
| 🔒 Encryption | AES-256 ZIP with auto-generated password |
| ✅ Integrity | SHA256 hash verification post-upload |
| 📡 Redundancy | Dual upload: SFTP + SMB |
| 🔁 Recovery | Checkpoint/resume system for interrupted backups |
| 🔐 Lock system | Prevents concurrent executions |
| 🖥️ UI | CLI and GUI mode (Zenity) |
| 📊 Reporting | HTML report + email delivery |

---

## Usage

```bash
# CLI mode
./Cyborg_V1.sh /path/to/source 192.168.1.50 user password user@example.com

# GUI mode (requires Zenity)
./Cyborg_V1.sh --gui

# Other options
./Cyborg_V1.sh --help
./Cyborg_V1.sh --cleanup-locks
```

---

## Requirements

```bash
sudo apt install zip openssh-client smbclient zenity mailutils coreutils findutils
```

---

## vs. Umano (v1)

| Aspect | Umano | Cyborg |
|---|---|---|
| Encryption | ❌ | ✅ Auto-generated password |
| Integrity check | Log only | SHA256 hash |
| Remote destination | FTP or SMB | SFTP **+** SMB |
| Recovery | ❌ | ✅ Checkpoint & retry |
| Report | Plain text | HTML + email |

---

## Security Notes

- Password is generated at runtime and never hardcoded
- SFTP preferred over FTP for encrypted transport
- Lock file prevents race conditions on concurrent runs
- Future improvement: externalize secrets via env file or secret manager

---

## Related

- [Backup_script_Umano](https://github.com/Neniku/Backup_script_Umano) — the base version this evolved from

## License

MIT — see [LICENSE](./LICENSE)
